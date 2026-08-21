# 2-pt-mm-noborders.lua

Removes the horizontal separator lines Project: Title draws in its mosaic
(cover grid) view. The patch overrides two of PT's drawing helpers:
`ptutil.mediumBlackLine` returns a zero-width spacer and
`ptutil.thinGrayLine` is redirected to the thin white variant, so covers
render without border lines between sections.

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title (`ptutil`
  line helpers)
- **Written against:** ProjectTitle 2026.07-v3.8.3 / KOReader 2026.07.1
- **Requires:** Project: Title plugin installed (replaces coverbrowser);
  without it (no `ptutil` module) this patch does nothing.

## Settings

No settings. Active whenever the patch file is installed.

## Disable

Remove or rename `koreader/patches/2-pt-mm-noborders.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

Complements `2--disable-all-PT-widgets.lua` (which removes per-cover borders
and widgets) by cleaning up the view-level separator lines; the two cover
different elements and are meant to be installed together for the borderless
look.
