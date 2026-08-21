# 2-new-progress-bar.lua

Draws a custom rounded progress bar near the bottom edge of each book cover
in the cover grid (mosaic) view. The bar shows the book's reading progress as
a dark fill on a light track with a thin black border, and is skipped
entirely for finished books. For abandoned/paused books the fill turns light
gray. When a corner status icon is present (reading/complete/abandoned), the
bar shortens so it never runs underneath the icon.

Only books with a recorded reading position (`percent_finished`) get a bar,
and only in mosaic view; list views are untouched.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem paint path)
- **Written against:** KOReader 2026.07.1 / ProjectTitle 2026.07-v3.8.3
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.

## Settings

No in-app settings. Appearance is tuned via the constants block at the top
of the file (`patches/2-new-progress-bar.lua:10-21`):

| Constant | Default | What it does |
| --- | --- | --- |
| `BAR_H` | 9 (scaled) | Bar height |
| `BAR_RADIUS` | 3 (scaled) | Corner rounding of track and fill |
| `INSET_X` | 6 (scaled) | Distance from the cover's inner left/right edges |
| `INSET_Y` | 12 (scaled) | Distance from the cover's inner bottom edge |
| `GAP_TO_ICON` | 0 | Extra gap before the corner status icon |
| `TRACK_COLOR` | `#F4F0EC` | Track (background) color |
| `FILL_COLOR` | `#555555` | Progress fill color |
| `ABANDONED_COLOR` | `#C0C0C0` | Fill color for abandoned/paused books |
| `BORDER_W` | 0.5 (scaled) | Border width around the track, 0 disables |
| `BORDER_COLOR` | black | Border color |

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/2-new-progress-bar.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-new-status-icons.lua` paints the bottom-right status icon this bar makes
  room for; the two are designed to coexist.
- `2-pages-badge.lua` occupies the bottom-left of covers, but only for
  unopened books, which normally have no `percent_finished` and therefore no
  bar; overlap does not occur in practice.
- Project: Title's own progress widgets are turned off by
  `2--disable-all-PT-widgets.lua`, which is what makes room for this bar.
