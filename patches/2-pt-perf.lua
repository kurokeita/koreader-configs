--[[
pt-perf - Project: Title file-browser performance fixes.

Two independent fixes in one patch (formerly 2-pt-bookinfo-cache.lua and
2-pt-foldercover-perf.lua). Each section version-guards itself and skips
with a log warning if PT's internals have moved; neither changes anything
visual except that auto folder-cover thumbnails stop reshuffling between
page draws.

Section 1 - blob-free metadata queries and an in-memory cache:
PT's single prepared SELECT fetches every bookinfo column, including the
zstd-compressed cover blob (50-200KB per row), even for metadata-only
lookups (get_cover=false). Those lookups are everywhere on the hot path:
MosaicMenuItem:paintTo re-queries on every repaint of every visible book,
and PT's custom sort collates query once per file each time a folder's
item table is generated. This section wraps BookInfoManager:getBookInfo so
metadata-only lookups use a separate prepared statement that excludes the
cover columns and are served from a bounded in-memory cache keyed by
filepath (callers get a shallow copy because PT mutates returned tables).
Books not yet in the DB are never cached, so background extraction results
still show up. Cover lookups (get_cover=true) and Kobo virtual-library
paths pass through untouched.

Section 2 - cached auto-generated folder covers:
PT rebuilds every folder tile from scratch on every page draw: a directory
scan looking for a cover file, one or two throwaway SQLite connections
running `ORDER BY RANDOM()` queries (a full scan-and-sort of every cached
book under the folder), and up to four cover blobs zstd-decompressed and
rescaled. This section replaces the folder-cover helpers in ptutil to
query deterministically on the dir_filename index, reuse BookInfoManager's
shared DB connection, cache the chosen cover paths per folder and the
scaled thumbnails per book+size, and cache cover-file probe results and
image dimensions. Invalidation is scoped: extracting or refreshing books
drops only the affected files' thumbnails and their ancestor folders'
cached picks; emptying the cache database clears everything. Evicted
thumbnails are reclaimed by GC (never freed explicitly, as live widgets
may still reference them).

Targets:
  - coverbrowser @ joshuacant/ProjectTitle 2026.03-v3.7
    (BookInfoManager.getBookInfo/getDocProps/closeDbConnection and
    cache-mutating methods wrapped, column layout discovered via the
    BOOKINFO_COLS_SET upvalue; ptutil.query_cover_paths,
    ptutil.build_cover_images, ptutil.getSubfolderCoverImages,
    ptutil.getFolderCover replaced)
--]]

local userpatch = require("userpatch")
local logger = require("logger")

