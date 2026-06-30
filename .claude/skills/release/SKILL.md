---
name: release
description: >-
  Cut a new versioned release of this repo by pushing a `v*` tag, then
  curating and publishing the draft release that the "Release bundle"
  workflow creates. Use when the user asks to "create a release", "cut a
  release", "release a new version", "tag a release", "publish a
  release", or asks to make a new release tag after merging a PR.
disable-model-invocation: true
---

# Release

Cut a release for `koreader-configs`. A release is built and published by
the `release.yml` workflow, not by hand: pushing a `v*` tag triggers the
**Release bundle** workflow, which creates a DRAFT GitHub release authored
by `github-actions[bot]` and uploads the bundle zip + checksum. The
release is then curated and published by editing that draft.

## Critical rule

NEVER run `gh release create` in this repo. Creating the release manually
makes the human the author and reduces the workflow to merely attaching
assets. All releases v0.2.0+ are authored by `github-actions[bot]`, and a
manual create had to be redone for v0.5.0. Editing and publishing a
bot-created draft preserves the bot as author.

## Procedure

### 1. Pre-flight

1. `git fetch --tags --quiet` and confirm `origin/main` is the intended
   release point. Tag the exact `origin/main` HEAD commit; do not require
   a local `main` checkout (local branches are often stale).
2. Find the latest tag: `git tag --sort=-v:refname | head -1`.
3. List what is new since it: `git log --oneline <latest-tag>..origin/main`.
4. Decide the next version (semver, `vX.Y.Z`). When the bump size is
   ambiguous, ask the user: patch (`v0.5.1`) for a single small change
   like a plugin version bump, minor (`v0.6.0`) for features or a batch
   of changes. Do not guess silently.

### 2. Create and push the tag

```bash
git tag -a vX.Y.Z <origin/main-HEAD-commit> -m "vX.Y.Z

- <one line per notable change, referencing PR #N>"
git push origin vX.Y.Z
```

The tag push triggers the workflow. Confirm it started:

```bash
gh run list --workflow=release.yml --limit 3
```

### 3. Wait for the draft

The workflow builds the bundle and creates a DRAFT release under
`GITHUB_TOKEN`. Wait for the run to finish (`gh run watch <id>` or poll
`gh run list`), then confirm the draft exists and is bot-authored:

```bash
gh release view vX.Y.Z   # author should be github-actions[bot]
```

### 4. Curate release notes

Write notes following the established format (see `v0.4.0` for the
reference shape):

- `## H2` sections grouped by theme (e.g. new features, Documentation,
  Patches). Append `(new)` to section titles for net-new capabilities.
- Link to docs and files with absolute `github.com/.../blob/main/...`
  URLs so links work from the Releases page.
- End with a **Pinned plugin versions** subsection listing each plugin
  and its tag, sourced from `plugins/manifest.yml` (`targets[].plugins[]`,
  `repo` + `tag`).

Read `plugins/manifest.yml` for the current pins rather than copying from
a previous release.

### 5. Publish the draft

Publishing is an outward-facing action. Confirm the curated notes with
the user, then publish by EDITING the draft (never create):

```bash
gh release edit vX.Y.Z --notes-file <notes.md> --title vX.Y.Z \
  --draft=false --latest
```

## Notes

- Tag format is `vMAJOR.MINOR.PATCH`. The workflow also accepts
  `workflow_dispatch` with a tag input for artifact-only rebuilds (mode
  `artifact`, no release), but the normal release path is the tag push.
- If the workflow fails, fix forward and re-push a new tag rather than
  hand-creating a release.
  