# 2-percent-badge.lua

Paints a progress-percentage badge on book covers in the cover grid (mosaic)
view, using this repo's `percent.badge` SVG as the backdrop with the percent
number centered on it. Badges appear only for in-progress books: the book
must have a reading position, not be finished, and either carry the "opened"
hint or be shown from History or Collections.

Note: the file's own header comment says "top right corner", but as
configured the badge is anchored to the cover's top-left edge
(`move_on_x` is measured from the left). Treat the constants block as the
source of truth for placement.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem paint path)
- **Written against:** KOReader 2026.07.1 / ProjectTitle 2026.07-v3.8.3
- **Requires:** the `percent.badge.svg` icon from this repo's `icons/` set
  installed into `koreader/resources/icons/mdlight/`

## Settings

No in-app settings. Appearance is tuned via the constants block at the top
of the file (`patches/2-percent-badge.lua:5-12`):

| Constant | Default | What it does |
| --- | --- | --- |
| `text_size` | 0.25 | Text size as a fraction of the corner mark size |
| `move_on_x` | 5 | Horizontal inset from the cover's left edge |
| `move_on_y` | -1 | Vertical offset from the cover's top edge |
| `badge_w` | 70 | Badge width (scaled) |
| `badge_h` | 40 | Badge height (scaled) |
| `bump_up` | 1 | Upward nudge of the text inside the badge |

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/2-percent-badge.lua` on the device (add a
`.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-series-badge-numbered.lua` occupies the top-right of covers; with this
  badge at the top-left the two stay clear of each other. If you reposition
  this badge to the right via `move_on_x`, they will collide on series books
  that are in progress.
- `2-new-progress-bar.lua` shows the same information as a bar at the bottom
  of the cover; both can be active, this badge just adds the number.
