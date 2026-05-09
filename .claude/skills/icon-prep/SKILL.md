---
name: icon-prep
description: >-
  Normalize a new SVG icon to match the visual convention of the
  existing `icons/` set (Lucide-style 24x24, fill="none",
  stroke="#000000", stroke-width="1", round caps and joins). Use when
  the user wants to "add an icon", "drop in an SVG", "normalize this
  icon", or has a raw SVG that needs to fit alongside the existing
  icons before being shipped to KOReader.
disable-model-invocation: true
---

# Icon Prep

Conforms a new SVG to this repo's icon convention so it renders
consistently with the existing icons in KOReader's UI.

## When to run

User-only. Invoked when adding a new icon to `icons/`, given either a
path to an SVG or pasted SVG content.

## Target convention

Inspect existing icons (`icons/home.svg`, `icons/align.center.svg`,
etc.) for the source-of-truth shape. The expected root element is:

```xml
<svg xmlns="http://www.w3.org/2000/svg"
     width="24" height="24"
     viewBox="0 0 24 24"
     fill="none"
     stroke="#000000"
     stroke-width="1"
     stroke-linecap="round"
     stroke-linejoin="round">
  <!-- one or more <path> children -->
</svg>
```

## Procedure

1. Read the input SVG (path or pasted content).
2. Verify or rewrite the root attributes to match the convention
   above. In particular:
   - `width="24"` and `height="24"` (no units).
   - `viewBox="0 0 24 24"`. If the source uses a different viewBox,
     scale the path data or reject and ask the user — do not silently
     squash.
   - `fill="none"`, `stroke="#000000"`, `stroke-width="1"`,
     `stroke-linecap="round"`, `stroke-linejoin="round"`.
3. Strip:
   - XML prolog (`<?xml ... ?>`) and DOCTYPE.
   - Comments, `<title>`, `<desc>`, `<metadata>`.
   - `class=`, `id=`, `data-*` attributes on the root and children.
   - Inline `style=` attributes.
   - Any `fill` or `stroke` declared on child `<path>` (let them
     inherit from root).
4. Inline the result on a single line (matches the existing files'
   formatting).
5. Confirm the destination filename with the user. KOReader looks up
   icons by filename without the `.svg` suffix; pick a stable,
   lowercase, dot-separated name (`appbar.<thing>.svg`, or a bare
   noun like `home.svg`, `history.svg`).
6. Write the normalized SVG to `icons/<name>.svg`.

## Notes

- Do not introduce `currentColor` — the existing convention is
  hard-coded `#000000`. KOReader handles theming separately.
- If the source uses `<rect>`, `<circle>`, or other primitives, leave
  them as-is (Lucide icons in this set use only `<path>`, but other
  primitives are valid SVG).
- If `svgo` is on PATH, you may run it as
  `svgo --pretty=false --multipass <file>` after writing to compress
  further. Do not require it.
- For large viewBox sources (e.g. 256x256 Material icons), prefer
  rejecting with a note rather than guessing a scale; the user should
  pick a 24x24 source.
