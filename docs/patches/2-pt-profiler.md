# 2-pt-profiler.lua

Enables Project: Title's built-in draw timers (`ptdbg.enabled`). With the
patch installed, PT logs how long each file-browser page and each item takes
to build:

```text
Draw grid item <name> done in 42.317 ms
Draw whole page done in 481.205 ms
genItemTable(/sdcard/Books): 124 items in 310.221 ms
patch status: foldercover-perf=true bookinfo-cache=true rounded-folder-covers=true
```

Timings go to the normal log (crash.log on e-ink devices, logcat on
Android) **and** to a plain file `pt-profile.log` in the koreader data
directory, next to `patches/`, so they are readable on Android without
adb. The file is recreated on each restart and additionally records:

- a `patch status:` line (~5s after startup) showing which of this repo's
  PT performance patches actually took effect on the device;
- `genItemTable(...)` lines timing item-table generation per navigation
  (folder counting and sorting), a cost PT's own draw timers do not cover.

This is a diagnostic patch for investigating file-browser sluggishness:
install it, reproduce the slow navigation, read the timings, then remove
the patch. Leaving it installed permanently is harmless but adds a little
overhead per draw and the log file grows quickly (one line per visible
item per page draw).

## Target

- **Patches:** coverbrowser plugin as shipped by Project: Title (`ptdbg`
  module)
- **Written against:** ProjectTitle 2026.03-v3.7 / KOReader 2026.03
- **Requires:** Project: Title plugin installed (replaces coverbrowser);
  without it (no `ptdbg` module) this patch logs a warning and does nothing.

## Settings

No settings. Active whenever the patch file is installed.

## Disable

Remove or rename `koreader/patches/2-pt-profiler.lua` on the device
(add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

None. It only flips a logging flag; pairs naturally with
`2-pt-foldercover-perf.lua` for before/after measurements.
