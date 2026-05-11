# Release Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a GitHub Actions workflow that, on release, downloads pinned upstream plugins and packages them with this repo's `icons/` and `patches/` into a single ready-to-extract zip per KOReader target.

**Architecture:** A manifest (`plugins/manifest.yml`) is the source of truth for pinned plugin versions per KOReader target. The workflow has a `prepare` job that parses + validates the manifest and emits a JSON matrix; a `build-release` job that runs once per target, fetches each plugin's zip from its GitHub release, stages the bundle (icons/patches/plugins/INSTALL/VERSIONS), zips it, generates a SHA-256 checksum, and uploads both as release assets (or as workflow artifacts for `workflow_dispatch`). All non-trivial logic lives in `.github/scripts/*.sh` so it is testable and reviewable.

**Tech Stack:** GitHub Actions, bash, `gh` CLI, `yq`, `unzip`, `zip`, `shasum`, `actionlint` (lint), `shellcheck` (lint).

**Reference:** Approved design spec at `docs/superpowers/specs/2026-05-11-release-workflow-design.md`.

---

## File Structure

Files to create:

| Path | Purpose |
| --- | --- |
| `INSTALL.md` | Repo-root install instructions; copied into each zip as `INSTALL.txt`. |
| `plugins/manifest.yml` | Pinned plugin versions per KOReader target. |
| `.github/scripts/parse-manifest.sh` | Validates `plugins/manifest.yml` and emits a compact JSON targets array on stdout. |
| `.github/scripts/build-bundle.sh` | Given a target JSON and tag, fetches plugins, stages the bundle, zips, and produces a `.sha256`. |
| `.github/scripts/tests/parse-manifest.test.sh` | Hand-rolled bash tests for `parse-manifest.sh`. |
| `.github/scripts/tests/fixtures/manifest-valid.yml` | Test fixture. |
| `.github/scripts/tests/fixtures/manifest-missing-codename.yml` | Test fixture (invalid). |
| `.github/scripts/tests/fixtures/manifest-no-plugins.yml` | Test fixture (invalid). |
| `.github/workflows/release.yml` | The workflow itself. |

No existing files are modified. `plugins/README.md` stays as-is in the repo but is excluded from the bundle.

Decomposition rationale:

- `parse-manifest.sh` is small, pure (reads file → stdout), and easy to test locally. It is the most error-prone part because YAML schema mistakes propagate everywhere; unit tests catch that.
- `build-bundle.sh` is a top-to-bottom script that orchestrates network calls, filesystem ops, and zipping. Unit-testing it would require heavy mocking of `gh` and the filesystem. It is validated by `shellcheck` and by the end-to-end smoke test in Task 6 instead.
- `release.yml` is the orchestrator: trigger configuration, job graph, matrix, upload mode. Validated by `actionlint`.

---

## Task 1: Install instructions document

**Files:**

- Create: `INSTALL.md`

- [ ] **Step 1: Write `INSTALL.md`**

```markdown
# Install

This bundle contains everything in `koreader-configs` (custom icons,
userpatches) plus the pinned upstream plugins (`ProjectTitle`,
`bookends`) built for a specific KOReader version. See `VERSIONS.txt`
inside this bundle for the exact plugin and KOReader versions it
targets.

## Steps

1. Locate your KOReader data directory:
   - **Kobo / Kindle / reMarkable**: the `koreader/` folder on the
     device, accessible over USB.
   - **Android**: `Internal storage/koreader/` (path may vary by
     install method).
   - **Desktop**: the directory you launch KOReader from.
2. Copy the contents of each of the following folders from this
   bundle into the corresponding folder inside your KOReader data
   directory, overwriting any existing files with the same name:
   - `patches/` → `koreader/patches/`
   - `plugins/` → `koreader/plugins/` (each `*.koplugin/` folder goes
     in whole)
   - `icons/` → `koreader/resources/icons/mdlight/` (or whichever icon
     set your theme uses)
3. Restart KOReader.

If you are upgrading and want to revert, delete the files you copied
in step 2 (the bundle's `VERSIONS.txt` lists every plugin folder it
adds).
```

- [ ] **Step 2: Verify the file exists**

Run: `wc -l INSTALL.md`
Expected: a non-zero line count.

