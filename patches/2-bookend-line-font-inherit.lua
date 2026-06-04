--[[
bookend-line-font-inherit — make the line editor's font "Reset" truly inherit.

In Bookends' per-line font picker, the "Reset" button (and tapping the list
row matching the default font) calls on_select with the *resolved* default
font path, which the line editor stores into line_font_face. The line then
looks like it follows "Default font" but is permanently pinned to that file:
later default-font changes silently stop applying, and presets carry the
pinned path verbatim. This patch wraps Bookends:showFontPicker so that, for
pickers opened from the line editor, selecting the default font stores nil —
the line editor's documented "use default" sentinel — so the line genuinely
inherits Bookends' Default font setting again.

Pickers opened from anywhere else (e.g. the Default font setting itself,
where saving nil would be wrong) are passed through unchanged.

Targets:
  - Bookends @ AndyHazz/bookends.koplugin v5.14.0 (or compatible)
    wraps Bookends:showFontPicker (main.lua:2188); line-editor call site
    bookends_line_editor.lua:490 ("nil = use default" contract at line 77),
    render-time fallback main.lua:1695.
--]]

local userpatch = require("userpatch")

local function patchBookends(plugin)
    if plugin._bookend_line_font_inherit_applied then return end
    plugin._bookend_line_font_inherit_applied = true

    local orig_showFontPicker = plugin.showFontPicker
    plugin.showFontPicker = function(self, current_face, on_select, default_face, opts)
        -- Only adjust pickers opened by the line editor; identified by the
        -- caller's source file. Other callers (Default font, fallbacks in
        -- other patches) must keep receiving the concrete face.
        local info = debug.getinfo(2, "S")
        local from_line_editor = info and info.source
            and info.source:find("bookends_line_editor", 1, true)
        if not from_line_editor then
            return orig_showFontPicker(self, current_face, on_select, default_face, opts)
        end
        -- Selecting the default font (Reset button, or its list row) means
        -- "follow the Default font setting": store nil instead of pinning
        -- the default's current file path into the line.
        local wrapped_on_select = function(face)
            if face == default_face then
                on_select(nil)
            else
                on_select(face)
            end
        end
        return orig_showFontPicker(self, current_face, wrapped_on_select, default_face, opts)
    end
end

userpatch.registerPatchPluginFunc("bookends", patchBookends)
