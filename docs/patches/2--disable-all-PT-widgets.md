# 2--disable-all-PT-widgets.lua

Strips Project: Title's own decorations from book covers in the cover grid
(mosaic) view, clearing the canvas for this repo's replacement patches. It
suppresses, during each item's paint pass:

- **Progress icons:** PT's `trophy.svg`, `pause.svg`, `new.svg`, and
  `large_book.svg` resource images are skipped entirely.
- **Progress bars:** `ProgressWidget` painting is disabled while the stock
  item paints (the book's real progress is restored afterwards for other
  patches to use).
- **Status frames:** the item's `status` and `percent_finished` are hidden
  from the stock painter, so complete/abandoned frames never render.
- **Cover borders:** border size, padding, and background of the cover frame
  are zeroed during paint.
- **Series indicators:** PT's `series_mode` setting reads as off during
  paint.

It also pins two coverbrowser settings: `hide_file_info` is forced to true
and `show_pages_read_as_progress` to false, both at load time and whenever
anything tries to change them, so toggling them in PT's menu has no effect
while this patch is installed.

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title
  (MosaicMenuItem paint path, `ImageWidget`, `BookInfoManager` settings)
- **Written against:** ProjectTitle 2026.07-v3.8.3 / KOReader 2026.07.1
- **Requires:** Project: Title plugin installed (replaces coverbrowser);
  without it this patch does nothing useful.

## Settings

No settings. Active whenever the patch file is installed. The double hyphen
in the filename makes it sort, and therefore load, before the other `2-`
patches that draw replacements.

## Disable

Remove or rename `koreader/patches/2--disable-all-PT-widgets.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.
Note that `hide_file_info` and `show_pages_read_as_progress` keep their last
forced values in coverbrowser's settings database; flip them back in PT's
menu after removing the patch if you want the stock look.

## Interactions

This patch is the foundation the replacement set builds on:

- `2-new-status-icons.lua` draws the new corner status icons in the space
  PT's marks vacated.
- `2-new-progress-bar.lua` draws the custom progress bar where PT's was
  suppressed.
- `2-series-badge-numbered.lua` / `2-series-indicator.lua` replace the
  disabled series indicators.

Without this patch, those decorations would render on top of PT's own.
