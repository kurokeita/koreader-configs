--[[
bookend-unifont — render Bookends overlays in the open book's embedded font.

When a zip-based book (EPUB, fb2.zip, htmlz) is opened and the feature is
enabled, this patch extracts the book's main body font and makes the Bookends
plugin draw its overlay text in it. It never changes the document reading font,
the KOReader UI font, or Bookends' stored configuration — the override is
applied only at render time and reverts automatically when disabled or when a
book has no usable embedded font.

Targets:
  - Bookends @ AndyHazz/bookends.koplugin v5.14.0 (or compatible)
    wraps Bookends:resolveLineConfig (main.lua:1006) and
    Bookends:buildBookendsSettingsMenu (menu/main_menu.lua:203)
  - KOReader with ffi/archiver and userpatch.registerPatchPluginFunc

Settings (global, in G_reader_settings):
  - bookend_unifont_enabled  (bool, default false)
  - bookend_unifont_fallback (font face path/sentinel, default nil = none)

Toggle: in the reader, top menu -> Bookends -> Bookends settings
        -> "Use book's embedded font".
--]]

local userpatch   = require("userpatch")
local Archiver    = require("ffi/archiver")
local DataStorage = require("datastorage")
local Font        = require("ui/font")
local FontList    = require("fontlist")
local lfs         = require("libs/libkoreader-lfs")
local util        = require("util")
local logger      = require("logger")
local _           = require("gettext")

logger.info("bookend-unifont: patch file loaded")

local ENABLED_KEY  = "bookend_unifont_enabled"
local FALLBACK_KEY = "bookend_unifont_fallback"
local CACHE_DIR    = DataStorage:getDataDir() .. "/cache/bookend-unifont/"

-- Font file extensions we will consider extracting from a book archive.
local FONT_EXTS = { ttf = true, otf = true, ttc = true, otc = true }
-- Filename suffixes that identify a zip-based book we can mine for fonts.
local ZIP_SUFFIXES = { ".epub", ".fb2.zip", ".htmlz" }

-- Module-local "active" font: an absolute path or a face sentinel when set,
-- nil when the patch should not override Bookends' own font. Shared across the
-- single live reader instance; recomputed on each book open and on toggle.
local active_font_path = nil

