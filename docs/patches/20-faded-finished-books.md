# 20-faded-finished-books.lua

Gives finished books a faded, washed-out look in the cover grid (mosaic)
view by lightening the exact rectangle of the visible cover after it is
painted. Books with any other status render normally.

The `20-` priority prefix makes this patch load after all the `2-` patches,
so its paint wrapper runs last: the fade is applied on top of the fully
decorated cover (status icons, badges, progress bar), fading the whole
composition uniformly.

## Target

- **Patches:** coverbrowser plugin (MosaicMenuItem paint path); written for
  Project: Title's mosaic view
- **Written against:** ProjectTitle 2026.07-v3.8.3 / KOReader 2026.07.1
- **Requires:** Project: Title plugin installed (replaces coverbrowser).

## Settings

No in-app settings. One tunable constant at the top of the file
(`patches/20-faded-finished-books.lua:5`):

| Constant | Default | What it does |
| --- | --- | --- |
| `fading_amount` | 0.5 | Fade strength from 0 (none) to 1 (white) |

Edit the file and restart KOReader to apply changes.

## Disable

Remove or rename `koreader/patches/20-faded-finished-books.lua` on the
device (add a `.disabled` suffix to keep it around), then restart KOReader.

## Interactions

- Fades everything painted inside the cover rectangle, including the
  decorations added by the `2-` badge patches; that is intentional, finished
  books recede as a whole.
- `2-new-status-icons.lua`'s "complete" dogear is painted before the fade
  and is therefore faded with the cover; the faded look itself signals the
  finished state.
- `20-rounded-covers.lua` shares the `20-` priority and sorts after this
  file, so its corners are painted after the fade and stay crisp.