- [ ] **Step 3: Commit**

```bash
git add INSTALL.md
git commit -m "docs: add install instructions bundled with releases"
```

---

## Task 2: Plugin manifest

**Files:**

- Create: `plugins/manifest.yml`

- [ ] **Step 1: Discover the current latest tag for each upstream plugin**

Run:

```bash
gh release view --repo joshuacant/ProjectTitle --json tagName -q .tagName
gh release view --repo AndyHazz/bookends.koplugin --json tagName -q .tagName
```

Record the two tag strings. Use them verbatim in step 2.

- [ ] **Step 2: Write `plugins/manifest.yml`**

Use the tag strings discovered in step 1 in place of `<PROJECTTITLE_TAG>` and `<BOOKENDS_TAG>` below. Keep `koreader: "2026.03"` quoted so YAML preserves the literal string.

```yaml
targets:
  - koreader: "2026.03"
    codename: Snowflake
    plugins:
      - repo: joshuacant/ProjectTitle
        tag: <PROJECTTITLE_TAG>
        install_dir: projecttitle.koplugin
      - repo: AndyHazz/bookends.koplugin
        tag: <BOOKENDS_TAG>
        install_dir: bookends.koplugin
```

- [ ] **Step 3: Validate YAML syntax**

Run: `yq '.' plugins/manifest.yml`
Expected: the file is echoed back as parsed YAML (no parse error).

- [ ] **Step 4: Commit**

```bash
git add plugins/manifest.yml
git commit -m "feat: pin upstream plugin versions per KOReader target"
```

---

## Task 3: `parse-manifest.sh` (TDD)

This task uses TDD: tests first, watch them fail, implement, watch them pass.

**Files:**

- Create: `.github/scripts/parse-manifest.sh`
- Create: `.github/scripts/tests/parse-manifest.test.sh`
- Create: `.github/scripts/tests/fixtures/manifest-valid.yml`
- Create: `.github/scripts/tests/fixtures/manifest-missing-codename.yml`
- Create: `.github/scripts/tests/fixtures/manifest-no-plugins.yml`

The script contract:

- Argument: path to a manifest file.
- On success: prints a single compact JSON line representing the `targets` array (suitable for `fromJSON` in a GitHub Actions matrix) and exits 0.
- On failure: prints a human-readable reason to stderr and exits non-zero.
- Validation: each target must have non-empty `koreader`, `codename`, and at least one plugin with non-empty `repo`, `tag`, `install_dir`.

- [ ] **Step 1: Create the test fixtures**

Create `.github/scripts/tests/fixtures/manifest-valid.yml`:

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

Create `.github/scripts/tests/fixtures/manifest-missing-codename.yml`:

```yaml
targets:
  - koreader: "2026.03"
    plugins:
      - repo: joshuacant/ProjectTitle
        tag: v1.4.2
        install_dir: projecttitle.koplugin
```

Create `.github/scripts/tests/fixtures/manifest-no-plugins.yml`:

```yaml
targets:
  - koreader: "2026.03"
    codename: Snowflake
    plugins: []
```

- [ ] **Step 2: Write the failing test**

Create `.github/scripts/tests/parse-manifest.test.sh`:

