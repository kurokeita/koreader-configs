## 1. Refresh reference checkouts

- [ ] 1.1 Move `_ref/ProjectTitle` to tag `2026.07-v3.8.3` and confirm `_meta.lua` no longer carries a `name` field
- [ ] 1.2 Move `_ref/koreader` to tag `v2026.07.1` and confirm `Version:getNormalizedVersion` still uses the `((year*100+month)*1000000) + point*10000 + revision` formula the pin value depends on
- [ ] 1.3 Update `scripts/setup-refs.sh` if it pins the old tags, so a fresh clone lands on the new target

## 2. Bump the manifest

- [ ] 2.1 Set `plugins/manifest.yml` to `koreader: "2026.07.1"`, `codename: Sailing Walrus`, PT `tag: "2026.07-v3.8.3"`; leave bookends at `v5.20.0`
- [ ] 2.2 Run the manifest validation in `.github/scripts/` and confirm it still passes

## 3. Mechanical registration pass

- [ ] 3.1 Change `"coverbrowser"` to `"projecttitle"` in `registerPatchPluginFunc` across the 13 PT patches: `2--disable-all-PT-widgets.lua:134`, `2-new-progress-bar.lua:108`, `2-new-status-icons.lua:116`, `2-pages-badge.lua:111`, `2-percent-badge.lua:108`, `2-pt-footer-history-recent.lua:169`, `2-pt-mm-noborders.lua:34`, `2-pt-perf.lua:597`, `2-rounded-folder-covers.lua:934`, `2-series-badge-numbered.lua:140`, `2-series-indicator.lua:78`, `20-faded-finished-books.lua:54`, `20-rounded-covers.lua:125`
- [ ] 3.2 Confirm `grep -rn '"coverbrowser"' patches/` returns no `registerPatchPluginFunc` hits, and that the 2 bookends and 2 coverimage patches were left untouched
- [ ] 3.3 Rename local patch functions named `patchCoverBrowser` to match the new target where the name is now misleading (cosmetic; upstream's own template did this)

## 4. Add version pins to all 19 patches

- [ ] 4.1 Add `KOReader 2026.07.1 (safe_version 202607010000)` to the header block of every patch in `patches/`, following the existing form in `2-pt-footer-history-recent.lua`
- [ ] 4.2 Add `local safe_version = 202607010000` to each patch that does not already declare one
- [ ] 4.3 Re-run the `koreader-version-bump` audit against `2026.07.1` and confirm 19 OK, 0 STALE, 0 UNKNOWN

## 5. Tier 3 verification (symbol confirmed present)

- [ ] 5.1 `2-pt-mm-noborders.lua` — confirm `ptutil.thinWhiteLine`, `thinGrayLine`, `mediumBlackLine` exist at v3.8.3 and the call signatures are unchanged
- [ ] 5.2 `2-pt-footer-history-recent.lua` — confirm `CoverMenu.menuInit` is unchanged at v3.8.3 and the `BookInfoManager` setting accessors it uses still resolve

## 6. Tier 2 verification (hooked body changed upstream)

- [ ] 6.1 Read the rewritten `MosaicMenuItem:paintTo` body at v3.8.3 and record where a wrapper can still hook without losing paint order
- [ ] 6.2 Verify the 8 `paintTo` wrappers against that finding: `2--disable-all-PT-widgets`, `2-new-progress-bar`, `2-new-status-icons`, `2-pages-badge`, `2-percent-badge`, `2-series-indicator`, `20-faded-finished-books`, `20-rounded-covers`
- [ ] 6.3 `2-series-badge-numbered.lua` — additionally check its `MosaicMenuItem:init` and `:free` overrides against the touched `MosaicMenuItem:update`
- [ ] 6.4 Check the series patches against upstream's new `ptutil.formatSeries` / `formatSeriesIndex` / `zeroPadIndex` / `getSeries`, given 3.8 removed its own series-formatting preferences; record whether our patches now duplicate or conflict with core behavior
- [ ] 6.5 `2-pages-badge.lua` — check against upstream's new `ptutil.getPageCount` and the 3.8 page-count sort feature
- [ ] 6.6 Repair whatever 6.1-6.5 found broken, one patch per commit

## 7. Tier 1 verification (BookInfoManager layer)

- [ ] 7.1 Read the full `bookinfomanager.lua` v3.7 → v3.8.3 diff: the schema line change at 72, the ~70 inserted lines before `getBookInfo`, and the `getBookInfo` changes
- [ ] 7.2 Answer design.md's open question — determine whether any of `2-pt-perf.lua`'s caching landed upstream in those inserted lines, and report before editing
- [ ] 7.3 Repair or delete the superseded parts of `2-pt-perf.lua`; if the outcome is a rewrite rather than a repair, stop and re-scope with the user
- [ ] 7.4 Verify `2-rounded-folder-covers.lua`'s `BookInfoManager` cache-registry wrapping against the changed layer, including the folder-cover helpers in `ptutil` (`getFolderCover`, `query_cover_paths`, `build_cover_images`)
- [ ] 7.5 Confirm the two Tier 1 patches do not conflict with each other after repair, since both wrap the same `BookInfoManager` methods

## 8. Sweep version references

- [ ] 8.1 Update `docs/installation.md` to KOReader `2026.07.1` "Sailing Walrus" / PT `2026.07-v3.8.3`, and note that PT writes this release as `2026.07.01`
- [ ] 8.2 Update the "Written against" line in all 19 `docs/patches/*.md`
- [ ] 8.3 Regenerate `patches/README.md` with the `patch-changelog` skill rather than hand-editing it
- [ ] 8.4 Confirm `grep -rn '2026\.03\|v3\.7\|Snowflake' --include='*.md' --include='*.yml' --include='*.lua' .` returns only intentional historical references

## 9. Record verification state and close out

- [ ] 9.1 Record each patch's verification level (symbol-level vs verified against changed code) where the repo tracks patch metadata, per the spec's third requirement
- [ ] 9.2 Note explicitly that verification was static only, with no device or emulator run
- [ ] 9.3 Manual smoke test on device against KOReader 2026.07.1 + PT v3.8.3 before any release tag
- [ ] 9.4 Run `openspec validate koreader-2026-07-patch-compat --strict` and archive the change