-- True for book files we can open as an archive and mine for fonts.
local function isZipBased(file)
    local lower = file:lower()
    for _, suffix in ipairs(ZIP_SUFFIXES) do
        if lower:sub(-#suffix) == suffix then return true end
    end
    return false
end

-- Bump when the font-selection logic changes so stale cached picks are
-- re-extracted instead of reused (pruneCache then removes the old files).
local CACHE_VERSION = "v3"

-- Stable per-book cache filename (independent of which font we pick), so a
-- second open of the same book reuses the extracted file without reopening the
-- archive. Includes file size to disambiguate same-named books, and a version
-- token so picker changes invalidate old extractions.
local function cacheKey(file)
    local attr = lfs.attributes(file)
    local size = attr and attr.size or 0
    local flat = file:gsub("[^%w]", "_")
    return CACHE_VERSION .. "_" .. flat:sub(-60) .. "_" .. tostring(size) .. ".font"
end

local function ensureCacheDir()
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then
        util.makePath(CACHE_DIR)
    end
end

-- Remove every cached font except the one we just used, bounding disk usage.
local function pruneCache(keep_path)
    local keep_name = keep_path and keep_path:match("([^/]+)$")
    local ok, iter, dir_obj = pcall(lfs.dir, CACHE_DIR)
    if not ok then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." and entry ~= keep_name then
            os.remove(CACHE_DIR .. entry)
        end
    end
end

-- Tokens that mark a non-regular weight/style. If a font filename contains any
-- of these, it is not our preferred body face.
local NON_REGULAR = {
    "bold", "italic", "oblique", "black", "light", "thin",
    "semibold", "demibold", "medium", "condensed", "heavy",
    "extrabold", "extralight",
}

-- Tokens stripped when comparing a filename family to a used-font display name.
local STRIP_TOKENS = {
    "regular", "book", "roman",
    "bold", "italic", "oblique", "black", "light", "thin",
    "semibold", "demibold", "medium", "condensed", "heavy",
    "extrabold", "extralight",
}

local function normalizeFamily(s)
    s = tostring(s):lower():gsub("%.%w+$", "")
    for _, token in ipairs(STRIP_TOKENS) do
        s = s:gsub(token, "")
    end
    return (s:gsub("[^%a]", ""))
end

local function isRegularFontName(base)
    for _, token in ipairs(NON_REGULAR) do
        if base:find(token, 1, true) then return false end
    end
    return true
end

-- Tokens that mark a display/title/heading face rather than body text.
local DISPLAY_TOKENS = {
    "display", "title", "heading", "headline", "head", "caption",
    "smallcap", "script", "swash", "deco", "ornament", "initial",
    "dropcap", "hand",
}

local function isDisplayName(base)
    for _, token in ipairs(DISPLAY_TOKENS) do
        if base:find(token, 1, true) then return true end
    end
    return false
end

-- Choose the book's main body face from collected font entries.
-- entries: array of { path, base = <lowercased basename>, size = <bytes> }
-- used:    set keyed by normalizeFamily(name) for fonts the book actually uses.
-- Score favors a regular-weight, non-display, used face; ties broken by the
-- largest file, since body fonts carry the full character set while title and
-- display fonts are usually subset down to a few glyphs.
local function pickBodyFont(entries, used)
    local best, best_score
    for _, e in ipairs(entries) do
        local score = 0
        if isRegularFontName(e.base) then score = score + 100 end
        if not isDisplayName(e.base) then score = score + 50 end
        if used[normalizeFamily(e.base)] == true then score = score + 10 end
        if not best or score > best_score
                or (score == best_score and (e.size or 0) > (best.size or 0)) then
            best, best_score = e, score
        end
    end
    return best or entries[1]
end

-- Strip CSS comments so they can't hide declarations.
local function stripCssComments(css)
    return (css:gsub("/%*.-%*/", " "))
end

-- Ordered list of font families declared for body text, or nil if no body rule.
local function bodyFamilyList(css)
    for sel, block in css:gmatch("([^{}]+)(%b{})") do
        local s = sel:lower()
        if s:find("%f[%a]body%f[%A]") and not s:find("@") then
            local decl = block:match("font%-family%s*:%s*([^;}]+)")
            if decl then
                local list = {}
                for fam in decl:gmatch("[^,]+") do
                    fam = fam:gsub("[\"']", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if fam ~= "" then list[#list + 1] = fam end
                end
                if #list > 0 then return list end
            end
        end
    end
    return nil
end

-- Map of normalizeFamily(name) -> src url for normal-weight @font-face rules.
local function fontFaceSources(css)
    local map = {}
    for sel, block in css:gmatch("([^{}]+)(%b{})") do
        if sel:lower():find("@font%-face") then
            local fam = block:match("font%-family%s*:%s*([^;}]+)")
            local url = block:match("url%(%s*['\"]?([^'\")]+)")
            if fam and url then
                local style  = (block:match("font%-style%s*:%s*([^;}]+)")  or "normal"):lower()
                local weight = (block:match("font%-weight%s*:%s*([^;}]+)") or "normal"):lower()
                local norm = normalizeFamily(fam)
                local is_normal = not style:find("italic") and not style:find("oblique")
                    and not weight:find("bold") and not weight:find("[5-9]00")
                if norm ~= "" and (is_normal or map[norm] == nil) then
                    map[norm] = url
                end
            end
        end
    end
    return map
end

-- Use the book's CSS to find the embedded *body* font file.
-- Returns: an entry (embedded body font found),
--          false (a body font is declared but not embedded -> use fallback),
--          nil   (inconclusive: no body rule -> caller may use the heuristic).
local function resolveBodyFontEntry(css, entries)
    local fams = bodyFamilyList(css)
    if not fams then return nil end
    local sources = fontFaceSources(css)
    for _, fam in ipairs(fams) do
        local url = sources[normalizeFamily(fam)]
        if url then
            local base = url:lower():match("([^/\\]+)$")
            for _, e in ipairs(entries) do
                if e.base == base then return e end
            end
        end
    end
    return false
end

-- Make an extracted font loadable by Font:getFace. Font:getFace can only
-- resolve a face whose path is present in FontList's (session-memoized) list,
-- so we ensure that list is built and then append our path. FreeType loads the
-- file by content, so its extension and location are irrelevant.
local function registerFontPath(path)
    FontList:getFontList() -- ensure the base list is built before we append
    for _, p in ipairs(FontList.fontlist) do
        if p == path then return end
    end
    table.insert(FontList.fontlist, path)
end

-- Extract the book's body font to the cache and return its absolute path, or
-- nil if the book is not zip-based / has no usable font / extraction fails.
local function tryExtractBookFont(doc)
    local file = doc.file
    if not file or not isZipBased(file) then return nil end

    local cache_path = CACHE_DIR .. cacheKey(file)
    if lfs.attributes(cache_path, "mode") == "file" then
        registerFontPath(cache_path)
        if Font:getFace(cache_path, 20) then
            pruneCache(cache_path)
            return cache_path
        end
    end

    local arc = Archiver.Reader:new()
    if not arc:open(file) then return nil end

    local entries, css_paths = {}, {}
    for entry in arc:iterate() do
        if entry.mode == "file" then
            local ext = entry.path:lower():match("%.([%w]+)$")
            if ext and FONT_EXTS[ext] then
                entries[#entries + 1] = {
                    path = entry.path,
                    base = entry.path:lower():match("([^/]+)$"),
                    size = entry.size or 0,
                }
            elseif ext == "css" then
                css_paths[#css_paths + 1] = entry.path
            end
        end
    end

    if #entries == 0 then
        arc:close()
        return nil
    end

    -- Prefer the embedded *body* font as declared in the book's CSS, so we
    -- don't grab a heading/title-only embedded font when the body text uses a
    -- non-embedded system font.
    local chosen
    local css = ""
    for _, p in ipairs(css_paths) do
        local ok, data = pcall(function() return arc:extractToMemory(p) end)
        if ok and data then css = css .. "\n" .. data end
    end
    if css ~= "" then
        local r = resolveBodyFontEntry(stripCssComments(css), entries)
        if r == false then
            arc:close()
            logger.info("bookend-unifont: body font not embedded; using fallback")
            return nil
        end
        chosen = r or nil
    end

    if not chosen then
        local used = {}
        local list = doc.getEmbeddedFontList and doc:getEmbeddedFontList()
        if list then
            for name in pairs(list) do
                used[normalizeFamily(name)] = true
            end
        end
        chosen = pickBodyFont(entries, used)
    end

    ensureCacheDir()
    local ok = arc:extractToPath(chosen.path, cache_path)
    arc:close()
    if not ok then
        logger.info("bookend-unifont: extractToPath failed for", chosen.path)
        return nil
    end

    registerFontPath(cache_path)
    if not Font:getFace(cache_path, 20) then
        logger.info("bookend-unifont: Font:getFace rejected", cache_path)
        os.remove(cache_path)
        return nil
    end
    pruneCache(cache_path)
    return cache_path
end

-- Recompute active_font_path from settings + current document, and repaint
-- Bookends if it changed. Safe to call repeatedly.
local function computeActiveFont(plugin)
    local new_path = nil
    if G_reader_settings:isTrue(ENABLED_KEY) and plugin.ui and plugin.ui.document then
        local ok, result = pcall(tryExtractBookFont, plugin.ui.document)
        if ok and result then
            new_path = result
        else
            if not ok then
                logger.warn("bookend-unifont: extraction error:", result)
            end
            new_path = G_reader_settings:readSetting(FALLBACK_KEY) -- may be nil
        end
    end
    logger.info("bookend-unifont: enabled=", G_reader_settings:isTrue(ENABLED_KEY),
        "active=", tostring(new_path))
    if new_path ~= active_font_path then
        active_font_path = new_path
        if plugin.markDirty then plugin:markDirty() end
    end
end

-- Human-readable label for a stored fallback face value (path or @family:).
local function faceLabel(face)
    if not face then return _("None") end
    local fam = tostring(face):match("^@family:(.+)$")
    if fam then return fam end
    local base = tostring(face):match("([^/]+)$") or tostring(face)
    return (base:gsub("%.%w+$", ""))
end

local function buildUnifontItems(plugin)
    return {
        {
            text = _("Use book's embedded font"),
            help_text = _("Render Bookends overlays in the font embedded in the current book (EPUB and other zip-based formats). Falls back to the chosen fallback font, or Bookends' own font, when the book has no embedded font."),
            checked_func = function()
                return G_reader_settings:isTrue(ENABLED_KEY)
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse(ENABLED_KEY)
                computeActiveFont(plugin)
            end,
        },
        {
            text_func = function()
                return _("Fallback font") .. " (" ..
                    faceLabel(G_reader_settings:readSetting(FALLBACK_KEY)) .. ")"
            end,
            enabled_func = function()
                return G_reader_settings:isTrue(ENABLED_KEY)
            end,
            sub_item_table_func = function()
                return {
                    {
                        text = _("None (use Bookends' own font)"),
                        checked_func = function()
                            return G_reader_settings:readSetting(FALLBACK_KEY) == nil
                        end,
                        callback = function()
                            G_reader_settings:delSetting(FALLBACK_KEY)
                            computeActiveFont(plugin)
                        end,
                    },
                    {
                        text_func = function()
                            return _("Choose fallback font…") .. " (" ..
                                faceLabel(G_reader_settings:readSetting(FALLBACK_KEY)) .. ")"
                        end,
                        callback = function()
                            plugin:showFontPicker(
                                G_reader_settings:readSetting(FALLBACK_KEY),
                                function(face)
                                    G_reader_settings:saveSetting(FALLBACK_KEY, face)
                                    computeActiveFont(plugin)
                                end,
                                Font.fontmap["ffont"])
                        end,
                    },
                }
            end,
        },
    }
end

-- patchBookends receives the Bookends *class* (userpatch fires after the
-- instance is built and passes the plugin module). We therefore wrap class
-- methods, and compute the active font against the live instance (`self`)
-- lazily from within resolveLineConfig — the class has no document.
local function patchBookends(plugin)
    if plugin._bookend_unifont_applied then return end
    plugin._bookend_unifont_applied = true
    logger.info("bookend-unifont: applied to Bookends class")

    -- Render-time substitution: when an active font is set, swap it in as the
    -- face name and delegate to the original. resolveLineConfig itself resolves
    -- @family: sentinels and variant lookups, so both an absolute path and a
    -- face sentinel (from the fallback picker) work unchanged. Never writes
    -- Bookends' stored settings.
    local orig_resolveLineConfig = plugin.resolveLineConfig
    plugin.resolveLineConfig = function(self, face_name, font_size, style)
        -- Compute once per opened document, against the live instance.
        local doc_file = self.ui and self.ui.document and self.ui.document.file or false
        if self._unifont_doc_file ~= doc_file then
            self._unifont_doc_file = doc_file
            computeActiveFont(self)
        end
        if active_font_path then
            return orig_resolveLineConfig(self, active_font_path, font_size, style)
        end
        return orig_resolveLineConfig(self, face_name, font_size, style)
    end

    -- Append our settings into Bookends' own settings submenu.
    local orig_buildBookendsSettingsMenu = plugin.buildBookendsSettingsMenu
    plugin.buildBookendsSettingsMenu = function(self)
        local items = orig_buildBookendsSettingsMenu(self)
        for _, item in ipairs(buildUnifontItems(self)) do
            items[#items + 1] = item
        end
        return items
    end
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
