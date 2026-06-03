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
local lfs         = require("libs/libkoreader-lfs")
local util        = require("util")
local logger      = require("logger")
local _           = require("gettext")

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

-- Stable per-book cache filename (independent of which font we pick), so a
-- second open of the same book reuses the extracted file without reopening the
-- archive. Includes file size to disambiguate same-named books.
local function cacheKey(file)
    local attr = lfs.attributes(file)
    local size = attr and attr.size or 0
    local flat = file:gsub("[^%w]", "_")
    return flat:sub(-60) .. "_" .. tostring(size) .. ".font"
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

-- Choose the book's main body face from collected font entries.
-- entries: array of { path = <path in archive>, base = <lowercased basename> }
-- used:    set keyed by normalizeFamily(name) for fonts the book actually uses.
-- Preference: regular-weight AND used > regular-weight > used > first entry.
local function pickBodyFont(entries, used)
    local first_regular, first_used
    for _, e in ipairs(entries) do
        local is_regular = isRegularFontName(e.base)
        local in_used = used[normalizeFamily(e.base)] == true
        if is_regular and in_used then
            return e
        end
        if is_regular and not first_regular then first_regular = e end
        if in_used and not first_used then first_used = e end
    end
    return first_regular or first_used or entries[1]
end

local function patchBookends(plugin)
    if plugin._bookend_unifont_applied then return end
    plugin._bookend_unifont_applied = true
    -- wrapping added in Task 5; menu added in Task 6
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