```bash
#!/usr/bin/env bash
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../parse-manifest.sh"
FIXTURES="$HERE/fixtures"
PASS=0
FAIL=0

assert() {
  local name="$1"
  shift
  if "$@"; then
    echo "  ok  - $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL - $name"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1: valid manifest produces JSON containing both plugins
test_valid_outputs_json() {
  local out
  out="$(bash "$SCRIPT" "$FIXTURES/manifest-valid.yml")"
  echo "$out" | grep -q '"koreader":"2026.03"' \
    && echo "$out" | grep -q '"codename":"Snowflake"' \
    && echo "$out" | grep -q '"repo":"joshuacant/ProjectTitle"' \
    && echo "$out" | grep -q '"repo":"AndyHazz/bookends.koplugin"'
}

# Test 2: valid manifest exits 0
test_valid_exit_zero() {
  bash "$SCRIPT" "$FIXTURES/manifest-valid.yml" >/dev/null
}

# Test 3: missing codename exits non-zero
test_missing_codename_fails() {
  ! bash "$SCRIPT" "$FIXTURES/manifest-missing-codename.yml" >/dev/null 2>&1
}

# Test 4: missing codename mentions "codename" in stderr
test_missing_codename_message() {
  bash "$SCRIPT" "$FIXTURES/manifest-missing-codename.yml" 2>&1 >/dev/null \
    | grep -qi 'codename'
}

# Test 5: empty plugins list exits non-zero
test_no_plugins_fails() {
  ! bash "$SCRIPT" "$FIXTURES/manifest-no-plugins.yml" >/dev/null 2>&1
}

# Test 6: nonexistent file exits non-zero
test_missing_file_fails() {
  ! bash "$SCRIPT" "$FIXTURES/does-not-exist.yml" >/dev/null 2>&1
}

assert "valid manifest produces expected JSON" test_valid_outputs_json
assert "valid manifest exits 0" test_valid_exit_zero
assert "missing codename fails" test_missing_codename_fails
assert "missing codename message mentions field" test_missing_codename_message
assert "no plugins fails" test_no_plugins_fails
assert "missing file fails" test_missing_file_fails

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 3: Make the test script executable and run it to verify it fails**

```bash
chmod +x .github/scripts/tests/parse-manifest.test.sh
bash .github/scripts/tests/parse-manifest.test.sh
```

Expected: all tests FAIL (script does not exist yet). Exit code non-zero.

- [ ] **Step 4: Implement `parse-manifest.sh`**

Create `.github/scripts/parse-manifest.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <path-to-manifest.yml>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
MANIFEST="$1"

if [ ! -f "$MANIFEST" ]; then
  echo "error: manifest not found: $MANIFEST" >&2
  exit 1
fi

# Require yq.
if ! command -v yq >/dev/null 2>&1; then
  echo "error: yq is required but not installed" >&2
  exit 1
fi

# Validate top-level shape: targets must be a non-empty list.
target_count="$(yq '.targets | length' "$MANIFEST")"
if [ "$target_count" = "null" ] || [ "$target_count" -lt 1 ]; then
  echo "error: manifest has no targets" >&2
  exit 1
fi

# Validate each target.
i=0
while [ "$i" -lt "$target_count" ]; do
  for field in koreader codename; do
    val="$(yq ".targets[$i].$field // \"\"" "$MANIFEST")"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      echo "error: target index $i missing required field: $field" >&2
      exit 1
    fi
  done

  plugin_count="$(yq ".targets[$i].plugins | length" "$MANIFEST")"
  if [ "$plugin_count" = "null" ] || [ "$plugin_count" -lt 1 ]; then
    echo "error: target index $i has no plugins" >&2
    exit 1
  fi

  j=0
  while [ "$j" -lt "$plugin_count" ]; do
    for field in repo tag install_dir; do
      val="$(yq ".targets[$i].plugins[$j].$field // \"\"" "$MANIFEST")"
      if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo "error: target $i plugin $j missing required field: $field" >&2
        exit 1
      fi
    done
    j=$((j + 1))
  done

  i=$((i + 1))
done

# Emit compact JSON of the targets array on stdout.
yq -o=json -I=0 '.targets' "$MANIFEST"
```

- [ ] **Step 5: Make the script executable**

```bash
chmod +x .github/scripts/parse-manifest.sh
```

- [ ] **Step 6: Run the test script and verify it passes**

```bash
bash .github/scripts/tests/parse-manifest.test.sh
```

Expected output ends with `6 passed, 0 failed` and exit code 0.

- [ ] **Step 7: Run `shellcheck` on the script**

```bash
shellcheck .github/scripts/parse-manifest.sh
```

Expected: no output (clean). If `shellcheck` is not installed, install via `brew install shellcheck` and re-run.

- [ ] **Step 8: Commit**

```bash
git add .github/scripts/parse-manifest.sh .github/scripts/tests/
git commit -m "feat(ci): parse and validate plugins/manifest.yml"
```

---

## Task 4: `build-bundle.sh`

This script is exercised end-to-end in Task 6 (the workflow smoke test) rather than unit-tested, because doing so locally would require mocking `gh release download`. It is validated statically with `shellcheck`.

**Files:**

- Create: `.github/scripts/build-bundle.sh`

The script contract:

- Required environment variables:
  - `TARGET_JSON` — JSON object for one target (one element of the array emitted by `parse-manifest.sh`).
  - `RELEASE_TAG` — the koreader-configs release tag being built (e.g. `v0.3.0`).
  - `REPO_ROOT` — absolute path to the repository checkout.
  - `OUT_DIR` — directory where the final `.zip` and `.sha256` are written.
- Effects: creates the staged bundle under `$OUT_DIR/staging/<bundle-name>/`, then a zip and matching `.sha256` directly under `$OUT_DIR`.
- Emits the bundle's base filename (without `.zip`) on stdout for the workflow to consume.
- Exits non-zero with a clear message on any failure.

- [ ] **Step 1: Implement `build-bundle.sh`**

Create `.github/scripts/build-bundle.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "error: required env var not set: $name" >&2
    exit 2
  fi
}

