# Settings presets

`settings/bookends_presets/` holds exported Bookends presets
(schema version 5): complete overlay layouts that can be loaded from
Bookends' preset library. Two are shipped, `manga.lua` and `novel.lua`.

Since v0.4.0 the release bundle ships them in its `settings/` folder.

## Applying a preset

1. Copy the preset files into `koreader/settings/bookends_presets/` on the
   device (create the directory if needed). The bundle's and the repo's
   `settings/` folders mirror the device layout, so you can copy
   `settings/*` to `koreader/` wholesale.
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
| `margin_top` | 10 | Distance from the top screen edge |
| `margin_bottom` | 5 | Distance from the bottom screen edge |
| `margin_left` / `margin_right` | 28 | Horizontal distance from screen edges |
| `overlap_gap` | 50 | Gap maintained when lines would overlap |
| `truncation_priority` | center | Which part of a long line is truncated |

All progress-bar slots are present but disabled in both presets, no line
pins a font face (lines follow the Bookends default font, or the book's own
font with [`2-bookend-unifont.lua`](patches/2-bookend-unifont.md) enabled).

## manga

Keeps the top edge of the screen completely clean (all three top positions
are disabled), so full-bleed art is never overlaid. The bottom row carries
everything:

| Position | Line | Shows |
| --- | --- | --- |
| Bottom-left | `%batt_icon%batt \| %wifi \| %time_24h` | Battery, wifi state, 24h clock |
| Bottom-center | `— Page %page_num of %page_count —` | Page counter |
| Bottom-right | `%title \| %chap_title` | Book title and chapter |

## novel

Uses the top corners for book context and adds session stats at the bottom.

| Position | Line | Shows |
| --- | --- | --- |
| Top-left | `%author - %title` | Author and book title |
| Top-right | `%chap_title` | Current chapter |
| Bottom-left | `%batt_icon%batt \| %wifi \| %time_24h` | Battery, wifi state, 24h clock |
| Bottom-center | `— Page %page_num of %page_count —` | Page counter |
| Bottom-right | `⌛ %session_time » %session_pages page session` | Reading-session duration and pages |

The top-center position is disabled in both presets (it holds a leftover
clock/date line kept for reference).

## Choosing between them

Use **manga** when the top of the page must stay clean for full-bleed pages
and panel art; use **novel** when you want author/title/chapter context at
a glance while reading prose.
