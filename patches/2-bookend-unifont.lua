--[[
bookend-unifont — render Bookends overlays in the open book's embedded font.

When a zip-based book (EPUB, fb2.zip, htmlz) is opened and the feature is
enabled, this patch extracts the book's main body font and makes the Bookends
plugin draw its overlay text in it. It never changes the document reading font,
the KOReader UI font, or Bookends' stored configuration — the override is
applied only at render time and reverts automatically when disabled or when a
book has no usable embedded font.

Targets:
  - Bookends @ AndyHazz/bookends.koplugin v5.20.0 (or compatible)
    wraps Bookends:resolveLineConfig (main.lua:1016) and
    Bookends:buildBookendsSettingsMenu (menu/main_menu.lua:209)
  - KOReader 2026.07.1 (safe_version 202607010000), with ffi/archiver and
    userpatch.registerPatchPluginFunc

Settings (global, in G_reader_settings):
  - bookend_unifont_enabled  (bool, default false)

Toggle: in the reader, top menu -> Bookends -> Bookends settings
        -> "Use book's embedded font" (inserted above the stock
        "Default font" entry, which is disabled while the toggle is on).
        When the book has no usable embedded font, the overlay falls
        back to the book's KOReader reading font.
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

local ENABLED_KEY = "bookend_unifont_enabled"
local CACHE_DIR   = DataStorage:getDataDir() .. "/cache/bookend-unifont/"

-- Font file extensions we will consider extracting from a book archive.
local FONT_EXTS = { ttf = true, otf = true, ttc = true, otc = true }
-- Filename suffixes that identify a zip-based book we can mine for fonts.
local ZIP_SUFFIXES = { ".epub", ".fb2.zip", ".htmlz" }

-- Module-local "active" font: an absolute path or a face sentinel when set,
-- nil when the patch should not override Bookends' own font. Shared across the
-- single live reader instance; recomputed on each book open and on toggle.
local active_font_path = nil
-- Path we last appended to FontList.fontlist, so we can remove it again and
-- avoid accumulating stale entries that point at pruned cache files.
local injected_font_path = nil

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
local CACHE_VERSION = "v6"

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

-- Weight/style tokens dropped when comparing family names. Matched as whole
-- tokens (see normalizeFamily), never as substrings.
local STRIP_TOKENS = {
    "regular", "book", "roman",
    "bold", "italic", "oblique", "black", "light", "thin",
    "semibold", "demibold", "medium", "condensed", "heavy",
    "extrabold", "extralight",
}
local STRIP_SET = {}
for _, token in ipairs(STRIP_TOKENS) do STRIP_SET[token] = true end

-- Reduce a font family or filename to a comparable key: drop the extension,
-- split into alphabetic tokens, discard weight/style words, and join the rest.
-- Whole-token matching avoids mangling names like "Bookerly" (which merely
-- contains the substring "book").
local function normalizeFamily(s)
    s = tostring(s):lower():gsub("%.%w+$", "")
    local kept = {}
    for token in s:gmatch("%a+") do
        if not STRIP_SET[token] then kept[#kept + 1] = token end
    end
    return table.concat(kept)
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

-- Families from the *last* rule matching `selector` that declares a
-- font-family, preserving declaration order (the first family is preferred).
-- nil if no such rule. CSS cascades last-wins at equal specificity, so a later
-- rule overrides an earlier one (e.g. a reset stylesheet's
-- `body { font-family: serif }` before the main `body { font-family: "X" }`).
-- Note: CSS is concatenated in archive iteration order, which only approximates
-- true stylesheet/spine cascade order.
local function familyListFor(css, selector)
    local result
    for sel, block in css:gmatch("([^{}]+)(%b{})") do
        -- The real selector is the text after the last ';': @charset/@namespace
        -- are ;-terminated and bleed into the next rule's captured selector, so
        -- stripping them keeps the @-guard from skipping a following body rule.
        local s = sel:gsub(".*;", ""):lower()
        if s:find("%f[%a]" .. selector .. "%f[%A]") and not s:find("@") then
            local decl = block:match("font%-family%s*:%s*([^;}]+)")
            if decl then
                local list = {}
                for fam in decl:gmatch("[^,]+") do
                    fam = fam:gsub("[\"']", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if fam ~= "" then list[#list + 1] = fam end
                end
                if #list > 0 then result = list end
            end
        end
    end
    return result
end

-- The book's prose font families. `body` sets the document's default reading
-- font, so prefer it; fall back to `p` then `html` only when a higher-priority
-- selector declares no font-family. A bare/contextual `p` rule is often a
-- special style (e.g. centered title paragraphs in `div.jacket p`), so it must
-- not outrank `body`. Returns nil when none declare a font-family.
local function bodyFamilyList(css)
    return familyListFor(css, "body")
        or familyListFor(css, "p")
        or familyListFor(css, "html")
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
--          false (a body font is declared but not embedded -> reading font),
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

-- Families used for drop caps / decorative initials. These must never be used
-- for the overlay, even if the size heuristic would otherwise rank them high.
-- Detected via :first-letter, a `drop`/`dropcap`/`initial` selector, or a
-- floated rule that also sets a font-family (the classic drop-cap pattern).
local function dropCapFamilies(css)
    local set = {}
    for sel, block in css:gmatch("([^{}]+)(%b{})") do
        local s = sel:gsub(".*;", ""):lower()
        if not s:find("@") then
            local fam = block:match("font%-family%s*:%s*([^;}]+)")
            if fam then
                local is_dropcap = s:find("first%-letter")
                    or s:find("%f[%a]drop%f[%A]")
                    or s:find("dropcap")
                    or s:find("initial")
                    or block:find("float%s*:")
                if is_dropcap then
                    local first = fam:gsub(",.*$", ""):gsub("[\"']", "")
                        :gsub("^%s+", ""):gsub("%s+$", "")
                    if first ~= "" then set[normalizeFamily(first)] = true end
                end
            end
        end
    end
    return set
end

-- Set of font-file basenames (lowercased) that back a drop-cap family, so they
-- can be filtered out of the candidate list.
local function excludedBases(css, entries)
    local fams = dropCapFamilies(css)
    if not next(fams) then return {} end
    local sources = fontFaceSources(css)
    local bases = {}
    for fam in pairs(fams) do
        local url = sources[fam]
        if url then bases[url:lower():match("([^/\\]+)$")] = true end
    end
    return bases
end

-- Remove the previously injected entry from FontList so the list (and the font
-- pickers it feeds) does not accumulate stale paths to pruned cache files.
local function clearInjectedFont()
    if not injected_font_path then return end
    for i = #FontList.fontlist, 1, -1 do
        if FontList.fontlist[i] == injected_font_path then
            table.remove(FontList.fontlist, i)
        end
    end
    injected_font_path = nil
end

-- Append a path to FontList so Font:getFace can resolve it (Font:getFace only
-- finds faces whose path is in FontList's session-memoized list). FreeType
-- loads by content, so extension/location are irrelevant. No removal tracking:
-- safe for real system fonts that are already (or should stay) in the list.
local function ensureInFontList(path)
    FontList:getFontList() -- ensure the base list is built before we append
    for _, p in ipairs(FontList.fontlist) do
        if p == path then return end
    end
    table.insert(FontList.fontlist, path)
end

-- Register an *extracted* (temporary, per-book cache) font: like
-- ensureInFontList, but tracks the path so the previous one is removed when a
-- new book is opened, keeping stale cache paths out of the font pickers.
local function registerFontPath(path)
    if injected_font_path ~= path then clearInjectedFont() end
    injected_font_path = path
    ensureInFontList(path)
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
    local stripped = stripCssComments(css)

    -- Drop-cap / decorative-initial fonts must never be used; drop them from
    -- the candidate list before both CSS resolution and the heuristic.
    local excl = excludedBases(stripped, entries)
    local cand = {}
    for _, e in ipairs(entries) do
        if not excl[e.base] then cand[#cand + 1] = e end
    end
    if #cand == 0 then cand = entries end

    if css ~= "" then
        local r = resolveBodyFontEntry(stripped, cand)
        if r == false then
            arc:close()
            clearInjectedFont()
            pruneCache(nil)
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
        chosen = pickBodyFont(cand, used)
    end

    ensureCacheDir()
    local ok = arc:extractToPath(chosen.path, cache_path)
    arc:close()
    if not ok then return nil end

    registerFontPath(cache_path)
    if not Font:getFace(cache_path, 20) then
        os.remove(cache_path)
        return nil
    end
    pruneCache(cache_path)
    return cache_path
end

-- The font KOReader uses to render this book (its reading font), resolved to a
-- file path Bookends can load. Used as the fallback when the book has no usable
-- embedded body font, so the overlay mirrors the book's text rather than
-- Bookends' own font.
local cre_engine -- delayed init
local function readingFontPath(plugin)
    local doc = plugin.ui and plugin.ui.document
    if not doc or not doc.getFontFace then return nil end
    local ok, face = pcall(function() return doc:getFontFace() end)
    if not ok or not face or face == "" then
        face = (plugin.ui.font and plugin.ui.font.font_face)
            or G_reader_settings:readSetting("cre_font")
    end
    if not face or face == "" then return nil end
    if not cre_engine then
        local ok2, eng = pcall(function()
            return require("document/credocument"):engineInit()
        end)
        if not ok2 then return nil end
        cre_engine = eng
    end
    local fn = cre_engine.getFontFaceFilenameAndFaceIndex(face)
        or cre_engine.getFontFaceFilenameAndFaceIndex(face, nil, true)
    if not fn then return nil end
    ensureInFontList(fn)
    if Font:getFace(fn, 20) then return fn end
    return nil
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
            clearInjectedFont() -- drop any stale extracted-font injection
            -- No embedded body font: mirror the book's KOReader reading font.
            new_path = readingFontPath(plugin)
        end
    else
        clearInjectedFont()
    end
    if new_path ~= active_font_path then
        active_font_path = new_path
        if plugin.markDirty then plugin:markDirty() end
    end
end

local function buildUnifontToggle(plugin)
    return {
        text = _("Use book's embedded font"),
        help_text = _("Render Bookends overlays in the font embedded in the current book (EPUB and other zip-based formats). When the book has no embedded font, falls back to the book's KOReader reading font."),
        checked_func = function()
            return G_reader_settings:isTrue(ENABLED_KEY)
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse(ENABLED_KEY)
            computeActiveFont(plugin)
        end,
    }
end

-- patchBookends receives the Bookends *class* (userpatch fires after the
-- instance is built and passes the plugin module). We therefore wrap class
-- methods; the active font is computed against the live instance (`self`) when
-- the document becomes ready, the class itself has no document.
local function patchBookends(plugin)
    if plugin._bookend_unifont_applied then return end
    plugin._bookend_unifont_applied = true

    -- Render-time substitution: when an active font is set, swap it in as the
    -- face name (an absolute file path, which resolveLineConfig loads directly)
    -- and delegate to the original. Never writes Bookends' stored settings. The
    -- lazy compute is a fallback for the case where onReaderReady did not run
    -- (e.g. font extracted on first paint).
    local orig_resolveLineConfig = plugin.resolveLineConfig
    plugin.resolveLineConfig = function(self, face_name, font_size, style)
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

    -- Compute the active font when the document is ready, keeping the archive
    -- IO off the paint path.
    local orig_onReaderReady = plugin.onReaderReady
    plugin.onReaderReady = function(self, doc_settings)
        if orig_onReaderReady then orig_onReaderReady(self, doc_settings) end
        self._unifont_doc_file = self.ui and self.ui.document and self.ui.document.file or false
        computeActiveFont(self)
    end

    -- Insert our toggle just above Bookends' "Default font" entry and disable
    -- that entry while the toggle is on (the embedded/reading font overrides
    -- it at render time, so editing it would have no visible effect).
    local orig_buildBookendsSettingsMenu = plugin.buildBookendsSettingsMenu
    plugin.buildBookendsSettingsMenu = function(self)
        local items = orig_buildBookendsSettingsMenu(self)
        local toggle = buildUnifontToggle(self)
        local prefix = _("Default font")
        for i, item in ipairs(items) do
            local text = item.text_func and item.text_func() or item.text
            if text and text:sub(1, #prefix) == prefix then
                item.enabled_func = function()
                    return not G_reader_settings:isTrue(ENABLED_KEY)
                end
                table.insert(items, i, toggle)
                return items
            end
        end
        -- "Default font" entry not found (menu layout changed): append instead.
        items[#items + 1] = toggle
        return items
    end
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
