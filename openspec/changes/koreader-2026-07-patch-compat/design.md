## Context

See `proposal.md` — Why, for motivation. The constraints that shape the approach:

**The break is silent by construction.** `userpatch.registerPatchPluginFunc(name, fn)`
stores `fn` against `name` and applies it when a plugin of that name loads. An unmatched
name is not an error condition — nothing logs, nothing throws, the patch simply never
runs. There is no runtime signal to test against, so verification has to be static.

**The identity change is confirmed at the source.** PT `_meta.lua`, v3.7 → v3.8.3:

```diff
-    -- name = "projecttitle",
-    name = "coverbrowser",
+    -- name field deprecated. plugin names are now created from the folder name minus '.koplugin'
```

`plugins/manifest.yml` already sets `install_dir: projecttitle.koplugin`, so the derived
name is `projecttitle` with no install-side change needed.

**PT ships a compatibility shim that does not help us.** `covermenu.lua` v3.8.3 adds
`self.coverbrowser = self.projecttitle` in `CoverMenu:setupLayout()`. Field access via
`FileManager.coverbrowser` still resolves. Registration dispatch does not — it keys on
the plugin name, not on that field. Any reasoning that "PT still answers to
coverbrowser" is true for the field and false for the thing that is broken.

**Upstream drift is uneven.** v3.7 → v3.8.3 is +666/-133. Per-file, against the symbols
our patches hook:

```shell
mosaicmenu.lua        MosaicMenuItem:paintTo body rewritten (@@ -935,29 +934,30 @@)
                      MosaicMenuItem:update touched (@@ -801 +801 @@)
ptutil.lua            +224 lines; line helpers intact at 542-545
                      new: formatSeries, formatSeriesIndex, zeroPadIndex,
                           getPageCount, swapAuthor, getSeries
                      all functions made non-local (was: many local)
bookinfomanager.lua   DB schema line changed (@@ -72 +72 @@)
                      +70 lines inserted before getBookInfo (@@ -341,0 +342,70 @@)
                      getBookInfo itself changed (@@ -343,0 +414,6 @@, @@ -346 +422 @@)
covermenu.lua         setupLayout changed; menuInit unchanged
listmenu.lua          unchanged
```

**Both reference checkouts predate the target.** `_ref/ProjectTitle` at `ac3f010`
(2026-05-26, pre-3.8), `_ref/koreader` at `9c5e596` (2026-06-02). Nothing about v3.8.3
can be verified until these move.

## Goals / Non-Goals

**Goals:**

- Every PT patch fires again on the pinned target, verified statically.
- Compatibility state per patch is recorded, not assumed — including "verified at symbol
  level" versus "verified against changed code".
- The audit that produced this change gives a real answer next time: no patch reports as
  compatible merely because it declares nothing.

**Non-Goals:**

- Supporting KOReader 2026.03 and 2026.07 from one patch set. Dual-targeting would mean
  registering under both names and branching on `Version:getNormalizedCurrentVersion()`
  in 13 files, to keep a release the user is leaving behind. Single target; the previous
  release stays reachable by git tag.
- Adopting v3.8's new affordances. `ptutil` functions becoming non-local invites
  simplifying existing workarounds, and 3.8 added sort methods our patches could hook.
  Both are improvements, neither is this change.
- ~~Bumping bookends past `v5.20.0`~~ — amended, see `proposal.md`. Pulled into this
  change by request and pinned to `v5.22.0` (`43bbcfa`), verified separately.

## Decisions

### Pin format: prose header plus a `safe_version` literal

Each patch gets both a human-readable `KOReader 2026.07.1 (safe_version 202607010000)`
line in its header block and a `local safe_version = 202607010000` literal.

The numeric value is not arbitrary. KOReader's `Version:getNormalizedVersion` computes
`((year * 100 + month) * 1000000) + point * 10000 + revision`, so `v2026.07.1` is
`(2026*100+7)*1000000 + 1*10000` = `202607010000`. The existing pin in
`2-pt-footer-history-recent.lua` (`202603000000` for 2026.03) follows the same formula,
so this extends a convention already in the repo rather than inventing one.

Alternatives: prose only, which is what 2 of the 3 currently-pinned patches do and what
made the audit regex-dependent and the other 16 patches invisible; or a manifest-side
patch → version table, rejected because a patch is copied to the device as a single file
and the pin has to travel with it.

Note the literal is declared, not enforced. Making it a hard runtime gate that refuses to
apply the patch on a mismatched KOReader is a larger behavioral change and is not part of
this design; the literal exists so tooling and humans can read the intent exactly.

### Target: KOReader `2026.07.1`, in KOReader's tag notation

The manifest records `2026.07.1` / codename `Sailing Walrus`, matching the release tag
`v2026.07.1`. PT's release notes write this release as `2026.07.01` and also claim
support for `2026.07.02`; the latter exists as tag `v2026.07.2` with no GitHub release
attached. Because manifest values map to downloadable releases, the release-backed tag
wins, and PT's differing notation is recorded in `docs/installation.md` so the mismatch
does not read as an error later.

