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