require_var TARGET_JSON
require_var RELEASE_TAG
require_var REPO_ROOT
require_var OUT_DIR

for cmd in gh jq unzip zip shasum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required tool not installed: $cmd" >&2
    exit 1
  fi
done

KO_VER="$(echo "$TARGET_JSON" | jq -r '.koreader')"
CODENAME="$(echo "$TARGET_JSON" | jq -r '.codename')"
PLUGIN_COUNT="$(echo "$TARGET_JSON" | jq '.plugins | length')"

if [ -z "$KO_VER" ] || [ "$KO_VER" = "null" ]; then
  echo "error: target JSON missing koreader" >&2
  exit 1
fi
if [ -z "$CODENAME" ] || [ "$CODENAME" = "null" ]; then
  echo "error: target JSON missing codename" >&2
  exit 1
fi

BUNDLE_NAME="koreader-configs-${RELEASE_TAG}-koreader${KO_VER}-${CODENAME}"
STAGING="$OUT_DIR/staging/$BUNDLE_NAME"

mkdir -p "$STAGING/plugins"
cp -R "$REPO_ROOT/icons" "$STAGING/icons"
cp -R "$REPO_ROOT/patches" "$STAGING/patches"

# Fetch each plugin.
i=0
while [ "$i" -lt "$PLUGIN_COUNT" ]; do
  repo="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].repo")"
  tag="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].tag")"
  install_dir="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].install_dir")"

  echo "==> fetching $repo @ $tag"
  tmp="$(mktemp -d)"
  gh release download "$tag" --repo "$repo" --pattern '*.zip' --dir "$tmp"

  zips=( "$tmp"/*.zip )
  if [ ${#zips[@]} -ne 1 ]; then
    echo "error: expected exactly one .zip in $repo@$tag, found ${#zips[@]}" >&2
    exit 1
  fi

  extract="$(mktemp -d)"
  unzip -q "${zips[0]}" -d "$extract"

  # Find the single *.koplugin directory at the top.
  shopt -s nullglob
  koplugins=( "$extract"/*.koplugin )
  shopt -u nullglob
  if [ ${#koplugins[@]} -ne 1 ]; then
    echo "error: expected one *.koplugin folder in $repo@$tag, found ${#koplugins[@]}" >&2
    exit 1
  fi

  src="${koplugins[0]}"
  if [ "$(basename "$src")" != "$install_dir" ]; then
    mv "$src" "$extract/$install_dir"
    src="$extract/$install_dir"
  fi

  mv "$src" "$STAGING/plugins/$install_dir"
  rm -rf "$tmp" "$extract"

  i=$((i + 1))
done

# VERSIONS.txt
{
  echo "koreader-configs $RELEASE_TAG for KOReader $KO_VER ($CODENAME)"
  i=0
  while [ "$i" -lt "$PLUGIN_COUNT" ]; do
    repo="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].repo")"
    tag="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].tag")"
    echo "${repo}@${tag}"
    i=$((i + 1))
  done
} > "$STAGING/VERSIONS.txt"

# INSTALL.txt
cp "$REPO_ROOT/INSTALL.md" "$STAGING/INSTALL.txt"

# Zip and checksum.
(
  cd "$OUT_DIR/staging"
  zip -qr "../$BUNDLE_NAME.zip" "$BUNDLE_NAME"
)
(
  cd "$OUT_DIR"
  shasum -a 256 "$BUNDLE_NAME.zip" > "$BUNDLE_NAME.zip.sha256"
)

echo "$BUNDLE_NAME"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x .github/scripts/build-bundle.sh
```

- [ ] **Step 3: Run `shellcheck`**

```bash
shellcheck .github/scripts/build-bundle.sh
```

Expected: no output. Fix anything it flags before moving on.

- [ ] **Step 4: Commit**

```bash
git add .github/scripts/build-bundle.sh
git commit -m "feat(ci): build per-target zip bundle with checksum"
```

---

## Task 5: The workflow

**Files:**

- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release bundle

on:
  release:
    types: [published]
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag to build (defaults to latest tag)"
        required: false

concurrency:
  group: release-${{ github.event.release.tag_name || github.ref_name || inputs.tag }}
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      targets: ${{ steps.parse.outputs.targets }}
      tag: ${{ steps.resolve.outputs.tag }}
      upload_mode: ${{ steps.resolve.outputs.upload_mode }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Resolve tag and upload mode
        id: resolve
        env:
          EVENT_NAME: ${{ github.event_name }}
          RELEASE_TAG: ${{ github.event.release.tag_name }}
          REF_NAME: ${{ github.ref_name }}
          DISPATCH_TAG: ${{ inputs.tag }}
        run: |
          set -euo pipefail
          case "$EVENT_NAME" in
            release)
              tag="$RELEASE_TAG"
              mode=release
              ;;
            push)
              tag="$REF_NAME"
              mode=release
              ;;
            workflow_dispatch)
              if [ -n "$DISPATCH_TAG" ]; then
                tag="$DISPATCH_TAG"
              else
                tag="$(git tag --sort=-v:refname | head -n1 || true)"
              fi
              mode=artifact
              ;;
            *)
              echo "unsupported event: $EVENT_NAME" >&2
              exit 1
              ;;
          esac
          if [ -z "$tag" ]; then
            echo "error: could not resolve a tag to build" >&2
            exit 1
          fi
          echo "tag=$tag" >> "$GITHUB_OUTPUT"
          echo "upload_mode=$mode" >> "$GITHUB_OUTPUT"

      - name: Parse manifest
        id: parse
        run: |
          set -euo pipefail
          targets="$(bash .github/scripts/parse-manifest.sh plugins/manifest.yml)"
          echo "targets=$targets" >> "$GITHUB_OUTPUT"

  build-release:
    needs: prepare
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        target: ${{ fromJSON(needs.prepare.outputs.targets) }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ needs.prepare.outputs.tag }}

      - name: Build bundle
        id: build
        env:
          TARGET_JSON: ${{ toJSON(matrix.target) }}
          RELEASE_TAG: ${{ needs.prepare.outputs.tag }}
          REPO_ROOT: ${{ github.workspace }}
          OUT_DIR: ${{ runner.temp }}/out
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          mkdir -p "$OUT_DIR"
          name="$(bash .github/scripts/build-bundle.sh)"
          echo "bundle_name=$name" >> "$GITHUB_OUTPUT"

      - name: Upload as release asset
        if: needs.prepare.outputs.upload_mode == 'release'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ needs.prepare.outputs.tag }}
          NAME: ${{ steps.build.outputs.bundle_name }}
          OUT_DIR: ${{ runner.temp }}/out
        run: |
          set -euo pipefail
          # Create the release if it doesn't exist (tag-push path).
          gh release create "$TAG" --generate-notes --title "$TAG" \
            --repo "$GITHUB_REPOSITORY" || true
          gh release upload "$TAG" \
            "$OUT_DIR/$NAME.zip" \
            "$OUT_DIR/$NAME.zip.sha256" \
            --repo "$GITHUB_REPOSITORY" --clobber

      - name: Upload as workflow artifact
        if: needs.prepare.outputs.upload_mode == 'artifact'
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.build.outputs.bundle_name }}
          path: |
            ${{ runner.temp }}/out/${{ steps.build.outputs.bundle_name }}.zip
            ${{ runner.temp }}/out/${{ steps.build.outputs.bundle_name }}.zip.sha256
          if-no-files-found: error
```

- [ ] **Step 2: Validate with `actionlint`**

```bash
actionlint .github/workflows/release.yml
```

Expected: no output. If `actionlint` is not installed, install via `brew install actionlint` and re-run. Fix anything it flags before moving on.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(ci): add release workflow that bundles patches/icons/plugins"
```

---

## Task 6: End-to-end smoke test via `workflow_dispatch`

The only realistic way to verify the workflow works against real upstream releases is to run it. `workflow_dispatch` is non-destructive (no release is created or modified — output is a workflow artifact).

**Files:** none.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin ci/release-workflow
```

- [ ] **Step 2: Trigger the workflow on this branch**

```bash
gh workflow run release.yml --ref ci/release-workflow
```

- [ ] **Step 3: Watch it to completion**

```bash
gh run watch
```

Expected: both `prepare` and `build-release` jobs end with green checkmarks. If anything fails, read the logs (`gh run view --log-failed`), fix the underlying issue, commit, push, and re-run from step 2.

- [ ] **Step 4: Download the produced artifact**

```bash
rm -rf /tmp/koreader-bundle-test
mkdir -p /tmp/koreader-bundle-test
cd /tmp/koreader-bundle-test
gh run download --name 'koreader-configs-*'
ls -la
```

Expected: a `.zip` and a `.zip.sha256` are present, with the name pattern `koreader-configs-<tag>-koreader2026.03-Snowflake`.

- [ ] **Step 5: Verify the checksum**

```bash
cd /tmp/koreader-bundle-test
shasum -c koreader-configs-*.zip.sha256
```

Expected: a single `OK` line for the zip.

- [ ] **Step 6: Verify the bundle structure**

```bash
cd /tmp/koreader-bundle-test
unzip -q koreader-configs-*.zip
ls koreader-configs-*-koreader2026.03-Snowflake/
cat koreader-configs-*-koreader2026.03-Snowflake/VERSIONS.txt
ls koreader-configs-*-koreader2026.03-Snowflake/plugins/
```

Expected:

- `ls` of the top dir shows `INSTALL.txt`, `VERSIONS.txt`, `icons/`, `patches/`, `plugins/`.
- `VERSIONS.txt` begins with a line like `koreader-configs <tag> for KOReader 2026.03 (Snowflake)` followed by one `<repo>@<tag>` line per plugin.
- `ls plugins/` shows `projecttitle.koplugin/` and `bookends.koplugin/`.

- [ ] **Step 7: Spot-check plugin contents**

```bash
cd /tmp/koreader-bundle-test
ls koreader-configs-*-koreader2026.03-Snowflake/plugins/projecttitle.koplugin/
ls koreader-configs-*-koreader2026.03-Snowflake/plugins/bookends.koplugin/
```

Expected: each plugin folder contains the upstream plugin source (typically `main.lua`, `_meta.lua`, etc.).

- [ ] **Step 8: If anything is wrong, iterate**

If structure, naming, or contents differ from the spec, return to the relevant task, fix, commit, push, and re-run from step 2 of this task. Do not proceed until all expected outcomes match.

- [ ] **Step 9: Final commit if any fixes were made**

If steps 1-8 required changes to fix issues, the fixes were already committed at the time. Otherwise, no new commit here.

---

## Acceptance verification

After Task 6 passes, verify the spec's six acceptance criteria are met:

1. ✅ AC1 (release: published produces zip + sha256 per target) — covered by the workflow logic and the artifact produced in Task 6 step 4. Will be exercised on the first real release; the workflow path is identical to `workflow_dispatch` for the build step.
2. ✅ AC2 (push tag v* produces same outputs) — same workflow handles it; the `gh release create ... || true` step ensures the release exists before upload.
3. ✅ AC3 (workflow_dispatch produces artifacts) — directly verified in Task 6.
4. ✅ AC4 (zip extracts to wrapped top-level folder with expected contents) — verified in Task 6 step 6.
5. ✅ AC5 (`shasum -c` succeeds) — verified in Task 6 step 5.
6. ✅ AC6 (re-runs overwrite) — covered by `--clobber` in the upload step. Not exercised by `workflow_dispatch` (uses artifacts, not releases), but the underlying `gh release upload --clobber` is the documented mechanism. Will be exercised on the first re-run of a real release.

AC1, AC2, AC6 are exercised the first time you cut a real release on `main` after merge. If any of them fail at that point, return to this plan, identify the root cause, and patch.
