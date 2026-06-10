--[[
pt-bookinfo-cache - blob-free metadata queries and an in-memory cache for
Project: Title's BookInfoManager.

PT's single prepared SELECT fetches every bookinfo column, including the
zstd-compressed cover blob (50-200KB per row), even for metadata-only
lookups (get_cover=false). Those lookups are everywhere on the hot path:
MosaicMenuItem:paintTo re-queries on every repaint of every visible book,
and PT's custom sort collates query once per file each time a folder's
item table is generated. SQLite must read the blob's overflow pages off
storage to materialize the row every time.

This patch wraps BookInfoManager:getBookInfo so metadata-only lookups:
  - use a separate prepared statement that excludes the cover columns, so
    the blob is never read from storage;
  - are served from an in-memory cache keyed by filepath, so repaints and
    re-sorts don't touch SQLite at all. Callers get a shallow copy because
    PT mutates the returned tables in place (e.g. ListMenuItem overwrites
    bookinfo.pages).

Books not yet in the DB are never cached, so background extraction results
still show up. The cache is cleared whenever PT mutates book info
(property changes, per-book refresh, cache emptying). Cover lookups
(get_cover=true) and Kobo virtual-library paths pass through untouched.

Targets:
  - coverbrowser @ joshuacant/ProjectTitle 2026.03-v3.7
    (BookInfoManager.getBookInfo/getDocProps/closeDbConnection wrapped;
    column layout discovered via the BOOKINFO_COLS_SET upvalue)
--]]

local userpatch = require("userpatch")
local logger = require("logger")

local function patchBookInfoCache(plugin)
    local BookInfoManager = require("bookinfomanager")
    if BookInfoManager._bookinfo_cache_patched then return end

    -- Discover the column layout from PT itself, and bail out if the
    -- schema assumptions this patch relies on no longer hold.
    local COLS = userpatch.getUpValue(BookInfoManager.getBookInfo, "BOOKINFO_COLS_SET")
    if type(COLS) ~= "table" or COLS[13] ~= "pages" or COLS[20] ~= "description"
            or COLS[#COLS] ~= "cover_bb_data" then
        logger.warn("pt-bookinfo-cache: BookInfoManager internals changed, not patching")
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

    logger.info("pt-bookinfo-cache: blob-free metadata queries and caching enabled")
end

userpatch.registerPatchPluginFunc("coverbrowser", patchBookInfoCache)
