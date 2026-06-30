--[[
bookend-line-font-inherit — add an "Inherit" option to the per-line font picker.

Bookends' line editor offers no way to clear a line's font override: the
picker's "Reset" stores the resolved default-font path into line_font_face,
pinning the line. This patch adds an "Inherit (use default font)" row at the
top of the Fonts section in line-editor pickers; picking it (or Reset) stores
nil — the line editor's "use default" sentinel — while picking any concrete
font pins the line, even when it matches the current default.

The row is injected into the picker's specific-fonts list (not the family
block): page 1 has a fixed 10-row layout that exactly fits the six stock
family rows, so a seventh family entry would overflow into the pagination
bar, while the Fonts section paginates correctly.

Targets:
  - Bookends @ AndyHazz/bookends.koplugin v5.20.0 (or compatible)
    wraps Bookends:showFontPicker (main.lua:2290), which builds its font list
    from FontList.fontinfo and validates entries via Font:getFace;
    line-editor call site bookends_line_editor.lua:698 ("nil = use default"
    contract at line 78).
--]]

local userpatch = require("userpatch")
local Font = require("ui/font")
local FontList = require("fontlist")
local _ = require("gettext")

-- Fake fontinfo key for the injected row. Contains no "/" and no extension,
-- so it can never collide with a real font path.
local INHERIT_SENTINEL = "::bookend-line-font-inherit::"

-- Default font of the picker currently open, so the Font.getFace wrap can
-- render the Inherit row (and the picker title) in the actual default font.
local resolved_default

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

    -- Resolve the sentinel to the default font everywhere, anytime: the
    -- picker validates list entries and renders rows/title through getFace,
    -- including on page rebuilds after the temporary fontinfo entry is gone.
    local orig_getFace = Font.getFace
    Font.getFace = function(self, font, size, ...)
        if font == INHERIT_SENTINEL then
            font = resolved_default or "cfont"
        end
        return orig_getFace(self, font, size, ...)
    end

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

        resolved_default = Utils.resolveFontFace(default_face, nil)

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

        -- The picker builds its font list from FontList.fontinfo once,
        -- synchronously inside the orig call, so the fake entry is removed
        -- right after it returns. The leading space makes the row sort to
        -- the top of the Fonts section.
        FontList.fontinfo[INHERIT_SENTINEL] = {
            { name = " " .. _("Inherit (use default font)") },
        }

        -- Sentinel as the picker's default: "Reset" means inherit instead of
        -- re-pinning the default's file path.
        local ok, err = pcall(orig_showFontPicker, self,
            current_face, wrapped_on_select, INHERIT_SENTINEL, opts)

        FontList.fontinfo[INHERIT_SENTINEL] = nil
        if not ok then error(err) end
    end
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
