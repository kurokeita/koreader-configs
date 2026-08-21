# 2-series-badge-numbered.lua

Adds a bordered "#N" badge flush to the top-right corner of book covers in
the cover grid (mosaic) view for books that belong to a series, where N is the
book's position in the series (`series_index` from coverbrowser's book-info
database). In mirrored/RTL layouts the badge moves to the top-left. Books
without both a series name and a series index get no badge.

The badge is styled to match the folder item-count badge from
[`2-rounded-folder-covers.lua`](2-rounded-folder-covers.md) and the progress
badge from [`2-percent-badge.lua`](2-percent-badge.md): a square content box
rounded by its own radius, light grey fill, thin border, bold text.

The badge widget is built once per item at init time and freed with it, so
scrolling stays cheap.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem init/paint/free)
- **Written against:** KOReader 2026.07.1 / ProjectTitle 2026.07-v3.8.3
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.

## Settings

No in-app settings. Appearance is tuned via the constants block at the top
of the file (`patches/2-series-badge-numbered.lua:16-22`):

| Constant | Default | What it does |
| --- | --- | --- |
| `font_size` | 11 | Badge text size |
| `move_on_x` | 0 | Horizontal inset from the cover's right edge; 0 is flush |
| `move_on_y` | 0 | Vertical inset from the cover's top edge; 0 is flush |
| `border_thickness` | 1 | Badge border width (0-5) |
| `text_color` | `#000000` | Badge text color |
| `border_color` | `#000000` | Badge border color |
| `background_color` | gray E | Badge fill color |

The badge sizes itself to its text, so there is no corner-radius constant: the
radius is derived to round the square content box into a circle.

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/2-series-badge-numbered.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-series-indicator.lua` marks the same books with a gray tab on the right
  edge of the cover; running both double-marks every series book, and the
  tab sits close to this badge. Pick one: this badge if you want the series
  number, the tab if you want a subtler hint.
- `2-percent-badge.lua` is anchored flush top-left in the matching style, so
  the two sit in opposite corners and do not collide.
