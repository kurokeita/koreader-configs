---
name: koreader-and-plugins-version-bump
description: >-
  Audit every userpatch in `patches/` for its pinned KOReader
  `safe_version`, and audit the bundled plugin tags in
  `plugins/manifest.yml` against upstream releases. Use when KOReader
  or a bundled plugin publishes a new release, when the user mentions
  "bump KOReader version", "bump Bookends", "bump Project: Title",
  "update the bundled plugins", "audit patches", or asks which patches
  or plugin pins still target an old version.
disable-model-invocation: true
---

# KOReader and Plugins Version Bump

Two audits in one skill:

- **Patches** (report only): surfaces the KOReader version each
  userpatch is pinned to, so the user knows what to re-validate.
- **Plugins** (report, then edit on request): compares the tags pinned
  in `plugins/manifest.yml` against upstream releases, and updates the
  manifest plus the hand-maintained doc tables once the user picks a
  tag.

## When to run

The user invokes this manually after a new KOReader or plugin release.
Optional argument: a target KOReader version (e.g. `202604000000` or
`2026.04`). Without an argument, output the current pins with no
comparison.

Run both sections unless the user names one.

## Part 1: Patch audit

1. List every `.lua` file directly inside `patches/` (skip `.disabled`
   files unless the user asks for them).
2. For each file, extract:
   - **Pinned version**: the first match of
     `safe_version%s*[=]?%s*(%d+)` in the file body (the
     `userpatch.registerPatchPluginFunc` patches reuse the host
     plugin's `safe_version` literal). If absent, look for a
     `KOReader <version>` line in the header comment.
   - **Header summary**: the first non-blank line of the leading
     `--[[ ... --]]` block.
   - **Last modified**: `git log -1 --format='%ai %h' -- <path>`.
3. Print a table sorted by pinned version ascending:

   ```text
   patches/<file>.lua
     pinned: 202603000000   (KOReader 2026.03)
     summary: <one-line header>
     last touched: 2026-05-09  a2cb017
   ```

4. If a target version is provided:
   - Mark each patch as **OK** (pinned >= target), **STALE** (pinned
     < target), or **UNKNOWN** (no pin found).
   - Output a final summary count.

## Part 2: Bundled plugin audit

`plugins/manifest.yml` is the single source of truth for which plugin
tags ship in a release bundle. Everything else (CI, `setup-refs.sh`,
the doc tables) either reads it or copies from it by hand.

1. Read the current pins from the first manifest target:

   ```sh
   yq '.targets[0].koreader' plugins/manifest.yml
   yq '.targets[0].plugins[] | [.repo, .tag, .install_dir] | @tsv' plugins/manifest.yml
   ```

2. For each `repo`, list recent upstream tags:

   ```sh
   gh api "repos/<repo>/releases?per_page=10" --jq '.[] | "\(.tag_name)\t\(.published_at)"'
   ```

3. Pick the candidate tag per plugin, respecting each project's tag
   convention:
   - **Project: Title** tags are KOReader-version prefixed
     (`2026.07-v3.8.3`). Match on the `YYYY.MM` part only; upstream is
     loose about the patch segment and has shipped both `2026.07-` and
     `2026.07.01-` prefixes for the same KOReader 2026.07.1 target.
     Pick the newest tag in the matching `YYYY.MM` family, not the
     newest tag overall. If nothing matches, say so instead of
     guessing.
   - **Bookends** tags are plain semver (`v5.22.0`). Newest wins.

4. Print pinned vs candidate:

   ```text
   AndyHazz/bookends.koplugin
     pinned:    v5.22.0
     candidate: v5.23.0   (published 2026-09-01)
     status:    BEHIND
   ```

   Status is **CURRENT**, **BEHIND**, or **UNKNOWN** (no matching tag
   for the target KOReader version).

5. Stop and let the user choose which pins to move. Do not bump on
   your own.

## Part 3: Applying a plugin bump

Only after the user names the tags:

1. Edit the `tag` field in `plugins/manifest.yml`. Change nothing else
   there; `repo` and `install_dir` are stable, and the `koreader` /
   `codename` fields belong to a KOReader target bump, which is a
   separate task.
2. Sync the two hand-maintained copies of the same information:
   - `docs/plugins.md`, the "Version compatibility" table.
   - `docs/installation.md`, the pinned-tag table and the KOReader
     version in its header row.
3. Validate the manifest still parses:

   ```sh
   .github/scripts/parse-manifest.sh plugins/manifest.yml
   bash .github/scripts/tests/parse-manifest.test.sh
   ```

4. Refresh the local reference trees so patch review runs against the
   new source:

   ```sh
   scripts/setup-refs.sh
   ```

5. Re-run Part 1 against the refreshed trees, and report which patches
   wrap functions in the bumped plugin. Those are the ones that need
   hands-on re-validation before the bump ships.

## Notes

- Many patches in this repo do not pin a version explicitly — they
  rely on monkey-patching whatever module is loaded. Treat absence of
  a pin as **UNKNOWN**, not **OK**.
- Do not modify any patch automatically. Patch pins and the
  "Written against:" lines in `docs/patches/*.md` change only after a
  human re-validates the patch against the new source.
- The manifest is the only file this skill edits, plus the two doc
  tables that mirror it, and only after the user picks the tags.
- Leave `.github/scripts/tests/fixtures/*.yml` alone. Those pin old
  versions on purpose so the manifest parser tests stay meaningful.
