---
name: patch-changelog
description: >-
  Scan every `.lua` file in `patches/` and rebuild `patches/README.md`
  as an index table mapping each patch to a one-line summary, target
  plugin/component, and pinned KOReader version. Use when the user
  asks to "update patch index", "regenerate patches readme", "list
  what each patch does", or after adding/removing a patch.
---

# Patch Changelog Index

Maintains `patches/README.md` as an at-a-glance index of what every
userpatch in this repo does.

## When to run

- After adding, removing, or renaming a patch.
- When the user asks to refresh, regenerate, or list the patches.
- Claude may also run this proactively after a commit that touches
  `patches/*.lua` if the README is now out of date.

## Procedure

1. Enumerate `patches/*.lua` AND `patches/*.lua.disabled` (treat
   `.disabled` separately).
2. For each file, extract:
   - **Summary**: first non-blank line of the leading `--[[ ... --]]`
     block. If the block opens with a heading-like line, use it;
     otherwise the first sentence ending with `.` or a newline.
   - **Target**: pull from a `Targets:` block when present (plugin
     name and/or KOReader version). Otherwise scan for
     `userpatch.registerPatchPluginFunc("<name>", ...)` and report
     `<name>`. If neither, "core".
   - **Priority prefix**: the leading `N-` digits in the filename
     (`2-`, `20-`, `0-` etc.).
3. Write `patches/README.md` with two tables:

   ```markdown
   # Patches

   Userpatches applied at KOReader startup. Drop into
   `koreader/patches/` on your device.

   ## Active

   | Priority | File | Targets | Summary |
   | --- | --- | --- | --- |
   | 2 | `2-pt-footer-history-recent.lua` | coverbrowser (PT) | ... |
   | ... | ... | ... | ... |

   ## Disabled

   | File | Summary |
   | --- | --- |
   ```

4. Sort each table by priority ascending, then filename.

## Notes

- The README is a generated index. Do not hand-edit it; rerun the
  skill instead.
- If a patch has no header comment, log a warning and emit
  `<missing summary>` in the cell so the gap is visible.
- Do not delete or move any patch file. This skill only reads and
  writes `patches/README.md`.
- Use `Write` to overwrite the README; do not append to a stale
  version.
