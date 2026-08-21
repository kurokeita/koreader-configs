# 2-bookend-line-font-inherit.lua

Adds an "Inherit (use default font)" row to the font picker in Bookends'
per-line editor. Stock Bookends gives no way to clear a line's font override:
its "Reset" button stores the resolved default-font path into the line, which
pins the line to that file even after the default font changes. With this
patch, picking the Inherit row (or pressing Reset) stores the "use default"
sentinel instead, so the line follows the Bookends default font from then on.
Picking any concrete font still pins the line, even when it matches the
current default.

The Inherit row appears at the top of the Fonts section of the picker, and
both the row and the picker title render in the actual current default font.
Pickers opened from anywhere other than the line editor (for example the
Default font setting itself) are left untouched.

## Target

- **Patches:** bookends plugin
- **Written against:** Bookends v5.20.0 (wraps `Bookends:showFontPicker`,
  call site in `bookends_line_editor.lua`) / KOReader 2026.07.1
- **Requires:** Bookends plugin installed

## Settings

No settings of its own. The patch only changes the behavior of an existing
dialog: with a book open,
`Top menu > typeset/document tab (style icon) > Bookends > (edit a position) > (line) > Font`.

- "Inherit (use default font)" row: stores no override, the line follows the
  Bookends default font.
- "Reset": now also means inherit, instead of pinning the default font's file
  path.

Nothing is persisted by the patch itself; line font choices live in Bookends'
own configuration.

## Disable

Remove or rename `koreader/patches/2-bookend-line-font-inherit.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.
Lines already set to inherit keep working; stock Bookends treats a missing
line font as "use default" natively.

## Interactions

`2-bookend-unifont.lua`: while its "Use book's embedded font" toggle is
enabled, the book's font replaces the face for every overlay line at render
time, so per-line font choices, including Inherit, have no visible effect
until that toggle is turned off. The two patches do not conflict; Inherit
simply becomes relevant again as soon as unifont is disabled or has no font
to apply.
