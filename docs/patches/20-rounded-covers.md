# 20-rounded-covers.lua

Adds rounded corners to book covers in the cover grid (mosaic) view by
painting the four `rounded.corner.*` SVG overlays over the corners of each
cover, plus a thin black border around the cover content. Directories are
skipped (folder covers are handled by `2-rounded-folder-covers.lua`).

The `20-` priority prefix makes this patch load after all the `2-` patches,
so the corner overlays and border are painted on top of the fully decorated
cover and stay crisp.

## Target

- **Patches:** coverbrowser plugin (MosaicMenuItem paint path); written for
  Project: Title's mosaic view
- **Written against:** ProjectTitle 2026.07-v3.8.3 / KOReader 2026.07.1
- **Requires:** the `rounded.corner.{tl,tr,bl,br}.svg` icons from this
  repo's `icons/` set installed into `koreader/resources/icons/mdlight/`.

## Settings

No in-app settings. The border thickness is hard-coded
(`cover_border` at `patches/20-rounded-covers.lua:67`, 0.5 scaled).

## Disable

Remove or rename `koreader/patches/20-rounded-covers.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-rounded-folder-covers.lua` applies the same treatment to folder cells;
  install both for a uniform look.
- `20-faded-finished-books.lua` sorts before this file within the `20-`
  group, so finished books are faded first and the corners are painted after,
  unfaded.
- The corner overlays paint over whatever the badge patches placed in the
  cover corners; the SVGs are small and mostly transparent, so in practice
  the badges stay readable.
