# Proposal

## Why

KOReader 2026.07 removed the `name` field from plugin `_meta.lua` and now derives a
plugin's identity from its folder name minus `.koplugin`. Project: Title consequently
stopped identifying itself as `coverbrowser`, so all 13 of this repo's PT userpatches
register against a plugin name that no longer exists. `userpatch.registerPatchPluginFunc`
silently no-ops on an unknown name, so every PT patch stops working with no error and no
log line. The repo currently pins KOReader `2026.03` / PT `2026.03-v3.7`, two releases
behind, and the two highest-risk patches carry no version pin at all.

## What Changes

- **BREAKING** Move the pinned target from KOReader `2026.03` "Snowflake" / PT
  `2026.03-v3.7` to KOReader `2026.07.1` "Sailing Walrus" / PT `2026.07-v3.8.3`. Patches
  from this change onward do not work on KOReader 2026.03.
- Change the plugin key in `userpatch.registerPatchPluginFunc` from `"coverbrowser"` to
  `"projecttitle"` in the 13 PT-targeting patches.
- Re-verify the patches whose hooked upstream symbols moved between PT v3.7 and v3.8.3,
  in risk order, and repair the ones that broke.
- Give every patch an explicit, machine-readable KOReader version pin. Today only 3 of
  19 declare one, which is why the staleness of the other 16 was invisible.
- Update the version references that trail the manifest: `plugins/manifest.yml`,
  `docs/installation.md`, `patches/README.md`, and the 19 `docs/patches/*.md`
  "Written against" lines.
- Refresh the `_ref/` checkouts so the compatibility claims in this change are
  verifiable rather than asserted.

## Capabilities

### New Capabilities

- `patch-compatibility`: The contract every userpatch in this repo must satisfy to
  actually take effect on its declared KOReader target — correct plugin registration
  identity, an explicit version pin, and a stated verification level against the pinned
  upstream.

### Modified Capabilities

<!-- None. This repo has no existing specs under openspec/specs/. -->

## Impact

**Patch source (13 files, one line each)** — `2--disable-all-PT-widgets.lua:134`,
`2-new-progress-bar.lua:108`, `2-new-status-icons.lua:116`, `2-pages-badge.lua:111`,
`2-percent-badge.lua:108`, `2-pt-footer-history-recent.lua:169`,
`2-pt-mm-noborders.lua:34`, `2-pt-perf.lua:597`, `2-rounded-folder-covers.lua:934`,
`2-series-badge-numbered.lua:140`, `2-series-indicator.lua:78`,
`20-faded-finished-books.lua:54`, `20-rounded-covers.lua:125`.

**Patch source (deeper repair, scope not yet known)** — `2-pt-perf.lua` and
`2-rounded-folder-covers.lua` wrap the whole `BookInfoManager` cache and DB layer, which
gained a schema change and ~70 new lines around `getBookInfo` in v3.8.3.

**Config and docs** — `plugins/manifest.yml`, `docs/installation.md`,
`patches/README.md`, `docs/patches/*.md` (19 files).

**Reference checkouts** — `_ref/ProjectTitle` (at `ac3f010`, 2026-05-26, pre-3.8),
`_ref/koreader` (at `9c5e596`, 2026-06-02).

**Unaffected** — the 2 bookends patches (folder `bookends.koplugin` already derives the
name `bookends` they register against), the 2 coverimage patches, and the 2 core patches
`2-menu-size.lua` and `2-disable-input-rotation-map.lua`.

**Explicitly out of scope** — bumping bookends past the current `v5.20.0` pin (`v5.22.0`
is available). Unrelated to the plugin-identity break; belongs in its own change.