Alternatives: `2026.07.2` has no release asset to point install docs at; the `2026.07`
base skips two rounds of upstream fixes for no gain, since PT v3.8.3 covers all three.

### Fix registration mechanically, verify separately

The 13 one-line edits are a single mechanical pass, independent of any verification. They
are safe in isolation: on the pinned target the old key matches nothing, so changing it
cannot regress behavior that currently works. Verification is then a distinct activity
per patch, and a patch can be registration-correct while still unverified — which is
exactly the state the spec requires us to be able to express.

Alternative considered and rejected: fix and verify patch-by-patch as one pass. It
couples a 13-file mechanical edit to an open-ended investigation, and if Tier 1 turns out
deep, the mechanical part is stuck behind it.

### Verification tiers drive the work order

Ordered by evidence needed, not by file:

- **Tier 3** — `2-pt-mm-noborders` (ptutil line helpers confirmed present at v3.8.3
  lines 542-545), `2-pt-footer-history-recent` (hooks `CoverMenu.menuInit`, unchanged).
  Registration fix, then confirm the symbol still exists. Done.
- **Tier 2** — the 8 `MosaicMenuItem:paintTo` wrappers plus the series and pages patches.
  `paintTo` was rewritten; these wrap rather than replace, so read the new body and
  confirm the wrap point and paint order still hold. The series patches additionally need
  checking against upstream's new `formatSeries` / `formatSeriesIndex` / `zeroPadIndex`,
  because 3.8 removed upstream's own series-formatting preferences — our patches may now
  duplicate or fight behavior that moved into core.
- **Tier 1** — `2-pt-perf` and `2-rounded-folder-covers`, which wrap the whole
  `BookInfoManager` cache and DB layer against a changed schema line, ~70 new lines
  before `getBookInfo`, and a changed `getBookInfo`. Read the v3.8.3 diff in full before
  touching either. Genuine possibility that some of what `2-pt-perf` adds landed upstream
  in those +70 lines, in which case the right outcome is deleting our version, not
  porting it.

### Refresh `_ref/` before verifying, not after

`_ref/ProjectTitle` moves to tag `2026.07-v3.8.3` and `_ref/koreader` to `v2026.07.1`
as the first implementation step. Every verification claim in this change is a claim
about code in those checkouts; making them accurate first is what separates verification
from assertion. `scripts/setup-refs.sh` already exists for this.

## Risks / Trade-offs

**Tier 1 scope is unknown until the diff is read** → It is bounded to two files and the
work is a read before it is an edit. If `2-pt-perf` turns out to need a rewrite rather
than a repair, that is a finding to report and re-scope on, not something to push through
silently. The registration pass and Tiers 2-3 do not depend on its outcome.

**A patch can be registration-correct and still silently wrong** → Fixing the key makes
patches fire again, which converts silent inactivity into visible behavior — possibly
visibly broken behavior against changed upstream code. This is why Tier 2 reads the new
`paintTo` body instead of assuming a wrapper survives, and why the spec forbids recording
compatibility on the strength of the registration fix alone.

**Verification is static only** → No emulator or device in this repo, so "verified"
means the hooked symbol exists and the surrounding code was read, never that it was run.
The pinned bundle still wants a manual smoke test on device before release. Stated
plainly here so "verified" is not read as stronger than it is.

**Docs drift is the failure that already happened** → 16 of 19 patches carrying no pin is
why two stale releases went unnoticed. Sweeping every version reference in one pass and
grepping for survivors is the mitigation; `patches/README.md` is generated, so
regenerating it via the `patch-changelog` skill beats hand-editing.

**Upstream may move mid-change** → PT released 3.8, 3.8.1, 3.8.2, 3.8.3 within about six
weeks. Pin to the tag, record the tag in the manifest, and re-audit on the next bump
rather than tracking a moving branch.

## Migration Plan

1. Refresh `_ref/` to PT `2026.07-v3.8.3` and KOReader `v2026.07.1`.
2. Bump `plugins/manifest.yml` to KOReader `2026.07.1` / Sailing Walrus / PT
   `2026.07-v3.8.3`.
3. Mechanical registration pass across the 13 patches.
4. Add pins to all 19 patches.
5. Verify Tier 3, then Tier 2, then Tier 1; repair what broke.
6. Sweep docs, regenerate `patches/README.md`.
7. Manual smoke test on device before tagging a release.

Rollback: the previous target stays intact at the last release tag, so a user on
KOReader 2026.03 installs the prior bundle. There is no in-place downgrade path and none
is needed — patches are files copied to a device, and the KOReader version is the thing
that actually has to match.

## Open Questions

- Whether any of `2-pt-perf`'s caching was absorbed into upstream's +70 lines around
  `getBookInfo`. Answerable by reading the refreshed ref in step 1; deferrable because it
  changes the content of one Tier 1 task, not the specs or the approach.
- Whether the series patches now conflict with upstream's own series formatting, given
  3.8 removed its formatting preferences and moved behavior into `ptutil`. Same
  reasoning: a Tier 2 finding, not a design fork.
