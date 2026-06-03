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

local function patchBookends(plugin)
    if plugin._bookend_unifont_applied then return end
    plugin._bookend_unifont_applied = true
    -- wrapping added in Task 5; menu added in Task 6
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
