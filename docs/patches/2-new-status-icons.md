# 2-new-status-icons.lua

Replaces the reading-status corner marks on book covers in the cover grid
(mosaic) view with this repo's dogear icons, painted with alpha blending in
the bottom-right corner (bottom-left in mirrored/RTL layouts):

- `dogear.reading` while a book is in progress
- `dogear.complete` when finished
- `dogear.abandoned` when on hold

Icons are shown for finished and abandoned books always, and for in-progress
books when the "opened" hint applies or the cover is shown from History or
Collections. The patch also forces `alpha = true` on every corner-mark
`IconWidget` so the transparent SVGs composite cleanly over cover art.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem paint path) and
  `IconWidget`; written for Project: Title's mosaic view
- **Written against:** ProjectTitle 2026.07-v3.8.3 / KOReader 2026.07.1
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.
- **Requires:** the `dogear.reading.svg`, `dogear.complete.svg`, and
  `dogear.abandoned.svg` icons from this repo's `icons/` set installed into
  `koreader/resources/icons/mdlight/`

## Settings

No settings. Active whenever the patch file is installed. Icon size is
derived from the cover size (one eighth of the smaller cover dimension).

## Disable

Remove or rename `koreader/patches/2-new-status-icons.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2--disable-all-PT-widgets.lua` disables Project: Title's stock status
  marks; install both so the new icons are not painted over PT's own marks.
- `2-new-progress-bar.lua` shortens its bar to make room for these icons in
  the bottom-right corner.
- `2-pages-badge.lua` sits in the opposite (bottom-left) corner; no overlap.
