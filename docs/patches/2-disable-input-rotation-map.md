# 2-disable-input-rotation-map.lua

Stops KOReader from remapping touch coordinates when the screen rotates, by
replacing `Device.input.rotation_map` with empty tables for all four
rotations. Touch input is then passed through unchanged in every
orientation.

**Warning:** this is only useful on devices whose kernel or touch driver
already reports rotated coordinates, where KOReader's stock remap rotates
the input a second time and taps land in the wrong place. On devices where
the stock behavior is correct, installing this patch breaks touch in rotated
orientations. Install it only if you see the double-rotation symptom.

## Target

- **Patches:** KOReader core (device input layer)
- **Written against:** KOReader 2026.07.1

## Settings

No settings. Active whenever the patch file is installed.

## Disable

Remove or rename `koreader/patches/2-disable-input-rotation-map.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

None; it touches only the input layer.
