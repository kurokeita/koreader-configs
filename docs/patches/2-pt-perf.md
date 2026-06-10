# 2-pt-perf.lua

Project: Title file-browser performance fixes, two independent sections in
one patch (formerly `2-pt-bookinfo-cache.lua` and
`2-pt-foldercover-perf.lua`). Nothing changes visually except that auto
folder-cover thumbnails stop reshuffling between page draws.

## Section 0: shared cache-invalidation registry

All caches (here and in `2-rounded-folder-covers.lua`) register listeners
on one registry that wraps every PT path that writes bookinfo rows:

- `setBookInfoProperties` ("Ignore cover/metadata" buttons) and
  `deleteBookInfo` notify per file;
- background extraction notifies at subprocess **completion** (observed
  by the zombie reaper), because rows commit after `extractInBackground`
  returns; invalidating at launch would let the next draw cache a stale
  negative result;
- batch indexing and the home-folder autoscan (`extractBooksInDirectory`)
  notify a full clear when the run ends;
- `deleteDb` (cache emptied) notifies a full clear.

While any extraction may still be writing rows, negative lookups ("this
folder has no covers") are not cached, so results from a running scan
appear without a restart. The registry is installed idempotently by
whichever of the two patches loads first.

## Section 1: blob-free metadata queries and an in-memory cache

Upstream PT uses a single prepared SELECT that fetches every column of a
book's row, including the zstd-compressed cover blob (50-200KB), even when
the caller only wants metadata (`get_cover=false`). Those metadata-only
lookups sit on the hottest paths:

- `MosaicMenuItem:paintTo` re-queries the database for every visible book
  on **every repaint** (page turns, closing dialogs, partial refreshes);
- PT's custom sort collates (Title / Author / Series / fullmeta) query
  once per file every time a folder's item table is generated;
- the `ptutil` metadata getters used by other patches do the same.

The patch wraps `getBookInfo` so metadata-only lookups use a second
prepared statement that excludes the three cover columns (layout
discovered from PT's own `BOOKINFO_COLS_SET` upvalue, no hardcoded
schema) and are answered from a two-generation in-memory cache keyed by
filepath (an overflow drops the oldest half instead of everything, so
whole-library iterations like PT's sort collates don't dump still-hot
entries mid-pass). Callers receive a shallow copy because PT mutates
returned tables in place. Correctness guards:

- books not yet in the DB are **never cached**, so background-extraction
  results still appear via PT's normal update loop;
- row rewrites invalidate precisely via the shared registry (per file for
  property changes and deletions, batch-wide for scans);
- cover lookups (`get_cover=true`), directories, unsupported files, and
  Kobo virtual-library paths pass through to upstream untouched;
- the prepared statement is dropped whenever PT closes its shared DB
  connection and re-prepared lazily.

`getDocProps` is rebuilt on top of the cached path, returning the same
pages-through-description slice as upstream.

## Section 2: cached auto-generated folder covers

Upstream PT rebuilds every folder tile from scratch on every page draw: a
directory scan probing for a `cover.*` image, one or two **new SQLite
connections** running `ORDER BY RANDOM()` queries (a scan-and-sort of
every cached book under the folder's subtree), and up to four cover blobs
zstd-decompressed at 600px and rescaled to quarter-tile thumbnails.
`RANDOM()` makes all of it uncacheable and visibly reshuffles thumbnails
each draw.

The patch replaces PT's folder-cover helpers in `ptutil` to:

- query deterministically (`ORDER BY directory, filename LIMIT 8`), riding
  the `dir_filename` index, which also makes thumbnails stable;
- reuse BookInfoManager's shared DB connection (upstream opens a fresh one
  per query, and leaks it when the folder no longer exists);
- cache the chosen cover paths per folder and the scaled thumbnail
  blitbuffers per book+size (two byte-budgeted generations, ~8MB total),
  so repeat draws skip queries and decompression;
- cache the cover-file probe result and image dimensions for folders with
  their own cover image (mtime-keyed; a vanished cover file is detected
  by a per-draw stat and re-probed).

Invalidation is scoped via the shared registry: changed files drop only
their own thumbnails and the cached cover picks of folders containing
them; batch scans and cache emptying clear everything; negative results
are not cached while a scan is writing. Evicted buffers are reclaimed by
GC rather than freed explicitly, since live widgets may still reference
them. `ptutil.make_sql_safe` is inlined as a fallback for PT releases
(like the pinned v3.7) that predate it.

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title
  (`BookInfoManager` query/lifecycle/mutation methods wrapped;
  `ptutil.query_cover_paths`, `ptutil.build_cover_images`,
  `ptutil.getSubfolderCoverImages`, `ptutil.getFolderCover` replaced)
- **Written against:** ProjectTitle 2026.03-v3.7 / KOReader 2026.03
- **Requires:** Project: Title plugin installed (replaces coverbrowser).
  Each section version-guards itself independently and skips with a log
  warning if PT's internals have moved; one section bailing does not
  disable the other.

## Settings

No settings. Active whenever the patch file is installed.

## Disable

Remove or rename `koreader/patches/2-pt-perf.lua` on the device (add a
`.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- `2-rounded-folder-covers.lua` builds its own folder covers on top of
  PT's; its source resolution and fallback collage ride this patch's
  caches, so the two are meant to be installed together (but each works
  alone).
- Patches that read metadata per item (`2-series-badge-numbered.lua`,
  `2-series-indicator.lua`, `2-pages-badge.lua`, `2-percent-badge.lua`)
  hit the metadata cache instead of SQLite.
- Both sections keep the internal idempotence markers of the two former
  separate patches, so accidentally having an old copy of either
  installed alongside this one does not double-patch anything.