-- Section 1: blob-free metadata queries and an in-memory cache for
-- BookInfoManager lookups.
local function patchBookInfoCache(plugin)
    local BookInfoManager = require("bookinfomanager")
    if BookInfoManager._bookinfo_cache_patched then return end

    -- Discover the column layout from PT itself, and bail out if the
    -- schema assumptions this patch relies on no longer hold.
    local COLS = userpatch.getUpValue(BookInfoManager.getBookInfo, "BOOKINFO_COLS_SET")
    if type(COLS) ~= "table" or COLS[13] ~= "pages" or COLS[20] ~= "description"
            or COLS[#COLS] ~= "cover_bb_data" then
        logger.warn("pt-perf: BookInfoManager internals changed, not patching metadata cache")
        return
    end
    BookInfoManager._bookinfo_cache_patched = true

    local DocumentRegistry = require("document/documentregistry")
    local lfs = require("libs/libkoreader-lfs")
    local util = require("util")

    local exclude = { cover_bb_type = true, cover_bb_stride = true, cover_bb_data = true }
    local meta_cols = {}
    for _, col in ipairs(COLS) do
        if not exclude[col] then
            table.insert(meta_cols, col)
        end
    end
    local META_SELECT_SQL = "SELECT " .. table.concat(meta_cols, ",") ..
        " FROM bookinfo WHERE directory=? AND filename=? AND in_progress=0;"

    local KOBO_VIRTUAL_PREFIX = "KOBO_VIRTUAL://"

    -- filepath -> canonical metadata table. Bounded; cleared wholesale on
    -- overflow or invalidation (rebuilding is cheap with the blob-free
    -- statement).
    local meta_cache = {}
    local meta_count = 0
    local META_CACHE_MAX = 1000

    local function cacheClear()
        meta_cache = {}
        meta_count = 0
    end

    local function shallowCopy(t)
        local c = {}
        for k, v in pairs(t) do c[k] = v end
        return c
    end

    -- The prepared statement must die with the connection it was prepared
    -- on (PT closes and reopens the shared connection around subprocess
    -- forks and on browser close).
    local orig_closeDbConnection = BookInfoManager.closeDbConnection
    function BookInfoManager:closeDbConnection()
        self.get_meta_stmt = nil
        orig_closeDbConnection(self)
    end

    local orig_getBookInfo = BookInfoManager.getBookInfo
    function BookInfoManager:getBookInfo(filepath, get_cover)
        if get_cover or type(filepath) ~= "string"
                or filepath:sub(1, #KOBO_VIRTUAL_PREFIX) == KOBO_VIRTUAL_PREFIX then
            return orig_getBookInfo(self, filepath, get_cover)
        end
        local cached = meta_cache[filepath]
        if cached then
            return shallowCopy(cached)
        end
        -- Directories and unsupported files get upstream's synthetic
        -- (DB-less) bookinfo table.
        if lfs.attributes(filepath, "mode") == "directory"
                or not DocumentRegistry:hasProvider(filepath) then
            return orig_getBookInfo(self, filepath, get_cover)
        end

        local directory, filename = util.splitFilePathName(filepath)
        self:openDbConnection()
        if not self.get_meta_stmt then
            self.get_meta_stmt = self.db_conn:prepare(META_SELECT_SQL)
        end
        local row = self.get_meta_stmt:bind(directory, filename):step()
        if not row then
            self.get_meta_stmt:clearbind():reset()
            return nil -- not extracted yet; never cached, so extraction results show up
        end
        local bookinfo = {}
        for num, col in ipairs(meta_cols) do
            if col == "pages" or col == "cover_w" or col == "cover_h" then
                bookinfo[col] = tonumber(row[num]) -- cdata<int64_t> to Lua number
            else
                bookinfo[col] = row[num]
            end
        end
        self.get_meta_stmt:clearbind():reset()

        if meta_count >= META_CACHE_MAX then
            cacheClear()
        end
        meta_cache[filepath] = bookinfo
        meta_count = meta_count + 1
        return shallowCopy(bookinfo)
    end

    function BookInfoManager:getDocProps(filepath)
        local info = self:getBookInfo(filepath, false)
        if not info or info._no_provider then return nil end
        local props = {}
        for i = 13, 20 do -- pages .. description, same slice as upstream
            props[COLS[i]] = info[COLS[i]]
        end
        props.pages = tonumber(props.pages)
        return props
    end

    -- Invalidate on anything that rewrites existing rows. New rows (first
    -- extraction) need no invalidation because misses are never cached.
    for _, method in ipairs({ "setBookInfoProperties", "deleteBookInfo", "deleteDb" }) do
        local orig = BookInfoManager[method]
        BookInfoManager[method] = function(self, ...)
            cacheClear()
            return orig(self, ...)
        end
    end

    logger.info("pt-perf: blob-free metadata queries and caching enabled")
end

-- Section 2: cache PT's auto-generated folder covers.
local function patchFolderCovers(plugin)
    local ptutil = require("ptutil")
    local BookInfoManager = require("bookinfomanager")

    if ptutil._foldercover_perf_patched then return end

    -- Version guard: bail out if PT's internals moved.
    for _, fn in ipairs({ "query_cover_paths", "build_cover_images",
                          "getSubfolderCoverImages", "getFolderCover",
                          "build_diagonal_stack", "build_grid",
                          "get_thumbnail_size", "findCover" }) do
        if type(ptutil[fn]) ~= "function" then
            logger.warn("pt-perf: ptutil." .. fn .. " not found, not patching folder covers")
            return
        end
    end
    ptutil._foldercover_perf_patched = true

    -- ptutil.make_sql_safe only exists in PT releases newer than
    -- 2026.03-v3.7; inline the same escaping as a fallback.
    local make_sql_safe = ptutil.make_sql_safe or function(s)
        s = s:gsub("'", "''") -- use '' inside '
        s = s:gsub(";", "_")  -- ljsqlite3 splits commands on semicolons
        return s
    end

    local Blitbuffer = require("ffi/blitbuffer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local RenderImage = require("ui/renderimage")
    local Size = require("ui/size")
    local util = require("util")

    -- folder path -> exec result ({dirs, filenames}) of chosen covers, or
    -- false when the folder yielded none (so we don't re-query every draw)
    local folder_covers_cache = {}
    -- folder path -> cover file path found by findCover, or false for none
    local cover_file_cache = {}
    -- image file path -> { w, h } original dimensions
    local img_dims_cache = {}
    -- "bookpath|WxH" -> pre-scaled cover BlitBuffer, in two generations:
    -- inserts go to the hot table; when it fills, it becomes the cold one
    -- and the oldest generation is dropped. Keeps the most recent ~100-200
    -- thumbs without ever wholesale-clearing on a page draw. We never free
    -- the buffers explicitly: a live ImageWidget may still hold one, so
    -- eviction just drops the reference and GC reclaims it (cover bbs are
    -- allocated, see BookInfoManager:getBookInfo).
    local thumb_hot, thumb_cold = {}, {}
    local thumb_hot_count = 0
    local THUMB_GEN_MAX = 100

    local function thumbCacheGet(key)
        local bb = thumb_hot[key]
        if bb then return bb end
        bb = thumb_cold[key]
        if bb then -- promote, so it survives the next rotation
            thumb_cold[key] = nil
            thumb_hot[key] = bb
            thumb_hot_count = thumb_hot_count + 1
        end
        return bb
    end

    local function thumbCachePut(key, bb)
        if thumb_hot_count >= THUMB_GEN_MAX then
            thumb_cold = thumb_hot
            thumb_hot = {}
            thumb_hot_count = 0
        end
        thumb_hot[key] = bb
        thumb_hot_count = thumb_hot_count + 1
    end

    local function clearCaches()
        folder_covers_cache = {}
        cover_file_cache = {}
        img_dims_cache = {}
        thumb_hot, thumb_cold = {}, {}
        thumb_hot_count = 0
    end

    -- Targeted invalidation: drop the given files' thumbnails and the
    -- cached cover picks of any folder containing them. Called when PT
    -- (re-)extracts or deletes individual books; everything else stays
    -- warm. `files` entries are {filepath=...} tables or plain strings.
    local function invalidateForFiles(files)
        local dropped = 0
        for i = 1, #files do
            local filepath = type(files[i]) == "table" and files[i].filepath or files[i]
            if type(filepath) == "string" then
                local thumb_prefix = filepath .. "|"
                for _, gen in ipairs({ thumb_hot, thumb_cold }) do
                    for key in pairs(gen) do
                        if key:sub(1, #thumb_prefix) == thumb_prefix then
                            gen[key] = nil -- clearing existing keys during pairs() is allowed
                        end
                    end
                end
                for folder in pairs(folder_covers_cache) do
                    local folder_prefix = folder .. "/"
                    if filepath:sub(1, #folder_prefix) == folder_prefix then
                        folder_covers_cache[folder] = nil
                        dropped = dropped + 1
                    end
                end
            end
        end
        if dropped > 0 then
            logger.info("pt-perf: invalidated", dropped,
                "cached folder cover(s) after bookinfo update")
        end
    end

    -- Deterministic query on the dir_filename index, shared connection.
    -- LIMIT 8 leaves headroom over the 4 covers needed in case some files
    -- were deleted since extraction.
    function ptutil.query_cover_paths(folder, include_subfolders)
        if not util.directoryExists(folder) then return nil end
        local folder_safe = make_sql_safe(folder)
        local query
        if include_subfolders then
            query = string.format([[
                SELECT directory, filename FROM bookinfo
                WHERE directory LIKE '%s/%%' AND has_cover = 'Y'
                ORDER BY directory, filename LIMIT 8;
                ]], folder_safe)
        else
            query = string.format([[
                SELECT directory, filename FROM bookinfo
                WHERE directory = '%s/' AND has_cover = 'Y'
                ORDER BY filename LIMIT 8;
                ]], folder_safe)
        end
        BookInfoManager:openDbConnection()
        return BookInfoManager.db_conn:exec(query)
    end

    local function getThumb(fullpath, max_img_w, max_img_h)
        local key = fullpath .. "|" .. math.floor(max_img_w) .. "x" .. math.floor(max_img_h)
        local bb = thumbCacheGet(key)
        if bb then return bb end
        local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
        if not bookinfo or not bookinfo.cover_bb then return nil end
        local _, _, scale_factor = BookInfoManager.getCachedCoverSize(
            bookinfo.cover_w, bookinfo.cover_h, max_img_w, max_img_h)
        bb = RenderImage:scaleBlitBuffer(bookinfo.cover_bb,
            math.floor(bookinfo.cover_w * scale_factor),
            math.floor(bookinfo.cover_h * scale_factor), true) -- frees the 600px original
        thumbCachePut(key, bb)
        return bb
    end

    -- Same output as upstream, but covers come from the thumbnail cache
    -- and the widgets reference cached buffers without owning them.
    function ptutil.build_cover_images(db_res, max_w, max_h)
        local covers = {}
        if db_res then
            local directories = db_res[1]
            local filenames = db_res[2]
            local max_img_w, max_img_h = ptutil.get_thumbnail_size(max_w, max_h)
            for i, filename in ipairs(filenames) do
                local fullpath = directories[i] .. filename
                if util.fileExists(fullpath) then
                    local bb = getThumb(fullpath, max_img_w, max_img_h)
                    if bb then
                        local border_total = (Size.border.thin * 2)
                        table.insert(covers, FrameContainer:new {
                            width = bb:getWidth() + border_total,
                            height = bb:getHeight() + border_total,
                            margin = 0,
                            padding = 0,
                            radius = Size.radius.default,
                            bordersize = Size.border.thin,
                            color = Blitbuffer.COLOR_GRAY_3,
                            background = Blitbuffer.COLOR_GRAY_3,
                            ImageWidget:new {
                                image = bb,
                                image_disposable = false, -- cache owns it
                            },
                        })
                    end
                    if #covers == 4 then break end
                end
            end
        end
        return covers
    end

    function ptutil.getSubfolderCoverImages(filepath, max_w, max_h)
        local images
        local cached = folder_covers_cache[filepath]
        if cached ~= nil then
            if cached == false then return nil end
            images = ptutil.build_cover_images(cached, max_w, max_h)
        else
            -- First visit: prefer covers from the immediate folder, fall
            -- back to the whole subtree (same two-stage logic as upstream).
            local db_res = ptutil.query_cover_paths(filepath, false)
            images = ptutil.build_cover_images(db_res, max_w, max_h)
            if #images < 4 then
                db_res = ptutil.query_cover_paths(filepath, true)
                images = ptutil.build_cover_images(db_res, max_w, max_h)
            end
            folder_covers_cache[filepath] = (#images > 0) and db_res or false
        end
        if #images == 0 then return nil end -- cached files may have vanished
        if BookInfoManager:getSetting("use_stacked_foldercovers") then
            return ptutil.build_diagonal_stack(images, max_w, max_h)
        else
            return ptutil.build_grid(images, max_w, max_h)
        end
    end

    -- Cover-file folder tiles: cache the directory probe and the image
    -- dimensions so each draw skips the lfs.dir scan and the throwaway
    -- dimension-probing decode.
    function ptutil.getFolderCover(filepath, max_img_w, max_img_h, pt_cover_path)
        local folder_image_file = pt_cover_path
        if not folder_image_file then
            local cached = cover_file_cache[filepath]
            if cached == nil then
                cached = ptutil.findCover(filepath) or false
                cover_file_cache[filepath] = cached
            end
            folder_image_file = cached or nil
        end
        if folder_image_file == nil then return nil end

        local success, folder_image = pcall(function()
            local dims = img_dims_cache[folder_image_file]
            if not dims then
                local temp_image = ImageWidget:new { file = folder_image_file, scale_factor = 1 }
                temp_image:_render()
                dims = { w = temp_image:getOriginalWidth(), h = temp_image:getOriginalHeight() }
                temp_image:free()
                img_dims_cache[folder_image_file] = dims
            end
            local scale_to_fill = 0
            if dims.w and dims.h then
                scale_to_fill = math.max(max_img_w / dims.w, max_img_h / dims.h)
            end
            return ImageWidget:new {
                file = folder_image_file,
                width = max_img_w,
                height = max_img_h,
                scale_factor = scale_to_fill,
                center_x_ratio = 0.5,
                center_y_ratio = 0.5,
            }
        end)
        if success then
            return FrameContainer:new {
                width = max_img_w,
                height = max_img_h,
                margin = 0,
                padding = 0,
                bordersize = 0,
                folder_image,
            }
        else
            logger.info("pt-perf: folder cover failed to render:", folder_image_file)
            local size_mult = 1.25
            local _, _, scale_factor = BookInfoManager.getCachedCoverSize(250, 500,
                max_img_w * size_mult, max_img_h * size_mult)
            return FrameContainer:new {
                width = max_img_w * size_mult,
                height = max_img_h * size_mult,
                margin = 0,
                padding = 0,
                bordersize = 0,
                ImageWidget:new {
                    file = ptutil.getPluginDir() .. "/resources/file-unsupported.svg",
                    alpha = true,
                    scale_factor = scale_factor,
                    original_in_nightmode = false,
                },
            }
        end
    end

    -- Invalidate when PT mutates the bookinfo cache, scoped to the files
    -- actually touched: background extraction may add covers to their
    -- containing folders, deletions/refreshes may change them. Only
    -- emptying the whole cache database clears everything.
    local orig_extractInBackground = BookInfoManager.extractInBackground
    function BookInfoManager:extractInBackground(files)
        invalidateForFiles(files)
        return orig_extractInBackground(self, files)
    end

    local orig_deleteBookInfo = BookInfoManager.deleteBookInfo
    function BookInfoManager:deleteBookInfo(filepath)
        invalidateForFiles({ filepath })
        return orig_deleteBookInfo(self, filepath)
    end

    local orig_deleteDb = BookInfoManager.deleteDb
    function BookInfoManager:deleteDb()
        clearCaches()
        return orig_deleteDb(self)
    end

    logger.info("pt-perf: folder cover caching enabled")
end

userpatch.registerPatchPluginFunc("coverbrowser", function(plugin)
    patchBookInfoCache(plugin)
    patchFolderCovers(plugin)
end)
