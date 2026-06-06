# Plugins

Plugin source is not vendored here. Versions are pinned per KOReader
target in [`manifest.yml`](manifest.yml); the release workflow downloads
those exact upstream tags into the bundle.

For install steps and recommended in-app settings, see
[docs/plugins.md](../docs/plugins.md).

| Plugin | Upstream | Install dir |
| --- | --- | --- |
| Project: Title | <https://github.com/joshuacant/ProjectTitle/releases> | `projecttitle.koplugin/` |
| Bookends | <https://github.com/AndyHazz/bookends.koplugin/releases> | `bookends.koplugin/` |

Installing manually instead of from a release bundle? Use exactly the
tags pinned in `manifest.yml`; the patches in this repo are written
against those versions.
