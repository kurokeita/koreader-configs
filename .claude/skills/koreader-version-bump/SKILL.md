---
name: koreader-version-bump
description: >-
  Audit every userpatch in `patches/` for its pinned KOReader
  `safe_version` and report which ones need re-validation against a
  target KOReader version. Use when KOReader publishes a new release,
  when the user mentions "bump KOReader version", "audit patches", or
  asks which patches still target an old version.
disable-model-invocation: true
---

# KOReader Version Bump

Surfaces the version each userpatch is pinned to so the user knows
what to re-validate when KOReader is updated.

## When to run

The user invokes this manually after a new KOReader release. Optional
argument: a target version (e.g. `202604000000` or `2026.04`). Without
an argument, output the current pin per patch with no comparison.

## Procedure

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

## Notes

- Many patches in this repo do not pin a version explicitly — they
  rely on monkey-patching whatever module is loaded. Treat absence of
  a pin as **UNKNOWN**, not **OK**.
- Do not modify any patch automatically. This skill only reports.
- When the user wants to actually bump a pin, hand control back;
  updating the source belongs to the patch author, not this audit.
