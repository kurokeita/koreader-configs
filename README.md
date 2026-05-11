# koreader-configs

Personal KOReader userpatches, custom icons, and pinned plugin releases, bundled
together for easy installation on any KOReader device.

## Contents

| Directory | Description |
| --- | --- |
| `patches/` | Lua userpatches loaded by KOReader at startup from `koreader/patches/`. |
| `icons/` | SVG icon overrides that drop into KOReader's `mdlight` icon set. |
| `plugins/` | Manifest (`manifest.yml`) pinning upstream plugin versions per KOReader target. |

## Releases

Each [release](../../releases) ships a pre-built `.zip` bundle for a specific
KOReader version. The bundle contains this repo's patches and icons together with
the upstream plugin releases listed in `plugins/manifest.yml`, ready to unzip
directly onto your device.

See [INSTALL.md](INSTALL.md) for step-by-step instructions.

## Patches

The `patches/` directory holds Lua files prefixed with a load-order number (e.g.
`2-`, `20-`). They are picked up automatically by KOReader as
[userpatches](https://github.com/koreader/koreader/wiki/User-patches).

## Plugins

Plugin versions are declared in `plugins/manifest.yml` and downloaded from the
respective upstream GitHub releases during the CI build. See that file for the
exact pinned tags.

## Development

This repo uses [Claude Code](https://claude.ai/claude-code) with project-specific
skills under `.claude/skills/`. The main CI workflow (`.github/workflows/release.yml`)
builds and publishes the bundle on every new `v*` tag or manual `workflow_dispatch`.
