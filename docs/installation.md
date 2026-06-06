# Installation

This repo ships KOReader userpatches, icon overrides, and a pinned set of
upstream plugins. There are two ways to install: the pre-built release
bundle (recommended) or a manual install from the repo plus upstream
releases.

A release bundle unzips to a single directory named
`koreader-configs-<tag>-koreader<version>-<codename>/` containing:

| Entry | Contents |
| --- | --- |
| `patches/` | All userpatches from this repo |
| `icons/` | SVG overrides for KOReader's `mdlight` icon set |
| `plugins/` | The pinned upstream plugins, one `*.koplugin/` folder each |
| `settings/` | Bookends presets (see [settings.md](settings.md)) |
| `VERSIONS.txt` | Exact plugin tags and the KOReader version targeted |
| `INSTALL.txt` | Offline copy of the basic install steps |

## Option A: release bundle

1. Download the `.zip` and `.zip.sha256` for your KOReader version from
   [Releases](https://github.com/kurokeita/koreader-configs/releases).
2. Verify the download:

   ```sh
   sha256sum -c koreader-configs-<tag>-koreader<version>-<codename>.zip.sha256
   ```

3. Unzip and copy the contents into your KOReader data directory (see
   [below](#koreader-data-directory)), overwriting files with the same name:

   | From the bundle | To the device |
   | --- | --- |
   | `patches/*` | `koreader/patches/` |
   | `plugins/*.koplugin/` (each folder, whole) | `koreader/plugins/` |
   | `icons/*` | `koreader/resources/icons/mdlight/` |
   | `settings/*` | `koreader/settings/` (optional Bookends presets) |

   The icons are overrides for the `mdlight` set specifically; if you use a
   different icon set, skip them (some patches then fall back or warn, see
   the per-patch pages).

4. Restart KOReader.

## Option B: manual install

1. Clone or download this repo.
2. Copy `patches/`, `icons/`, and `settings/` to the device exactly as in
   the table above.
3. Install each plugin from its upstream Releases page, at **exactly the
   tag pinned in [`plugins/manifest.yml`](../plugins/manifest.yml)**:

   | Plugin | Upstream releases | Pinned tag (KOReader 2026.03 "Snowflake") |
   | --- | --- | --- |
   | Project: Title | <https://github.com/joshuacant/ProjectTitle/releases> | `2026.03-v3.7` |
   | Bookends | <https://github.com/AndyHazz/bookends.koplugin/releases> | `v5.14.0` |

   Unzip each release and drop the `*.koplugin/` folder whole into
   `koreader/plugins/`. The pins matter: several patches wrap specific
   functions in these releases and may break on other versions; see
   [plugins.md](plugins.md).

4. Restart KOReader.

## KOReader data directory

| Platform | Location |
| --- | --- |
| Kobo / Kindle / reMarkable | the `koreader/` folder at the root of the device's USB storage |
| Android | `Internal storage/koreader/` (may vary by install method; check `Top menu > Help > About` for the exact path) |
| Desktop (Linux/macOS) | the directory KOReader is launched from (for the AppImage, usually `~/.config/koreader/`) |

Create `koreader/patches/` if it does not exist yet.

## Upgrading

Repeat the copy steps with the new bundle; files are safe to overwrite. When
the bundle targets a new KOReader version, upgrade KOReader first, then the
bundle built for it (check `VERSIONS.txt`).

## Rollback

- **Plugins:** delete the plugin folders listed in the bundle's
  `VERSIONS.txt` from `koreader/plugins/`.
- **Patches:** delete the copied files from `koreader/patches/`, or disable
  individual patches by renaming them to `<name>.lua.disabled`.
- **Icons:** delete the copied SVGs from
  `koreader/resources/icons/mdlight/`; KOReader falls back to its bundled
  icons.

Restart KOReader after any of these.

## After installing

- [plugins.md](plugins.md): what the plugins are, why versions are pinned,
  and recommended in-app settings.
- [settings.md](settings.md): the Bookends presets shipped in `settings/`.
- [patches index](../patches/README.md): what each patch does, with links to
  per-patch detail pages.
