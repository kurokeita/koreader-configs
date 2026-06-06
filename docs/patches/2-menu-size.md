# 2-menu-size.lua

Scales how many items KOReader menus show per page to match the screen's
real pixel density. When a custom DPI is configured (Screen settings), stock
KOReader keeps the default per-page counts, which makes rows cramped at
higher DPI. This patch compares the configured DPI against the device
default and shrinks `TouchMenu.max_per_page_default` and
`Menu.items_per_page_default` by that ratio, preserving comfortable touch
target sizes. With DPI at or below the device default, nothing changes (the
ratio is capped at 1).

## Target

- **Patches:** KOReader core (`ui/widget/menu`, `ui/widget/touchmenu`)
- **Written against:** KOReader 2026.03

## Settings

No settings. Active whenever the patch file is installed; the scaling
follows the DPI configured under
`Top menu > Settings (gear) > Screen > Screen DPI`.

## Disable

Remove or rename `koreader/patches/2-menu-size.lua` on the device (add a
`.disabled` suffix to keep it around), then restart KOReader.

## Interactions

Only adjusts the *defaults*; an explicit per-menu "items per page" override
set in KOReader's menus still wins.
