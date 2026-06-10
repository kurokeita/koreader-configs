# 2-pt-profiler.lua

Enables Project: Title's built-in draw timers (`ptdbg.enabled`). With the
patch installed, PT logs how long each file-browser page and each item takes
to build, at info level in `crash.log`:

```text
Project: Title - Draw grid item <name> done in 42.317
Project: Title - Draw whole page done in 481.205
Project: Title - Cache book <path> done in 1203.880
```

This is a diagnostic patch for investigating file-browser sluggishness:
install it, reproduce the slow navigation, read the timings out of
`crash.log`, then remove the patch. Leaving it installed permanently is
harmless but adds a little overhead per draw and grows `crash.log` quickly
(one line per visible item per page draw).

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
