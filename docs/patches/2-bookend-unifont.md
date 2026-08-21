# 2-bookend-unifont.lua

Renders Bookends header/footer overlays in the open book's own font. When
enabled and a zip-based book (EPUB, `.fb2.zip`, `.htmlz`) is opened, the patch
extracts the book's main body font from the archive and substitutes it, at
render time only, for whatever font each overlay line is configured to use.
When the book declares a body font that is not embedded, or embeds no usable
font at all, the overlay falls back to the book's current KOReader reading
font, so the overlay always mirrors the page text.

It never changes the document's reading font, the KOReader UI font, or
Bookends' stored configuration; everything reverts automatically when the
toggle is turned off or a book without a usable font is opened.

Body-font selection is CSS-aware: it prefers the family declared on `body`
(then `p`, then `html`), resolves it through the book's `@font-face` rules,
and explicitly excludes drop-cap and decorative-initial faces. Extracted fonts
are cached under `cache/bookend-unifont/` in the KOReader data directory; the
cache is pruned to the single font in use.

## Target

- **Patches:** bookends plugin
- **Written against:** Bookends v5.22.0 (wraps `Bookends:resolveLineConfig`
  and `Bookends:buildBookendsSettingsMenu`); needs KOReader with
  `ffi/archiver` (2026.07.1)
- **Verified:** re-checked against changed code: hooked upstream code changed in
  the pinned release, and the patch was re-verified against the new body.
- **Requires:** Bookends plugin installed

## Settings

Menu path (with a book open):
`Top menu > typeset/document tab (style icon) > Bookends > Bookends settings > Use book's embedded font`
(inserted directly above the stock "Default font" entry).

| Option | Default | What it does | Recommended |
| --- | --- | --- | --- |
| Use book's embedded font | off | Toggles the render-time font override for all overlay lines | on |

While the toggle is on, Bookends' own "Default font" entry is greyed out,
since the override would hide any change made there.

Persisted in `G_reader_settings` key `bookend_unifont_enabled`.

## Disable

Turn the toggle off in the menu (this also clears the injected font), or
remove/rename `koreader/patches/2-bookend-unifont.lua` on the device (add a
`.disabled` suffix to keep it around), then restart KOReader. Leftover cached
fonts live in `cache/bookend-unifont/` inside the KOReader data directory and
can be deleted freely.

## Interactions

`2-bookend-line-font-inherit.lua`: while this patch's toggle is enabled, the
book font is substituted for every overlay line, so per-line font overrides
and the Inherit option have no visible effect. Disable the toggle to make
per-line choices visible again. The patches coexist without conflict.
