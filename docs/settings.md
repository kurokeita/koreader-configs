# Settings presets

`settings/bookends_presets/` holds exported Bookends presets
(schema version 5): complete overlay layouts that can be loaded from
Bookends' preset library. Two are shipped, `manga.lua` and `novel.lua`.

Presets are **not** part of the release bundle; install them manually.

## Applying a preset

1. Copy the preset files into `koreader/settings/bookends_presets/` on the
   device (create the directory if needed). The repo's `settings/` folder
   mirrors the device layout, so you can copy `settings/*` to `koreader/`
   wholesale.
2. Open a book, then
   `Top menu > typeset/document tab (style icon) > Bookends > Preset > Preset library…`
3. Pick `manga` or `novel` and apply it.

Applying a preset replaces the current Bookends position/line configuration
(your other presets stay untouched).

## Shared defaults

Both presets use the same base configuration:

| Key | Value | What it controls |
| --- | --- | --- |
| `font_scale` | 100 | Global font scale (percent) |
| `font_size` | 11 | Default overlay font size |
| `margin_top` / `margin_bottom` | 10 | Vertical distance from screen edges |
| `margin_left` / `margin_right` | 28 | Horizontal distance from screen edges |
| `overlap_gap` | 50 | Gap maintained when lines would overlap |
| `truncation_priority` | center | Which part of a long line is truncated |

All progress-bar slots are present but disabled in both presets.

## manga

Keeps the top edge of the screen completely clean (all three top positions
are disabled), so full-bleed art is never overlaid. The bottom row carries
everything:

| Position | Line | Shows |
| --- | --- | --- |
| Bottom-left | `%batt_icon%batt ⋮ %wifi ⋮ %time_24h ` | Battery, wifi state, 24h clock |
| Bottom-center | `— Page %page_num of %page_count —` | Page counter |
| Bottom-right | `%title \| %chap_title` | Book title and chapter |

**Font caveat:** every bottom line pins its font to the Android path
`/storage/emulated/0/koreader/fonts/Bookerly.ttf`. On non-Android devices
(or without Bookerly installed) edit the preset file and fix or clear the
`line_font_face` entries; an empty entry falls back to the Bookends default
font. Alternatively clear them and enable the
[`2-bookend-unifont.lua`](patches/2-bookend-unifont.md) toggle, which
overrides line fonts with the book's own font at render time anyway.

## novel

Uses the top corners for book context and keeps the bottom row minimal. No
fonts are pinned; lines follow the Bookends default font.

| Position | Line | Shows |
| --- | --- | --- |
| Top-left | `%author - %title` | Author and book title |
| Top-right | `%chap_title` | Current chapter |
| Bottom-left | `%batt_icon%batt ⋮ %wifi` | Battery and wifi state |
| Bottom-center | `— Page %page_num of %page_count —` | Page counter |
| Bottom-right | `%time_24h` | 24h clock |

The top-center position is disabled in both presets (it holds a leftover
clock/date line kept for reference).

## Choosing between them

Use **manga** when the top of the page must stay clean for full-bleed pages
and panel art; use **novel** when you want author/title/chapter context at
a glance while reading prose.
