# 2-coverimage-eink-optimize.lua

Image optimization for color e-ink panels (Kaleido, Gallery), applied to the
book-cover images KOReader shows while the device sleeps. One strength slider
drives a combined pipeline:

1. Gamma lift: brightens shadows and midtones
2. Saturation boost: compensates for washed-out e-ink colors
3. S-curve contrast: adds punch without blowing out highlights
4. Floyd-Steinberg dithering: quantizes to 16 levels per channel
   (approximately Kaleido color depth) for smoother gradients

The patch covers both sleep-screen mechanisms, each with its own setting:

- **Cover Image plugin** (Android, reMarkable, PocketBook, emulator): the
  saved screensaver file is post-processed after the plugin writes it.
- **Built-in Sleep screen** (Kobo, Kindle, Cervantes, anything where
  `Device:supportsScreensaver()` is true): cover and random/custom images are
  processed in memory just before the screensaver is shown.

## Target

- **Patches:** coverimage plugin and `ui/screensaver` (stock KOReader)
- **Written against:** KOReader 2026.07.1

## Settings

Two independent sliders, one per mechanism:

Cover Image plugin path:
`Top menu > Settings (gear) > Screen > Cover image > Size, background and format > Optimize for color e-ink`

Sleep screen path:
`Top menu > Settings (gear) > Screen > Sleep screen > Wallpaper > Optimize for color e-ink`
(enabled only when the sleep screen type is a cover or random image)

| Option | Default | What it does | Recommended |
| --- | --- | --- | --- |
| Optimize for color e-ink (Cover image) | 0 (off) | Strength 0-100 % in steps of 5; scales gamma (1.0-2.0), saturation (1.0-1.8), and S-curve steepness (0-8) before dithering | 50 |
| Optimize for color e-ink (Sleep screen) | 0 (off) | Same pipeline, applied to the built-in screensaver's cover/random image | 50 |

The patch's own help text suggests 30 = subtle, 50 = recommended,
80 = aggressive.

Persisted in `G_reader_settings` keys `cover_image_eink_optimize` and
`screensaver_eink_optimize`. On the sleep-screen side, processing applies to
the `cover` and `random_image` screensaver types.

## Disable

Set both sliders to 0 to keep the patch but bypass processing, or
remove/rename `koreader/patches/2-coverimage-eink-optimize.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

`2-coverimage-lighten.lua` also post-processes the Cover Image plugin's saved
file. Both can be active at once; because that patch loads after this one,
the effective order is optimize first, then lighten on top of the result. If
covers look washed out with both enabled, reduce the lighten amount first.
