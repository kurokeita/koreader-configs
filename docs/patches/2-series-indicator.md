# 2-series-indicator.lua

Marks books that belong to a series with a slim gray tab sticking out of the
right edge of the cover (left edge in mirrored/RTL layouts) in the cover grid
(mosaic) view. The tab is about 6 px wide, an eighth of the cover height, and
sits 40 px down from the cover's top edge; any series metadata on the book
triggers it, no series index needed. The patch extends the item's refresh
region so the protruding tab is repainted correctly.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem paint path)
- **Written against:** KOReader 2026.07.1 / ProjectTitle 2026.07-v3.8.3

## Settings

No settings. Active whenever the patch file is installed. Size and position
are hard-coded in the paint routine (`d_w`, `d_h`, `iy` in
`patches/2-series-indicator.lua:47-70`).

## Disable

Remove or rename `koreader/patches/2-series-indicator.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-series-badge-numbered.lua` marks the same books with a "#N" pill in the
  top-right of the cover; running both double-marks every series book and
  the two sit close together. Pick one: the pill if you want the series
  number, this tab if you want a subtler hint.
- The tab paints at the cover edge and slightly outside it, away from the
  corners used by the status icons and page badges; no other conflicts.
