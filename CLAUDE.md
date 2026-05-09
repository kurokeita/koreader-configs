# koreader-configs

Personal KOReader userpatches and icon overrides. Lua patches in
`patches/` are loaded by KOReader at startup from `koreader/patches/`
on the device. Custom icons in `icons/` ship into KOReader's icon
system. `plugins/README.md` points to upstream Releases for the plugins
this repo is configured against.

## Project Skills

Project-scoped skills live under `.claude/skills/`:

- `koreader-plugin-development` — patch and plugin development
  conventions for KOReader (auto-invoked).
- `patch-changelog` — regenerate `patches/README.md` index after
  adding/removing patches.
- `koreader-version-bump` — audit each patch's pinned KOReader version
  (user-only, `/koreader-version-bump`).
- `icon-prep` — normalize a new SVG to the existing `icons/`
  convention (user-only, `/icon-prep`).

## Rules

@.claude/rules/serena.md
