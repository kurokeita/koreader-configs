# 2-coverimage-lighten.lua

Adds a "Lighten for color e-ink" percentage slider to the Cover Image plugin.
When set above 0, the saved screensaver image is blended onto a white
background at reduced opacity (the percentage is how far it is pushed toward
white) after the plugin writes it. This compensates for color e-ink panels
without front light, where covers otherwise look dark.

Only the saved cover file is changed; the book and its real cover are
untouched.

## Target

- **Patches:** coverimage plugin (stock KOReader)
- **Written against:** KOReader 2026.03

## Settings

Menu path:
`Top menu > Settings (gear) > Screen > Cover image > Size, background and format > Lighten for color e-ink`
(inserted as the second entry of that submenu)

| Option | Default | What it does | Recommended |
| --- | --- | --- | --- |
| Lighten for color e-ink | 0 (off) | Blends the saved cover toward white by 0-70 % | 30 |

> **Draft recommendation** - confirm before merge. (The patch's own help text
> suggests 30 = subtle, 50 = medium.)

Changing the value immediately regenerates the cover image for the open book.
Persisted in `G_reader_settings` key `cover_image_lighten`.

## Disable

Set the slider to 0 to keep the patch but bypass processing, or remove/rename
`koreader/patches/2-coverimage-lighten.lua` on the device (add a `.disabled`
suffix to keep it around), then restart KOReader.

## Interactions

`2-coverimage-eink-optimize.lua` post-processes the same saved file. Both can
be active at once; this patch loads after it, so the effective order is
optimize first, then lighten on top of the result. Note the optimize patch
also boosts saturation and contrast, which counteracts heavy lightening; tune
the two sliders together.
