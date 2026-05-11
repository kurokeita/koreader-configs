# Release workflow design

Date: 2026-05-11
Branch: `ci/release-workflow`

## Goal

When a release is published in this repo, automatically produce a zip
bundle that a user can download and extract into their KOReader data
directory to get everything in `koreader-configs` (icons, patches) plus
the pinned upstream plugins (`ProjectTitle`, `bookends`) in one step.

## Repo additions

Three new files:

- `plugins/manifest.yml` — pinned plugin versions, grouped under a
  KOReader target. Source of truth for both the workflow and humans.
- `.github/workflows/release.yml` — the workflow described below.
- `INSTALL.md` — short install instructions. Copied into each zip as
  `INSTALL.txt`.

### `plugins/manifest.yml` schema

```yaml
targets:
  - koreader: "2026.03"
    codename: Snowflake
    plugins:
      - repo: joshuacant/ProjectTitle
        tag: v1.4.2
        install_dir: projecttitle.koplugin
      - repo: AndyHazz/bookends.koplugin
        tag: v0.9.1
        install_dir: bookends.koplugin
```

Field contract:

- `targets[]` — one entry per supported KOReader release. Normally one
  entry (the current KOReader). Matrix-built so adding a target is just
  adding a list item.
- `targets[].koreader` — KOReader version string, used in filenames and
  `VERSIONS.txt`. Quoted to preserve leading zeros.
- `targets[].codename` — human-readable KOReader codename (e.g.
  `Snowflake`). Used in filenames and `INSTALL.txt`.
- `targets[].plugins[].repo` — `owner/name` GitHub slug.
- `targets[].plugins[].tag` — exact upstream release tag to bundle.
- `targets[].plugins[].install_dir` — folder name under `plugins/` in
  the produced zip. Lets the workflow normalize a differently-named
  upstream folder.

## Triggers

```yaml
on:
  release:
    types: [published]
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag to build (defaults to latest)"
        required: false
```

Concurrency keyed on the resolved tag to avoid double-runs when
publishing a release that also pushed a tag:

```yaml
concurrency:
  group: release-${{ github.event.release.tag_name || github.ref_name || inputs.tag }}
  cancel-in-progress: false
```

Permissions: `contents: write` (release asset upload). Nothing else.

## Jobs

### `prepare`

Single-step job that:

1. Checks out the repo at the resolved tag.
2. Parses `plugins/manifest.yml` with `yq` (preinstalled on
   `ubuntu-latest`).
3. Validates every target has non-empty `koreader`, `codename`, and at
   least one plugin with non-empty `repo`, `tag`, `install_dir`.
4. Emits the targets list as a JSON step output.
5. Emits the resolved tag and upload-mode (`release` vs `artifact`) as
   outputs.

### `build-release`

Depends on `prepare`. Strategy:

```yaml
strategy:
  fail-fast: false
  matrix:
    target: ${{ fromJSON(needs.prepare.outputs.targets) }}
```

Each matrix leg builds one bundle for one KOReader target.

Steps per leg:

1. **Checkout** repo at the resolved tag.
2. **Stage tree:**

   ```bash
   staging/koreader-configs-<tag>-koreader<KO_VER>-<CODENAME>/
   ├── INSTALL.txt
   ├── VERSIONS.txt
   ├── icons/
   ├── patches/
   └── plugins/
   ```

   - `icons/` and `patches/` copied wholesale from the checkout.
   - `plugins/README.md` (doc-only) is excluded; only fetched plugin
     folders end up in `plugins/`.
3. **Fetch plugins** — for each plugin in `matrix.target.plugins`:
   1. `gh release download "$tag" --repo "$repo" --pattern '*.zip' --dir "$tmp"`
      — fails loudly if no `.zip` asset exists.
   2. `unzip` into a fresh temp dir. Expected shape: a single
      `<name>.koplugin/` folder at the top of the extracted tree.
   3. Locate the single `*.koplugin/` directory. Fail if zero or more
      than one are found.
   4. If its name differs from `install_dir`, rename it (defensive).
   5. `mv` it into the staged `plugins/` directory.
