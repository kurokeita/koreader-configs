# 2-rounded-folder-covers.lua

Gives folders in the cover grid (mosaic) view real cover images with rounded
corners, replacing Project: Title's stock folder cells. For each folder it
looks for a `.cover.{jpg,jpeg,png,webp,gif}` file in the folder, falling back
to the first contained book's cached cover. On top of the image it draws:

- rounded-corner overlays (the same SVG technique as `20-rounded-covers.lua`)
- an optional folder-name plate, centered or top-aligned, auto-shrinking to
  fit
- an item-count badge in the bottom-right corner
- a thin black border around the image

Folder covers are resolved once and cached. The fallback book is picked
deterministically from PT's bookinfo DB (first by filename with a usable
cover) instead of rebuilding the folder's item table on every draw, and the
chosen cover is pre-scaled to the cell size and kept in a byte-budgeted
blitbuffer cache, so repeat page draws skip the DB blob read,
decompression, and rescaling. The cover a folder shows may therefore
differ from the pre-cache behavior (which followed the current sort
order): it is now stable across draws and sessions. If a folder's
`cover.*` file is unreadable, the patch falls back to a book cover, same
as before caching.

Invalidation goes through the shared registry installed by this patch or
`2-pt-perf.lua` (whichever loads first), which wraps every PT path that
writes bookinfo rows: per-file invalidation on property changes ("Ignore
cover") and per-book refreshes, completion-time invalidation for
background extraction (rows commit after the launch call returns), and a
full clear plus pre-warm restart when a batch scan (including the
home-folder autoscan) finishes or the cache database is emptied. While a
scan may still be writing rows, "no cover found" results are not cached,
so covers appear as the scan progresses. A changed `cover.*` file is
picked up via its mtime, and a deleted one is detected and re-resolved on
the next draw; a newly **added** `cover.*` file in an already-cached
folder is only noticed after the next scan/restart.

With `prewarm_folder_covers` enabled (default), a background walker
pre-builds the covers of **every** folder under the home directory at the
current grid cell size. The directory tree is expanded incrementally (a
few directories plus two covers per 0.2s scheduler tick), so nothing
blocks the draw path, and the walk keeps running while a book is open so
the browser is warm on return. Changing items-per-page restarts the walk
at the new size automatically. Folders without a cover of their own get
PT's collage fallback pre-warmed instead (effective when `2-pt-perf.lua`
is installed). `cover_cache_mb` (default 24) bounds the memory used by
pre-scaled covers in megabytes; raise it for very folder-heavy libraries.

When PT's **"Scan home folder for new books automatically"**
(`autoscan_on_eject`) is enabled, the walk additionally starts ~10s after
app startup, in the background, even when KOReader opens straight into a
book. The grid cell size is re-derived from the last session's persisted
value (`rfc_prewarm_cell` in PT's settings store, written off the draw
path); on the very first session there is nothing persisted yet, so the
startup warm begins with the first folder draw instead.

The patch also memoizes `FileChooser:getListItem` results to keep folder
scanning cheap while covers are resolved.

## Target

- **Patches:** projecttitle plugin (MosaicMenuItem,
  `FileChooser.getListItem`)
- **Written against:** ProjectTitle 2026.07-v3.8.3 / KOReader 2026.07.1
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.
- **Requires:** Project: Title plugin installed; the
  `rounded.corner.{tl,tr,bl,br}.svg` icons from this repo's `icons/` set
  installed into `koreader/resources/icons/mdlight/`.

## Settings

Two toggles are added to PT's existing menu:
`Top menu > first tab (settings) > Mosaic and detailed list settings`

| Option | Default | What it does | Recommended |
| --- | --- | --- | --- |
| Show folder name | on | Shows or hides the folder-name plate over the cover | on |
| Folder name centered | on | Centers the plate; off pins it to the top | on |

Both persist in coverbrowser's settings database (BookInfoManager keys
`folder_name_show`, `folder_name_centered`).

Further appearance tuning lives in the constants block at the top of the
file (`patches/2-rounded-folder-covers.lua:44-52`):

| Constant | Default | What it does |
| --- | --- | --- |
| `aspect_ratio` | 2/3 | Folder cover aspect ratio |
| `stretch_limit` | 50 | Image stretching limit (percent) |
| `fill` | false | Fill the whole cell, ignoring aspect ratio |
| `file_count_size` | 14 | Item-count badge font size |
| `folder_font_size` | 20 | Folder-name font size |
| `folder_border` | 0.5 | Border thickness around the cover |
| `folder_name` | true | Initial default for "Show folder name" |

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/2-rounded-folder-covers.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `20-rounded-covers.lua` rounds *book* covers; this patch rounds *folder*
  covers. Install both for a uniform look.
- The badge patches (`2-pages-badge`, `2-percent-badge`, series patches)
  skip directories, so they never draw on folder cells.
- To curate a folder's image, drop a `.cover.jpg` (or png/webp/gif) into the
  folder; it wins over the first-book fallback.
