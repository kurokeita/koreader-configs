--[[
rounded-folder-covers - give folders in mosaic view real cover images with rounded corners.

Renders each folder cell as a cover image (a `.cover.{jpg,jpeg,png,webp,gif}`
file in the folder, falling back to the first contained book's cached cover)
with rounded-corner overlays, an optional centered folder-name plate, and an
item-count badge in the bottom-right. Adds "Folder name centered" and "Show
folder name" toggles to the Mosaic and detailed list settings menu. Aspect
ratio, fonts, and border thickness are tunable constants at the top of this
file. Requires the rounded.corner.*.svg icons from this repo's icons/ set.

Folder covers are resolved once and cached: the fallback book is picked
deterministically from PT's bookinfo DB (first by filename, instead of
rebuilding the folder's whole item table on every draw), and the chosen
cover is pre-scaled to the cell size and kept in a byte-budgeted blitbuffer
cache, so repeat page draws skip the DB blob read, decompression, and
rescaling entirely. Invalidation goes through the shared registry (see
2-pt-perf.lua): per-file when rows change, full clear plus prewarm restart
when a batch scan or cache wipe finishes; negative results ("no cover")
are not cached while an extraction may still be writing rows. Cover image
files are re-read when their mtime changes, and a deleted cover file is
detected and re-resolved on the next draw.

Targets:
  - coverbrowser @ joshuacant/ProjectTitle 2026.03-v3.7 (MosaicMenuItem,
    FileChooser.getListItem, ptutil.query_cover_paths) via
    userpatch.registerPatchPluginFunc
--]]

local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local IconWidget = require("ui/widget/iconwidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderImage = require("ui/renderimage")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")

local _ = require("gettext")
local Screen = Device.screen
local logger = require("logger")

--========================== Edit your preferences here ================================
local aspect_ratio = 2 / 3          -- adjust aspect ratio of folder cover
local stretch_limit = 50            -- adjust the stretching limit
local fill = false                  -- set true to fill the entire cell ignoring aspect ratio
local file_count_size = 14          -- font size of the file count badge
local folder_font_size = 20         -- font size of the folder name
local folder_border = 0.5           -- thickness of folder border
local folder_name = true            -- set to false to remove folder title from the center
local prewarm_folder_covers = true  -- pre-build all folder covers in the background
local cover_cache_mb = 24           -- memory budget (MB) for pre-scaled folder covers;
                                    -- raise it if your library has many folders
--======================================================================================

local FolderCover = {
    name = ".cover",
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

local function findCover(dir_path)
    local path = dir_path .. "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then return fname end
    end
end

local function getMenuItem(menu, ...)
    local function findItem(sub_items, texts)
        local find = {}
        for _, text in ipairs(type(texts) == "table" and texts or { texts }) do 
            find[text] = true 
        end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then return item end
        end
    end

    local sub_items, item
    for _, texts in ipairs { ... } do
        sub_items = (item or menu).sub_item_table
        if not sub_items then return end
        item = findItem(sub_items, texts)
        if not item then return end
    end
    return item
end

local function toKey(...)
    local keys = {}
    for _, key in pairs { ... } do
        if type(key) == "table" then
            table.insert(keys, "table")
            for k, v in pairs(key) do
                table.insert(keys, tostring(k))
                table.insert(keys, tostring(v))
            end
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "")
end

local orig_FileChooser_getListItem = FileChooser.getListItem
local cached_list = {}
function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
    cached_list[key] = cached_list[key] or orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
    return cached_list[key]
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local Folder = {
    face = {
        border_size = 1,
        alpha = 0.75,
        nb_items_font_size = file_count_size,
        nb_items_margin = Screen:scaleBySize(5),
        dir_max_font_size = folder_font_size,
    },
}

local function svg_widget(icon)
    return IconWidget:new{ icon = icon, alpha = true }
end

local icons = { tl = "rounded.corner.tl", tr = "rounded.corner.tr", bl = "rounded.corner.bl", br = "rounded.corner.br" }
local corners = {}
for k, name in pairs(icons) do
    corners[k] = svg_widget(name)
    if not corners[k] then
        logger.warn("Failed to load SVG icon: " .. tostring(name))
    end
end

-- Shared cache-invalidation registry. Identical installer ships in
-- 2-pt-perf.lua; whichever patch loads first installs it (idempotent), so
-- each works standalone. Listeners receive a list of filepaths, or nil
-- meaning "clear everything". Wraps every PT path that writes bookinfo
-- rows; background extraction notifies at subprocess COMPLETION (rows
-- commit after extractInBackground returns), batch indexing/autoscan
-- notifies when the whole run ends.
local function installInvalidationRegistry(BookInfoManager)
    if BookInfoManager._cache_registry_installed then return end
    BookInfoManager._cache_registry_installed = true
    BookInfoManager._cache_listeners = {}

    local function notify(files)
        for _, listener in ipairs(BookInfoManager._cache_listeners) do
            local ok, err = pcall(listener, files)
            if not ok then
                logger.warn("rounded-folder-covers: cache listener error:", err)
            end
        end
    end
    BookInfoManager._notifyCacheListeners = notify

    local bg_pending_files = nil
    local batch_depth = 0
    function BookInfoManager._extractionMayBeWriting()
        return bg_pending_files ~= nil or batch_depth > 0
    end

    local orig_setProps = BookInfoManager.setBookInfoProperties
    function BookInfoManager:setBookInfoProperties(filepath, props)
        orig_setProps(self, filepath, props)
        notify({ filepath })
    end

    local orig_deleteBookInfo = BookInfoManager.deleteBookInfo
    function BookInfoManager:deleteBookInfo(filepath)
        orig_deleteBookInfo(self, filepath)
        notify({ filepath })
    end

    local orig_deleteDb = BookInfoManager.deleteDb
    function BookInfoManager:deleteDb()
        orig_deleteDb(self)
        notify(nil)
    end

    local orig_extractInBackground = BookInfoManager.extractInBackground
    function BookInfoManager:extractInBackground(files)
        local launched = orig_extractInBackground(self, files)
        if launched then
            bg_pending_files = bg_pending_files or {}
            for i = 1, #files do
                table.insert(bg_pending_files, files[i].filepath or files[i])
            end
        end
        return launched
    end

    local orig_collectSubprocesses = BookInfoManager.collectSubprocesses
    function BookInfoManager:collectSubprocesses()
        orig_collectSubprocesses(self)
        if bg_pending_files and #self.subprocesses_pids == 0 then
            local done = bg_pending_files
            bg_pending_files = nil
            notify(done)
        end
    end

    local orig_extractBooksInDirectory = BookInfoManager.extractBooksInDirectory
    function BookInfoManager:extractBooksInDirectory(...)
        batch_depth = batch_depth + 1
        local ok, err = pcall(orig_extractBooksInDirectory, self, ...)
        batch_depth = math.max(0, batch_depth - 1)
        notify(nil)
        if not ok then error(err, 0) end
    end
end

-- Iterate a file's ancestor directories ("/a/b/c.epub" -> "/a/b", "/a").
local function eachParentDir(filepath, fn)
    local dir = filepath:match("^(.+)/[^/]+$")
    while dir and dir ~= "" do
        fn(dir)
        dir = dir:match("^(.+)/[^/]+$")
    end
end

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem or MosaicMenuItem.rounded_folder_covers then return end

    -- Version guard before any state is touched: a clean logged bail
    -- beats a half-applied patch throwing at plugin load.
    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
    if type(BookInfoManager) ~= "table" or type(BookInfoManager.getBookInfo) ~= "function"
            or type(BookInfoManager.getSetting) ~= "function" then
        logger.warn("rounded-folder-covers: PT internals changed (BookInfoManager upvalue), not patching")
        return
    end
    MosaicMenuItem.rounded_folder_covers = true
    installInvalidationRegistry(BookInfoManager)

    local original_update = MosaicMenuItem.update

    local max_img_w, max_img_h
    -- used by StretchingImageWidget and _setFolderCover, they will hold dimensions after aspect ratio is applied
    local adjusted_w, adjusted_h

    if not MosaicMenuItem.patched_aspect_ratio then
        MosaicMenuItem.patched_aspect_ratio = true

        local local_ImageWidget
        local n = 1
        while true do
            local name, value = debug.getupvalue(MosaicMenuItem.update, n)
            if not name then break end
            if name == "ImageWidget" then
                local_ImageWidget = value
                break
            end
            n = n + 1
        end

        if not local_ImageWidget then
            logger.warn("Could not find ImageWidget in MosaicMenuItem.update closure")
        else
            local setupvalue_n = n
            local orig_MosaicMenuItem_init = MosaicMenuItem.init

            function MosaicMenuItem:init()
                if orig_MosaicMenuItem_init then orig_MosaicMenuItem_init(self) end
                if self.width and self.height then
                    local border_size = Size.border.thin
                    max_img_w = self.width - 2 * border_size
                    max_img_h = self.height - 2 * border_size

                    -- math.floor is applied when messing with the ratio
                    if fill then
                        adjusted_w = max_img_w
                        adjusted_h = max_img_h
                    else
                        local ratio = aspect_ratio
                        if max_img_w / max_img_h > ratio then
                            adjusted_h = max_img_h
                            adjusted_w = math.floor(max_img_h * ratio)
                        else
                            adjusted_w = max_img_w
                            adjusted_h = math.floor(max_img_w / ratio)
                        end
                    end
                end
            end

            local StretchingImageWidget = local_ImageWidget:extend({})
            StretchingImageWidget.init = function(self)
                if local_ImageWidget.init then local_ImageWidget.init(self) end
                if not adjusted_w or not adjusted_h then return end
                
                self.scale_factor = nil
                self.stretch_limit_percentage = stretch_limit
                -- no need to recalculate ratio, we use  adjusted_w/adjusted_h
                self.width = adjusted_w
                self.height = adjusted_h
            end

            debug.setupvalue(MosaicMenuItem.update, setupvalue_n, StretchingImageWidget)
            logger.info("Aspect ratio control applied successfully")
        end
    end

    local function getAspectRatioAdjustedDimensions(width, height, border_size)
        if adjusted_w and adjusted_h then
            return { w = adjusted_w + 2 * border_size, h = adjusted_h + 2 * border_size }
        end
        -- fallback
        local available_w = width - 2 * border_size
        local available_h = height - 2 * border_size
        local ratio = fill and (available_w / available_h) or aspect_ratio
        
        local frame_w, frame_h
        if available_w / available_h > ratio then
            frame_h = available_h
            frame_w = available_h * ratio
        else
            frame_w = available_w
            frame_h = available_w / ratio
        end
        
        return { w = frame_w + 2 * border_size, h = frame_h + 2 * border_size }
    end

    function BooleanSetting(text, name, default)
        self = { text = text }
        self.get = function()
            local setting = BookInfoManager:getSetting(name)
            if default then return not setting end
            return setting
        end
        self.toggle = function() return BookInfoManager:toggleSetting(name) end
        return self
    end

    local settings = {
        name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", true),
        show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", folder_name),
    }

    -- Folder-cover caches. Source picks and pre-scaled buffers survive
    -- across page draws; buffers are dropped to GC on eviction (never
    -- freed explicitly, live widgets may still reference them). The bb
    -- cache is two byte-budgeted generations of nested tables keyed by
    -- source path then size variant, so per-file invalidation is a single
    -- hash delete and memory is bounded in bytes, not entries.
    local folder_src_cache = {} -- dir -> {file=path} | {book=path} | false
    local bb_hot, bb_cold = {}, {} -- srcpath -> { [variant] = BlitBuffer }
    local bb_hot_bytes = 0
    local BB_GEN_MAX_BYTES = math.max(4, cover_cache_mb) / 2 * 1024 * 1024

    local function bbBytes(bb)
        return (tonumber(bb.stride) or 0) * bb:getHeight()
    end

    local function bbCacheGet(srcpath, variant)
        local sizes = bb_hot[srcpath]
        local bb = sizes and sizes[variant]
        if bb then return bb end
        sizes = bb_cold[srcpath]
        bb = sizes and sizes[variant]
        if bb then -- promote, so it survives the next rotation
            sizes[variant] = nil
            local hot = bb_hot[srcpath]
            if not hot then
                hot = {}
                bb_hot[srcpath] = hot
            end
            hot[variant] = bb
            bb_hot_bytes = bb_hot_bytes + bbBytes(bb)
        end
        return bb
    end

    local function bbCachePut(srcpath, variant, bb)
        if bb_hot_bytes >= BB_GEN_MAX_BYTES then
            bb_cold = bb_hot
            bb_hot = {}
            bb_hot_bytes = 0
        end
        local hot = bb_hot[srcpath]
        if not hot then
            hot = {}
            bb_hot[srcpath] = hot
        end
        hot[variant] = bb
        bb_hot_bytes = bb_hot_bytes + bbBytes(bb)
    end

    -- Mirror ImageWidget's stretch_limit_percentage decision so pre-scaled
    -- buffers match what the per-draw scaling used to produce.
    local function stretchDims(bw, bh, target_w, target_h)
        local divergence = math.abs(100 - (bw / bh) / (target_w / target_h) * 100)
        if divergence > stretch_limit then
            local f = math.min(target_w / bw, target_h / bh)
            return math.floor(bw * f), math.floor(bh * f)
        end
        return target_w, target_h
    end

    -- Pick the folder's cover source: a cover.* file if present, otherwise
    -- the first book (by filename) in the folder with a usable cached
    -- cover. Deterministic, and no item-table rebuild per draw. Negative
    -- results are not cached while an extraction may still be writing
    -- rows, so covers filled in by a running scan appear without restart.
    local function resolveBookSource(dir_path)
        local ptutil = require("ptutil")
        local ok, db_res = pcall(ptutil.query_cover_paths, dir_path, false)
        if ok and db_res then
            local dirs, files = db_res[1], db_res[2]
            for i, fn in ipairs(files or {}) do
                local fullpath = dirs[i] .. fn
                if util.fileExists(fullpath) then
                    local bi = BookInfoManager:getBookInfo(fullpath, false)
                    if bi and bi.has_cover and bi.cover_fetched and not bi.ignore_cover then
                        return { book = fullpath }
                    end
                end
            end
        end
        return nil
    end

    local function resolveSource(dir_path)
        local cover_file = findCover(dir_path)
        if cover_file then return { file = cover_file } end
        return resolveBookSource(dir_path) or false
    end

    local function getSource(dir_path)
        local src = folder_src_cache[dir_path]
        if src == nil then
            src = resolveSource(dir_path)
            if src ~= false or not BookInfoManager._extractionMayBeWriting() then
                folder_src_cache[dir_path] = src
            end
        end
        return src
    end

    local function fileCoverBB(file, target_w, target_h)
        local mtime = lfs.attributes(file, "modification") or 0
        local variant = mtime .. "|" .. target_w .. "x" .. target_h
        local bb = bbCacheGet(file, variant)
        if bb then return bb end
        local ok, native = pcall(RenderImage.renderImageFile, RenderImage, file)
        if not ok or not native then return nil end
        local w, h = stretchDims(native:getWidth(), native:getHeight(), target_w, target_h)
        bb = RenderImage:scaleBlitBuffer(native, w, h, true) -- frees the native decode
        bbCachePut(file, variant, bb)
        return bb
    end

    local function bookCoverBB(fullpath, target_w, target_h)
        local variant = target_w .. "x" .. target_h
        local bb = bbCacheGet(fullpath, variant)
        if bb then return bb end
        local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
        if not bookinfo or not bookinfo.cover_bb then return nil end
        if bookinfo.ignore_cover then
            bookinfo.cover_bb:free()
            return nil
        end
        local w, h = stretchDims(bookinfo.cover_w, bookinfo.cover_h, target_w, target_h)
        bb = RenderImage:scaleBlitBuffer(bookinfo.cover_bb, w, h, true) -- frees the 600px original
        bbCachePut(fullpath, variant, bb)
        return bb
    end

    local function getFolderCoverBB(dir_path, target_w, target_h)
        -- floor so cache keys match between draw-time and prewarm callers
        target_w, target_h = math.floor(target_w), math.floor(target_h)
        local src = getSource(dir_path)
        if not src then return nil end
        if src.file and lfs.attributes(src.file, "mode") ~= "file" then
            -- the cover file vanished: re-resolve from scratch
            folder_src_cache[dir_path] = nil
            src = getSource(dir_path)
            if not src then return nil end
        end
        local bb
        if src.file then
            bb = fileCoverBB(src.file, target_w, target_h)
            if not bb then
                -- unreadable/corrupt cover image: fall back to a book
                -- cover, like the pre-cache behavior did
                src = resolveBookSource(dir_path) or false
                if src ~= false or not BookInfoManager._extractionMayBeWriting() then
                    folder_src_cache[dir_path] = src
                end
                if not src then return nil end
            end
        end
        if not bb and src.book then
            bb = bookCoverBB(src.book, target_w, target_h)
            if not bb then
                -- transient decode failure: drop the pick so the next
                -- draw retries instead of pinning a wrong negative
                folder_src_cache[dir_path] = nil
                return nil
            end
        end
        return bb
    end

    -- Background pre-warm: walk every folder under the home directory and
    -- build its cover at the current grid cell size, expanding a few
    -- directories and warming a small batch of covers per scheduler tick
    -- (nothing blocks the draw path; the tree walk itself is incremental).
    -- Keyed by cell dimensions: changing items-per-page restarts the walk
    -- at the new size. The walk keeps running while a book is open, by
    -- design, so the browser is warm when the user returns.
    local UIManager = require("ui/uimanager")
    local prewarm = {
        dims_key = nil,
        pending = nil,  -- directories not yet expanded
        queue = nil,    -- folders awaiting cover warming
        next_idx = 1,
        running = false,
        persist_cell = nil, -- cell dims to save from the next tick (off the draw path)
        warmed = 0,
    }
    local PREWARM_BATCH = 2       -- folders warmed per tick
    local PREWARM_EXPAND_DIRS = 4 -- directories expanded per tick
    local PREWARM_INTERVAL = 0.2  -- seconds between ticks

    local function prewarmExpand()
        local show_hidden = G_reader_settings and G_reader_settings:isTrue("show_hidden")
        local expanded = 0
        while prewarm.pending and #prewarm.pending > 0 and expanded < PREWARM_EXPAND_DIRS do
            local d = table.remove(prewarm.pending, 1) -- breadth-first: top levels warm first
            expanded = expanded + 1
            local ok, iter, dir_obj = pcall(lfs.dir, d)
            if ok then
                for entry in iter, dir_obj do
                    if entry ~= "." and entry ~= ".."
                            and (show_hidden or not entry:match("^%."))
                            and not entry:match("%.sdr$") then
                        local fullpath = d .. "/" .. entry
                        if lfs.attributes(fullpath, "mode") == "directory" then
                            table.insert(prewarm.queue, fullpath)
                            table.insert(prewarm.pending, fullpath)
                        end
                    end
                end
            end
        end
    end

    local function prewarmStep()
        -- persist the cell size here, off the draw path
        if prewarm.persist_cell then
            if BookInfoManager:getSetting("rfc_prewarm_cell") ~= prewarm.persist_cell then
                BookInfoManager:saveSetting("rfc_prewarm_cell", prewarm.persist_cell)
            end
            prewarm.persist_cell = nil
        end

        prewarmExpand()

        for _ = 1, PREWARM_BATCH do
            local dir_path = prewarm.queue and prewarm.queue[prewarm.next_idx]
            if not dir_path then break end
            prewarm.next_idx = prewarm.next_idx + 1
            prewarm.warmed = prewarm.warmed + 1
            if getSource(dir_path) then
                getFolderCoverBB(dir_path, prewarm.w, prewarm.h)
            else
                -- no cover of our own: warm PT's collage fallback instead
                -- (cached by 2-pt-perf when installed)
                local ptutil = require("ptutil")
                pcall(ptutil.getSubfolderCoverImages, dir_path, prewarm.pt_w, prewarm.pt_h)
            end
        end

        if (not prewarm.pending or #prewarm.pending == 0)
                and (not prewarm.queue or prewarm.next_idx > #prewarm.queue) then
            logger.info(string.format("rounded-folder-covers: prewarm done, %d folders at %s",
                prewarm.warmed, tostring(prewarm.dims_key)))
            prewarm.running = false
            return
        end
        UIManager:scheduleIn(PREWARM_INTERVAL, prewarmStep)
    end

    local function startPrewarmQueue()
        local home_dir = G_reader_settings:readSetting("home_dir")
        if not home_dir or lfs.attributes(home_dir, "mode") ~= "directory" then
            return -- no home folder set, nothing to walk
        end
        prewarm.pending = { home_dir }
        prewarm.queue = {}
        prewarm.next_idx = 1
        prewarm.warmed = 0
        logger.info("rounded-folder-covers: prewarm starting at " .. tostring(prewarm.dims_key))
        if not prewarm.running then
            prewarm.running = true
            UIManager:scheduleIn(PREWARM_INTERVAL, prewarmStep)
        end
    end

    local function prewarmHasWork()
        return (prewarm.pending and #prewarm.pending > 0)
            or (prewarm.queue and prewarm.next_idx <= #prewarm.queue)
    end

    -- Called from every folder draw with the current cell size. Rebuilds
    -- the queue when the size changes, restarts a paused walk otherwise.
    -- The raw cell size is persisted (from the scheduler tick, not here)
    -- so the startup job below can re-derive everything next session.
    local function kickPrewarm(cell_w, cell_h)
        local frame_dimen = getAspectRatioAdjustedDimensions(cell_w, cell_h, 0)
        local fw, fh = math.floor(frame_dimen.w), math.floor(frame_dimen.h)
        local dims_key = fw .. "x" .. fh
        if prewarm.dims_key ~= dims_key then
            prewarm.dims_key = dims_key
            prewarm.w, prewarm.h = fw, fh
            prewarm.pt_w = math.floor(cell_w - 2 * Size.border.thin) -- dims PT's update passes
            prewarm.pt_h = math.floor(cell_h - 2 * Size.border.thin) -- to getSubfolderCoverImages
            prewarm.persist_cell = math.floor(cell_w) .. "," .. math.floor(cell_h)
            startPrewarmQueue()
        elseif not prewarm.running and prewarmHasWork() then
            prewarm.running = true
            UIManager:scheduleIn(PREWARM_INTERVAL, prewarmStep)
        end
    end

    -- Startup pre-warm: when PT's "Scan home folder for new books
    -- automatically" is enabled, also build the folder-cover cache right
    -- after startup, in the background, re-deriving dimensions from the
    -- persisted cell size of the last session. Works even when KOReader
    -- starts straight into a book; a later folder draw with different
    -- dimensions simply restarts the walk.
    if prewarm_folder_covers and BookInfoManager:getSetting("autoscan_on_eject") then
        local cell = BookInfoManager:getSetting("rfc_prewarm_cell")
        local cw, ch
        if type(cell) == "string" then
            cw, ch = cell:match("^(%d+),(%d+)$")
        end
        if cw then
            UIManager:scheduleIn(10, function() -- let startup and autoscan settle first
                if prewarm.dims_key then return end -- a folder draw beat us to it
                kickPrewarm(tonumber(cw), tonumber(ch))
            end)
        end
    end

    -- Scoped invalidation via the shared registry (see 2-pt-perf.lua):
    -- changed files drop their own buffers and the source pick of any
    -- ancestor folder; a full clear (cache emptied, batch scan finished)
    -- also restarts the pre-warm so the new covers get rebuilt.
    table.insert(BookInfoManager._cache_listeners, function(files)
        if not files then
            folder_src_cache = {}
            bb_hot, bb_cold = {}, {}
            bb_hot_bytes = 0
            if prewarm_folder_covers and prewarm.dims_key then
                startPrewarmQueue()
            end
            return
        end
        for i = 1, #files do
            local filepath = files[i]
            if type(filepath) == "string" then
                bb_hot[filepath] = nil -- bytes accounting drifts low; only delays rotation
                bb_cold[filepath] = nil
                eachParentDir(filepath, function(dir)
                    folder_src_cache[dir] = nil
                end)
            end
        end
    end)

    function MosaicMenuItem:update(...)
        -- When this patch will replace a folder cell's cover, PT's own
        -- auto folder-cover collage (up to 4 cover decompressions per
        -- cold tile) would be built only to be thrown away. Resolve our
        -- cover source first (cached), and suppress PT's collage for the
        -- duration of the original update by toggling its in-memory
        -- setting (the DB-stored value is never touched). Folders we
        -- cannot cover keep PT's collage as the visual fallback.
        local will_replace_cover = false
        local dir_path
        if not (self.entry.is_file or self.entry.file)
                and not self.menu.no_refresh_covers and self.do_cover_image
                and not self._foldercover_processed and self.mandatory then
            dir_path = self.entry and self.entry.path
            if dir_path then
                if prewarm_folder_covers then
                    kickPrewarm(self.width, self.height)
                end
                will_replace_cover = getSource(dir_path) and true or false
            end
        end

        -- The setting toggle must survive an error in original_update:
        -- a leaked true would silently disable PT collages session-wide
        -- (and the menu would show, and could persist, the wrong state).
        local toggled = false
        local saved_setting
        if will_replace_cover then
            if not BookInfoManager.settings then
                BookInfoManager:getSetting("disable_auto_foldercovers") -- force settings load
            end
            if BookInfoManager.settings then
                saved_setting = BookInfoManager.settings.disable_auto_foldercovers
                BookInfoManager.settings.disable_auto_foldercovers = true
                toggled = true
            end
        end
        local ok, err = pcall(original_update, self, ...)
        if toggled then
            BookInfoManager.settings.disable_auto_foldercovers = saved_setting
        end
        if not ok then error(err, 0) end

        if not will_replace_cover then return end
        self._foldercover_processed = true

        local frame_dimen = getAspectRatioAdjustedDimensions(self.width, self.height, 0)
        local bb = getFolderCoverBB(dir_path, frame_dimen.w, frame_dimen.h)
        if bb then
            self:_setFolderCover { bb = bb }
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        local border_size = 0
        local frame_dimen = getAspectRatioAdjustedDimensions(self.width, self.height, border_size)
        -- img.bb is pre-scaled to fit within frame_dimen and owned
        -- by the cover cache, so the widget must not dispose of it
        local image = ImageWidget:new { image = img.bb, image_disposable = false }
        
        local image_widget = FrameContainer:new {
            padding = 0, bordersize = border_size, image, overlap_align = "center",
        }

        local image_size = image:getSize()
        local directory = self:_getTextBox { w = image_size.w, h = image_size.h }

        local folder_name_widget
        if settings.show_folder_name.get() then
            folder_name_widget = (settings.name_centered.get() and CenterContainer or TopContainer):new {
                dimen = frame_dimen,
                FrameContainer:new {
                    padding = -1, bordersize = 1,
                    AlphaContainer:new { alpha = Folder.face.alpha, directory },
                },
                overlap_align = "center",
            }
        else
            folder_name_widget = VerticalSpan:new { width = 0 }
        end
        
        local nbitems_widget
        local item_count = 0
        if self.mandatory then
            local count_str = self.mandatory:match("(%d+)")
            if count_str then item_count = tonumber(count_str) end
        end
        
        if item_count > 0 then
            local nbitems = TextWidget:new {
                text = tostring(item_count),
                face = Font:getFace("cfont", Folder.face.nb_items_font_size),
                bold = true, padding = 0
            }
            
            local nb_size = math.max(nbitems:getSize().w, nbitems:getSize().h)
            nbitems_widget = BottomContainer:new {
                dimen = frame_dimen,
                RightContainer:new {
                    dimen = {
                        w = frame_dimen.w - Folder.face.nb_items_margin,
                        h = nb_size + Folder.face.nb_items_margin * 2,
                    },
                    FrameContainer:new {
                        padding = 2, bordersize = Folder.face.border_size,
                        radius = math.ceil(nb_size), background = Blitbuffer.COLOR_GRAY_E,
                        CenterContainer:new { dimen = { w = nb_size, h = nb_size }, nbitems },
                    },
                },
                overlap_align = "center",
            }
        else
            nbitems_widget = VerticalSpan:new { width = 0 }
        end
        
        self._folder_frame_dimen = frame_dimen
        self._folder_image_size = image_size
        
        local widget = CenterContainer:new {
            dimen = { w = self.width, h = self.height },
            CenterContainer:new {
                dimen = { w = self.width, h = self.height },
                OverlapGroup:new {
                    dimen = frame_dimen,
                    image_widget,
                    folder_name_widget,
                    nbitems_widget,
                },
            },
        }
        
        if self._underline_container[1] then
            self._underline_container[1]:free()
        end
        self._underline_container[1] = widget
    end

    function MosaicMenuItem:_getTextBox(dimen)
        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end
        text = BD.directory(capitalize(text))
        
        local available_height = dimen.h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end
        return directory
    end

    local orig_MosaicMenuItem_paintTo = MosaicMenuItem.paintTo
    function MosaicMenuItem:paintTo(bb, x, y)
        orig_MosaicMenuItem_paintTo(self, bb, x, y)

        if not self._folder_frame_dimen or not self._folder_image_size then return end
        if self.entry.is_file or self.entry.file then return end

        local frame_dimen = self._folder_frame_dimen
        local image_size = self._folder_image_size
        
        local fx = x + math.floor((self.width - frame_dimen.w) / 2)
        local fy = y + math.floor((self.height - frame_dimen.h) / 2)
        local image_x = fx + math.floor((frame_dimen.w - image_size.w) / 2)
        local image_y = fy + math.floor((frame_dimen.h - image_size.h) / 2)
        
        local cover_border = Screen:scaleBySize(folder_border)
        bb:paintBorder(image_x, image_y, image_size.w, image_size.h, cover_border, Blitbuffer.COLOR_BLACK, 0, false)

        local TL, TR, BL, BR = corners.tl, corners.tr, corners.bl, corners.br
        if not (TL and TR and BL and BR) then return end

        local function _sz(w)
            if w.getSize then local s = w:getSize(); return s.w, s.h end
            if w.getWidth then return w:getWidth(), w:getHeight() end
            return 0, 0
        end

        local tlw, tlh = _sz(TL)
        local trw, trh = _sz(TR)
        local blw, blh = _sz(BL)
        local brw, brh = _sz(BR)

        if TL.paintTo then TL:paintTo(bb, image_x, image_y) else bb:blitFrom(TL, image_x, image_y) end
        if TR.paintTo then TR:paintTo(bb, image_x + image_size.w - trw, image_y) else bb:blitFrom(TR, image_x + image_size.w - trw, image_y) end
        if BL.paintTo then BL:paintTo(bb, image_x, image_y + image_size.h - blh) else bb:blitFrom(BL, image_x, image_y + image_size.h - blh) end
        if BR.paintTo then BR:paintTo(bb, image_x + image_size.w - brw, image_y + image_size.h - brh) else bb:blitFrom(BR, image_x + image_size.w - brw, image_y + image_size.h - brh) end
    end

    local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu
    function plugin:addToMainMenu(menu_items)
        orig_CoverBrowser_addToMainMenu(self, menu_items)
        if menu_items.filebrowser_settings == nil then return end

        local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
        if item then
            item.sub_item_table[#item.sub_item_table].separator = true
            for i, setting in pairs(settings) do
                if not getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), setting.text) then
                    table.insert(item.sub_item_table, {
                        text = setting.text,
                        checked_func = function() return setting.get() end,
                        callback = function()
                            setting.toggle()
                            self.ui.file_chooser:updateItems()
                        end,
                    })
                end
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