4. **Generate `VERSIONS.txt`** — first line is the koreader-configs
   release tag and the target KOReader version (e.g.
   `koreader-configs v0.3.0 for KOReader 2026.03 (Snowflake)`).
   Following lines are one pin per plugin: `<repo>@<tag>`.
5. **Copy `INSTALL.md`** to `staging/<bundle>/INSTALL.txt`. The install
   text references the target KOReader version copied from the matrix
   leg.
6. **Zip:**

   ```bash
   cd staging && zip -r ../koreader-configs-<tag>-koreader<KO_VER>-<CODENAME>.zip koreader-configs-<tag>-koreader<KO_VER>-<CODENAME>
   ```

7. **Checksum:** `shasum -a 256 <zip> > <zip>.sha256`. Standard
   `<hash>  <filename>` format, verifiable with `shasum -c <file>.sha256`.
8. **Upload:**
   - If triggered by `release: published`: a release already exists.
     Run `gh release upload "$TAG" <zip> <zip>.sha256 --clobber`.
   - If triggered by `push` of a `v*` tag: a release may or may not
     exist. Run `gh release create "$TAG" --generate-notes || true`
     (idempotent — succeeds if it didn't exist, falls through if it
     did), then `gh release upload "$TAG" <zip> <zip>.sha256 --clobber`.
   - If `workflow_dispatch`: `actions/upload-artifact@v4` with both
     files under a per-target artifact name. No release is touched.

   When both `release: published` and `push` of the same tag fire
   together (the common case of publishing through the Releases UI),
   the concurrency group serializes them and `--clobber` makes the
   later upload idempotent.

Auth for `gh` calls uses the workflow's `GITHUB_TOKEN`. Sufficient for
public repo reads (avoids the unauthenticated 60/hr rate limit) and for
release uploads to this repo.

## Bundle layout (what the user gets)

After extracting one of the zips at the chosen location, the user has:

```bash
koreader-configs-v0.3.0-koreader2026.03-Snowflake/
├── INSTALL.txt
├── VERSIONS.txt
├── icons/
├── patches/
└── plugins/
    ├── projecttitle.koplugin/
    └── bookends.koplugin/
```

`INSTALL.txt` instructs the user to move the contents of `icons/`,
`patches/`, and `plugins/` into the corresponding folders inside their
KOReader data directory (the wrapped top-level folder prevents
accidental clobber on extract).

## Failure modes

- Missing manifest fields → `prepare` job fails before the matrix runs.
- Upstream release missing or has no `.zip` asset → `gh release
  download` exits non-zero; failed leg names the plugin in the log.
- Extracted upstream zip has zero or multiple `*.koplugin/` folders →
  fail with a clear message (unexpected upstream shape).
- Re-run against the same tag → `--clobber` replaces the assets.
- `workflow_dispatch` with no tag input and no tags in repo → fail
  early in `prepare`.

`fail-fast: false` ensures one broken target does not cancel the
others.

## Out of scope

- Cryptographic signing of the bundle (only SHA-256 checksums).
- Automated bumping of `manifest.yml` (manual edit, then cut a release).
- Smoke-testing the bundle against a real KOReader build in CI.
- Per-architecture or per-device variants.

## Acceptance criteria

1. Publishing a GitHub Release in this repo produces, per target in
   `plugins/manifest.yml`, one zip asset and one matching `.sha256`
   asset attached to the release.
2. Pushing a tag matching `v*` produces the same outputs without
   needing the Release UI.
3. `workflow_dispatch` runs end-to-end and produces the same files as
   workflow artifacts (no release touched).
4. The zip extracts to a single top-level
   `koreader-configs-<tag>-koreader<KO_VER>-<CODENAME>/` directory
   containing `icons/`, `patches/`, `plugins/<...>.koplugin/`,
   `INSTALL.txt`, and `VERSIONS.txt`.
5. `shasum -c <zip>.sha256` succeeds against the published zip.
6. Re-running the workflow against the same tag overwrites the
   existing assets without error.
