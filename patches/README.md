# Patches

Userpatches applied at KOReader startup. Drop into `koreader/patches/` on your
device.

> This file is a generated index — do not hand-edit it. Regenerate with the
> `patch-changelog` skill after adding, removing, or renaming a patch.

Every patch below targets KOReader **2026.07.1** ("Sailing Walrus"). The
Targets column names the plugin each one hooks; `core` means it patches
KOReader itself rather than a plugin.

## Active

| Priority | File | Targets | Summary |
| --- | --- | --- | --- |
| 2 | [`2--disable-all-PT-widgets.lua`](../docs/patches/2--disable-all-PT-widgets.md) | projecttitle (v3.8.3) | Disable specific Project: Title UI elements: progress/status icons & widgets, cover borders, and series indicators. |
| 2 | [`2-bookend-line-font-inherit.lua`](../docs/patches/2-bookend-line-font-inherit.md) | bookends (v5.22.0) | Add an "Inherit" option to the per-line font picker. |
| 2 | [`2-bookend-unifont.lua`](../docs/patches/2-bookend-unifont.md) | bookends (v5.22.0) | Render Bookends overlays in the open book's embedded font. |
| 2 | [`2-coverimage-eink-optimize.lua`](../docs/patches/2-coverimage-eink-optimize.md) | coverimage | Cover image optimization for color e-ink screens (gamma lift, saturation boost, S-curve contrast). |
| 2 | [`2-coverimage-lighten.lua`](../docs/patches/2-coverimage-lighten.md) | coverimage | Add a "Lighten for color e-ink" slider to the Cover Image menu. |
| 2 | [`2-disable-input-rotation-map.lua`](../docs/patches/2-disable-input-rotation-map.md) | core | Stop KOReader from remapping touch input on rotation. |
| 2 | [`2-menu-size.lua`](../docs/patches/2-menu-size.md) | core | Scale menu item counts to the screen's real DPI. |
| 2 | [`2-new-progress-bar.lua`](../docs/patches/2-new-progress-bar.md) | projecttitle (v3.8.3) | Add a custom rounded progress bar to book covers. |
| 2 | [`2-new-status-icons.lua`](../docs/patches/2-new-status-icons.md) | projecttitle (v3.8.3) | Replace Project: Title corner status marks with new status icons. |
| 2 | [`2-pages-badge.lua`](../docs/patches/2-pages-badge.md) | projecttitle (v3.8.3) | Add page-count badges for unread books. |
| 2 | [`2-percent-badge.lua`](../docs/patches/2-percent-badge.md) | projecttitle (v3.8.3) | Add progress-percentage badges on book covers. |
| 2 | [`2-pt-footer-history-recent.lua`](../docs/patches/2-pt-footer-history-recent.md) | projecttitle (v3.8.3) | Add History and Open-Previous-Document icon buttons to Project: Title's file-browser footer. |
| 2 | [`2-pt-mm-noborders.lua`](../docs/patches/2-pt-mm-noborders.md) | projecttitle (v3.8.3) | Remove separator lines in Project: Title's mosaic view. |
| 2 | [`2-pt-perf.lua`](../docs/patches/2-pt-perf.md) | projecttitle (v3.8.3) | File-browser performance fixes: blob-free cached metadata lookups and cached, deterministic auto folder covers. |
| 2 | [`2-rounded-folder-covers.lua`](../docs/patches/2-rounded-folder-covers.md) | projecttitle (v3.8.3) | Give folders in mosaic view real cover images with rounded corners. |
| 2 | [`2-series-badge-numbered.lua`](../docs/patches/2-series-badge-numbered.md) | projecttitle (v3.8.3) | Add a numbered series indicator to the top-right of book covers. |
| 2 | [`2-series-indicator.lua`](../docs/patches/2-series-indicator.md) | projecttitle (v3.8.3) | Add a series indicator to the right side of book covers. |
| 20 | [`20-faded-finished-books.lua`](../docs/patches/20-faded-finished-books.md) | projecttitle (v3.8.3) | Add a faded look for finished books in mosaic view. |
| 20 | [`20-rounded-covers.lua`](../docs/patches/20-rounded-covers.md) | projecttitle (v3.8.3) | Add rounded corners to book covers. |

## Disabled

| File | Summary |
| --- | --- |

_(none)_
