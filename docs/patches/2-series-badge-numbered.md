# 2-series-badge-numbered.lua

Adds a rounded "#N" pill to the top-right area of book covers in the cover
grid (mosaic) view for books that belong to a series, where N is the book's
position in the series (`series_index` from coverbrowser's book-info
database). In mirrored/RTL layouts the pill moves to the top-left. Books
without both a series name and a series index get no pill.

The badge widget is built once per item at init time and freed with it, so
scrolling stays cheap.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem init/paint/free)
- **Written against:** KOReader 2026.07.1 / ProjectTitle 2026.07-v3.8.3
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.

## Settings

No in-app settings. Appearance is tuned via the constants block at the top
of the file (`patches/2-series-badge-numbered.lua:12-19`):

| Constant | Default | What it does |
| --- | --- | --- |
| `font_size` | 11 | Pill text size |
| `border_thickness` | 1 | Pill border width (0-5) |
| `border_corner_radius` | 9 | Pill corner rounding (0-20) |
| `text_color` | `#000000` | Pill text color |
| `border_color` | `#000000` | Pill border color |
| `background_color` | gray E | Pill background color |

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/2-series-badge-numbered.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-series-indicator.lua` marks the same books with a gray tab on the right
  edge of the cover; running both double-marks every series book, and the
  tab sits close to this pill. Pick one: this pill if you want the series
  number, the tab if you want a subtler hint.
- `2-percent-badge.lua` is anchored top-left as configured, so it does not
  collide with this pill.
