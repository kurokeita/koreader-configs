# 2-pt-bookinfo-cache.lua

Makes Project: Title's metadata lookups cheap: a blob-free SQL statement
plus an in-memory cache in front of `BookInfoManager:getBookInfo`.

Upstream PT uses a single prepared SELECT that fetches every column of a
book's row, including the zstd-compressed cover blob (50-200KB), even when
the caller only wants metadata (`get_cover=false`). Those metadata-only
lookups sit on the hottest paths in the file browser:

- `MosaicMenuItem:paintTo` re-queries the database for every visible book
  on **every repaint** (page turns, closing dialogs, partial refreshes);
- PT's custom sort collates (Title / Author / Series / fullmeta) query
  once per file every time a folder's item table is generated;
- the `ptutil` metadata getters used by other patches do the same.

SQLite has to read the blob's overflow pages off storage to materialize
the row each time, so every "what series is this" lookup pays a cover-blob
I/O tax.

The patch wraps `getBookInfo` so metadata-only lookups:

- use a second prepared statement that excludes the three cover columns,
  discovered from PT's own `BOOKINFO_COLS_SET` upvalue (no hardcoded
  schema);
- are answered from an in-memory cache keyed by filepath, so repaints and
  re-sorts skip SQLite entirely. Callers receive a shallow copy because PT
  mutates returned tables in place.

Correctness guards:

- books not yet in the DB are **never cached**, so background-extraction
  results still appear via PT's normal update loop;
- the cache clears whenever PT rewrites rows (`setBookInfoProperties`,
  `deleteBookInfo`, `deleteDb`);
- cover lookups (`get_cover=true`), directories, unsupported files, and
  Kobo virtual-library paths pass through to upstream untouched;
- the prepared statement is dropped whenever PT closes its shared DB
  connection (subprocess forks, browser close) and re-prepared lazily;
- the cache is bounded (1000 entries, cleared wholesale on overflow).

`getDocProps` is rebuilt on top of the cached path, returning the same
pages-through-description slice as upstream.

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title
  (`BookInfoManager.getBookInfo`, `getDocProps`, `closeDbConnection`;
  wraps `setBookInfoProperties`/`deleteBookInfo`/`deleteDb` for cache
  invalidation)
- **Written against:** ProjectTitle 2026.03-v3.7 / KOReader 2026.03
- **Requires:** Project: Title plugin installed (replaces coverbrowser).
  The patch verifies PT's column layout via upvalue inspection and refuses
  to patch (with a `crash.log` warning) if internals have moved.

## Settings

No settings. Active whenever the patch file is installed.

## Disable

Remove or rename `koreader/patches/2-pt-bookinfo-cache.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- Complements `2-pt-foldercover-perf.lua`: that patch fixes folder tiles,
  this one fixes book tiles and sorting. Install both for the full effect;
  they are independent and safe in any combination.
- Benefits other patches in this repo that read metadata per item
  (`2-series-badge-numbered.lua`, `2-series-indicator.lua`,
  `2-pages-badge.lua`, `2-percent-badge.lua` and friends) since their
  lookups hit the cache instead of SQLite.
- Does not change what is displayed, only how fast it is fetched.
