# 2-disable-input-rotation-map.lua

Stops KOReader from renaming physical key events when the screen rotates, by
replacing `Device.input.rotation_map` with empty tables for all four
rotations.

That map is read in exactly one place, `input.lua:813`, where it rewrites a
key's name to follow the screen orientation: `Up` becomes `Right`, `LPgBack`
becomes `LPgFwd`, and so on. On a Boox the page-turn buttons arrive as
`VOLUME_UP`/`VOLUME_DOWN` and are mapped to `LPgBack`/`LPgFwd`
(`android/event_map.lua`), so they are exactly the names the stock map flips.
With the map emptied, the keys keep their unrotated names. It does not affect
touch coordinates.

**Ships disabled.** The bundle contains this patch as
`2-disable-input-rotation-map.lua.disabled`, so it does nothing after a normal
install. KOReader 2026.07.1 already calls `Input:disableRotationMap()` for the
Onyx models that need this — `go7`, `gocolor7`, `gocolor7_2`, `hibreak`,
`moaanmix7`, `xiaomi_reader` (see
[koreader#12423](https://github.com/koreader/koreader/issues/12423)) — and that
installs the same empty map this patch does, so on those devices the patch is
redundant.

**Warning:** this is only useful on a device whose firmware already reports
keys by gravity, where KOReader's stock rename rotates them a second time and
the page-turn buttons work backwards in rotated orientations. On a device where
the stock behavior is correct, enabling this patch makes the buttons stop
following the screen. Enable it only if the buttons are wrong and the device is
not on the list above.

## Target

- **Patches:** KOReader core (device input layer)
- **Written against:** KOReader 2026.07.1
- **Verified:** symbol level against the pinned release: every hooked upstream
  symbol is present, and unchanged from the previous target.

## Settings

No settings. Active whenever the patch file is installed with a `.lua`
extension.

## Enable

Rename `koreader/patches/2-disable-input-rotation-map.lua.disabled` to
`2-disable-input-rotation-map.lua` on the device, then restart KOReader. To
turn it back off, restore the `.disabled` suffix (or delete the file) and
restart again.

## Interactions

None; it touches only the input layer. In particular it has no effect on screen
rotation — orientation on Android comes from the OS window config change, and
KOReader's own saved modes (`fm_rotation_mode` for the browser,
`kopt_rotation_mode`/`copt_rotation_mode` per document, both gated on
`lock_rotation`). If rotation looks stuck, check those settings, not this patch.
