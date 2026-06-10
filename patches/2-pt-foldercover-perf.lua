--[[
pt-foldercover-perf - cache Project: Title's auto-generated folder covers.

PT rebuilds every folder tile from scratch on every page draw: a directory
scan looking for a cover file, one or two throwaway SQLite connections
running `ORDER BY RANDOM()` queries (a full scan-and-sort of every cached
book under the folder), and up to four cover blobs zstd-decompressed and
rescaled. Nothing is cacheable upstream because RANDOM() returns different
rows each call, which also makes the thumbnails visibly reshuffle.

This patch replaces the folder-cover helpers in ptutil with versions that:
  - query deterministically (`ORDER BY directory, filename LIMIT 8`), which
    rides the dir_filename index instead of sorting the whole subtree, and
    stops the per-page reshuffling;
  - reuse BookInfoManager's shared DB connection instead of opening a fresh
    one per query (upstream also leaks a connection when the folder no
    longer exists);
  - cache the chosen cover paths per folder and the scaled thumbnail
    blitbuffers per book+size, so repeat page draws skip the queries and
    the decompress+rescale entirely;
  - cache cover-file probe results and image dimensions, so folder tiles
    with a cover.jpg stop re-scanning the directory and decoding the image
    twice per draw.

Invalidation is scoped: when PT extracts or refreshes books, only the
affected files' thumbnails and their ancestor folders' cached cover picks
are dropped; everything else stays warm (emptying the whole cache database
still clears everything). Evicted thumbnails are reclaimed by GC (never
freed explicitly, as live widgets may still reference them).

Targets:
  - coverbrowser @ joshuacant/ProjectTitle 2026.03-v3.7
    (ptutil.query_cover_paths, ptutil.build_cover_images,
    ptutil.getSubfolderCoverImages, ptutil.getFolderCover;
    BookInfoManager cache-mutating methods are wrapped for invalidation)
--]]

local userpatch = require("userpatch")
local logger = require("logger")

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
            logger.warn("pt-foldercover-perf: ptutil." .. fn .. " not found, not patching")
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
            logger.info("pt-foldercover-perf: invalidated", dropped,
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
            logger.info("pt-foldercover-perf: folder cover failed to render:", folder_image_file)
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

    logger.info("pt-foldercover-perf: folder cover caching enabled")
end

userpatch.registerPatchPluginFunc("coverbrowser", patchFolderCovers)
