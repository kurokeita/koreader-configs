# 2-pt-foldercover-perf.lua

Caches Project: Title's auto-generated folder covers, the single biggest
source of file-browser sluggishness in folder-heavy libraries.

Upstream PT rebuilds every folder tile from scratch on every page draw:

- a full directory scan probing for a `cover.*`/`folder.*` image file,
- one or two **new SQLite connections** running `ORDER BY RANDOM()` queries,
  which scan and sort every cached book under the folder's subtree,
- up to four cover blobs zstd-decompressed at 600px and rescaled down to
  quarter-tile thumbnails.

Because `RANDOM()` returns different rows on every call, none of this is
cacheable upstream, and the folder thumbnails visibly reshuffle on every
page turn. A grid page with several folders pays for all of it on each
draw.

The patch replaces PT's folder-cover helpers in `ptutil` with versions
that:

- query deterministically (`ORDER BY directory, filename LIMIT 8`), riding
  the `dir_filename` index instead of sorting the subtree, which also makes
  thumbnails stable across page turns;
- reuse BookInfoManager's shared DB connection (upstream opens a fresh one
  per query, and leaks it when the folder no longer exists);
- cache the chosen cover paths per folder, and the scaled thumbnail
  blitbuffers per book+size, so repeat draws skip the queries and the
  decompress+rescale work entirely;
- cache the cover-file probe result and the image dimensions for folders
  with their own cover image, removing a directory scan and a throwaway
  full decode per draw.

Caches are invalidated whenever PT mutates its bookinfo cache (background
extraction, per-book refresh, cache emptying). The thumbnail cache holds at
most 100 entries (roughly 25 folders); evicted buffers are reclaimed by GC
rather than freed explicitly, since live widgets may still reference them.

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title
  (`ptutil.query_cover_paths`, `ptutil.build_cover_images`,
  `ptutil.getSubfolderCoverImages`, `ptutil.getFolderCover`; wraps
  `BookInfoManager.extractInBackground`/`deleteBookInfo`/`deleteDb` for
  cache invalidation)
- **Written against:** ProjectTitle 2026.03-v3.7 / KOReader 2026.03
- **Requires:** Project: Title plugin installed (replaces coverbrowser).
  The patch version-guards every function it replaces and refuses to patch
  (with a `crash.log` warning) if PT's internals have moved.

## Settings

No settings. Active whenever the patch file is installed. PT's own
"Auto-generate cover images from books" toggle still controls whether
auto folder covers appear at all.

## Disable

Remove or rename `koreader/patches/2-pt-foldercover-perf.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-rounded-folder-covers.lua` replaces mosaic folder tiles with its own
  covers *after* PT has built its version, so without this patch folder
  tiles paid the full upstream cost for work that was then thrown away.
  With this patch the wasted work becomes cheap cache hits. The two patches
  are independent and can be installed together.
- Behavioral change vs upstream: folder thumbnails are picked
  deterministically (first covers by directory/filename order) instead of
  randomly, so they no longer change on every page draw.
