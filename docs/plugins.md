# Plugins

This setup is built around two third-party plugins. Their versions are
pinned per KOReader target in [`plugins/manifest.yml`](../plugins/manifest.yml),
and the release bundle ships exactly those tags.

The pins are not cosmetic: several patches in this repo wrap specific
functions inside these releases. For example, `2-bookend-unifont.lua` wraps
`Bookends:resolveLineConfig`, whose location and signature can move between
Bookends releases, and the Project: Title patches reach into
`MosaicMenuItem` internals. Running other plugin versions may silently
disable a patch or break the view. If you upgrade a plugin, re-audit the
patches first (the `koreader-version-bump` skill in this repo automates the
check).

## Version compatibility

| KOReader | Codename | Project: Title | Bookends |
| --- | --- | --- | --- |
| 2026.07.1 | Sailing Walrus | `2026.07-v3.8.3` | `v5.20.0` |

To move to a new KOReader version: bump `plugins/manifest.yml`, re-audit
each patch's pinned version, then tag a release so CI builds the new bundle.

## Project: Title

A full visual replacement for KOReader's file browser, built on the stock
coverbrowser plugin. Upstream: <https://github.com/joshuacant/ProjectTitle>.

Install: drop `projecttitle.koplugin/` into `koreader/plugins/` (the release
bundle does this for you), restart KOReader. PT replaces coverbrowser
automatically while enabled; to fall back, enable Cover Browser in the
plugin manager and restart.

### Recommended settings

The patch set in this repo is designed around PT's **cover grid (mosaic)
view**; in list views most patches do nothing. After installing, in the file
browser:

| Setting | Where | Value | Why |
| --- | --- | --- | --- |
| Display mode | `Top menu > settings tab > Display mode` | Cover grid | All cover patches target the mosaic view |
| Show history & last-document icons | `Project: Title settings > Advanced settings > Footer` | on | Added by `2-pt-footer-history-recent.lua` |
| Show folder name / Folder name centered | `Mosaic and detailed list settings` | on / on | Added by `2-rounded-folder-covers.lua` |

Two PT behaviors are intentionally overridden by patches rather than menu
settings: `2--disable-all-PT-widgets.lua` pins "hide file info" on and
"pages read as progress" off, and suppresses PT's own progress/status/series
decorations so the replacement badges from this repo can take over. Those
menu entries will appear unresponsive while that patch is installed; that is
expected. See the [patches index](../patches/README.md) for the full set.

## Bookends

Customizable text overlays for the reading screen: page numbers, clocks,
progress bars, battery, and more, in any of six positions. Upstream:
<https://github.com/AndyHazz/bookends.koplugin>.

Install: drop `bookends.koplugin/` into `koreader/plugins/`, restart
KOReader. With a book open, the menu lives at
`Top menu > typeset/document tab (style icon) > Bookends`.

### Recommended settings

1. Enable it: `Bookends > Bookends settings > Enable bookends`.
2. Turn on `Use book's embedded font` in the same menu (added by
   [`2-bookend-unifont.lua`](patches/2-bookend-unifont.md)), so overlays
   render in each book's own font.
3. Rather than configuring positions by hand, apply one of the presets
   shipped in this repo (`settings/bookends_presets/`): a top-clean layout
   for manga and an author/title layout for novels. See
   [settings.md](settings.md) for what they contain and how to load them.
4. When editing individual lines, the font picker has an
   "Inherit (use default font)" row added by
   [`2-bookend-line-font-inherit.lua`](patches/2-bookend-line-font-inherit.md);
   prefer it over picking a concrete font so lines follow the default.
