# 2-pages-badge.lua

Shows a small "N p." page-count badge in the bottom-left corner of book
covers in the cover grid (mosaic) view, but only for books you have not
started: opened, finished, and deleted entries never get one. The count comes
from coverbrowser's book-info database (`BookInfoManager`), with a fallback
to a `P(123)` marker in the displayed filename.

Useful for judging the length of unread books at a glance; the badge
disappears as soon as a book is opened.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem paint path)
- **Written against:** KOReader 2026.07.1 / ProjectTitle 2026.07-v3.8.3
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.

## Settings

No in-app settings. Appearance is tuned via the constants block at the top
of the file (`patches/2-pages-badge.lua:6-14`):

| Constant | Default | What it does |
| --- | --- | --- |
| `page_font_size` | 0.95 | Text size as a fraction of the badge mark size |
| `page_text_color` | white | Badge text color |
| `border_thickness` | 2 | Badge border width (0-5) |
| `border_corner_radius` | 12 | Badge corner rounding (0-20) |
| `border_color` | dark gray | Badge border color |
| `background_color` | gray 3 | Badge background color |
| `move_from_border` | 8 | Inset from the cover's bottom-left corner |

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/2-pages-badge.lua` on the device (add a
`.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-new-progress-bar.lua` draws along the bottom of covers, but only for
  books with reading progress, while this badge only appears on unopened
  books; the two do not collide in practice.
- `2-new-status-icons.lua` uses the bottom-right corner; no overlap.
- Page counts require coverbrowser's book-info extraction to have run for
  the file (it happens automatically as covers are scanned).
