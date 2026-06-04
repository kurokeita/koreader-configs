--[[
bookend-line-font-inherit — add an "Inherit" option to the per-line font picker.

Bookends' line editor offers no way to clear a line's font override: the
picker's "Reset" stores the resolved default-font path into line_font_face,
pinning the line. This patch adds an "Inherit (use default font)" row at the
top of line-editor pickers; picking it (or Reset) stores nil — the line
editor's "use default" sentinel — while picking any concrete font pins the
line, even when it matches the current default. The "UI font" family row is
hidden in these pickers to keep page 1 within its fixed 10-row layout; the
UI font stays pickable from the Fonts list.

Targets:
  - Bookends @ AndyHazz/bookends.koplugin v5.14.0 (or compatible)
    wraps Bookends:showFontPicker (main.lua:2188); injects the row via
    bookends_utils' family-row tables; line-editor call site
    bookends_line_editor.lua:490 ("nil = use default" contract at line 77).
--]]

local userpatch = require("userpatch")
local _ = require("gettext")

-- "@family:" namespace so the picker's family-row machinery (page-1
-- placement, checkmark, title) applies unchanged.
local INHERIT_KEY = "bookend_line_inherit"
local INHERIT_SENTINEL = "@family:" .. INHERIT_KEY

-- Whether the line currently inherits, read off the on_select closure's
-- line_face upvalue (nil = inheriting). Returns nil if the closure shape
-- changed, degrading to no preselection.
local function lineInherits(on_select)
    if not (debug and debug.getupvalue) then return nil end
    local i = 1
    while true do
        local name, value = debug.getupvalue(on_select, i)
        if not name then return nil end
        if name == "line_face" then return value == nil end
        i = i + 1
    end
end

local function patchBookends(plugin)
    if plugin._bookend_line_font_inherit_applied then return end
    plugin._bookend_line_font_inherit_applied = true

    local orig_showFontPicker = plugin.showFontPicker
    plugin.showFontPicker = function(self, current_face, on_select, default_face, opts)
        -- Only adjust pickers opened by the line editor; other callers
        -- (e.g. the Default font setting) must keep receiving concrete faces.
        local info = debug.getinfo(2, "S")
        local from_line_editor = info and info.source
            and info.source:find("bookends_line_editor", 1, true)
        local Utils = package.loaded["bookends_utils"]
        if not from_line_editor or not Utils then
            return orig_showFontPicker(self, current_face, on_select, default_face, opts)
        end

        local function wrapped_on_select(face)
            if face == INHERIT_SENTINEL then
                on_select(nil)
            else
                on_select(face)
            end
        end

        if lineInherits(on_select) then
            current_face = INHERIT_SENTINEL
        end

        -- The picker builds its row list synchronously inside the orig call,
        -- so the Utils mutations below are reverted right after it returns.
        local orig_label_fn = Utils.getFontFamilyLabel
        Utils.getFontFamilyLabel = function(face)
            if face == INHERIT_SENTINEL then
                return {
                    label = _("Inherit (use default font)"),
                    is_family = true,
                    is_mapped = true,
                    resolved = Utils.resolveFontFace(default_face, nil),
                }
            end
            if face == "@family:ui" then return nil end -- skip row, see header
            return orig_label_fn(face)
        end
        table.insert(Utils.FONT_FAMILY_ORDER, 1, INHERIT_KEY)
        Utils.FONT_FAMILIES[INHERIT_KEY] = _("Inherit")

        -- Sentinel as the picker's default: "Reset" means inherit instead of
        -- re-pinning the default's file path.
        local ok, err = pcall(orig_showFontPicker, self,
            current_face, wrapped_on_select, INHERIT_SENTINEL, opts)

        table.remove(Utils.FONT_FAMILY_ORDER, 1)
        Utils.FONT_FAMILIES[INHERIT_KEY] = nil
        Utils.getFontFamilyLabel = orig_label_fn
        if not ok then error(err) end
    end
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
