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
chosen cover is pre-scaled to the cell size and kept as a blitbuffer, so
repeat page draws skip the DB blob read, decompression, and rescaling.
Caches invalidate per file when PT extracts or refreshes books; a changed
`cover.*` file is picked up via its mtime. The cover a folder shows may
therefore differ from the pre-cache behavior (which followed the current
sort order): it is now stable across draws and sessions.

With `prewarm_folder_covers` enabled (default), a background walker
pre-builds the covers of **every** folder under the home directory at the
current grid cell size, two folders per 0.2s scheduler tick, so first
visits to new pages draw from cache too. Changing items-per-page restarts
the walk at the new size automatically. The walk pauses while a book is
open and resumes on the next folder draw. Folders without a cover of
their own get PT's collage fallback pre-warmed instead (effective when
`2-pt-foldercover-perf.lua` is installed). `cover_cache_entries` (default
500) bounds how many pre-scaled covers stay in memory: raise it if your
library has more folders, at roughly 100-400KB per folder depending on
cell size and screen type.

The patch also memoizes `FileChooser:getListItem` results to keep folder
scanning cheap while covers are resolved.

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title
  (MosaicMenuItem, `FileChooser.getListItem`)
- **Written against:** ProjectTitle 2026.03-v3.7 / KOReader 2026.03
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
