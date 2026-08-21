# 2-pt-footer-history-recent.lua

Adds History and Open-Previous-Document icon buttons next to the pagination
chevrons in Project: Title's file-browser footer. The buttons appear in the
file manager, History, and Collections views (the History button hides when
the History list itself is open), are sized to match the chevron row, and
respect PT's reversed-footer layout. Tapping them opens the History list or
reopens the last document.

## Target

- **Patches:** projecttitle plugin (CoverMenu footer/menu init)
- **Written against:** ProjectTitle 2026.07-v3.8.3 /
  KOReader 2026.07.1
- **Requires:** Project: Title plugin installed (replaces coverbrowser);
  without it this patch does nothing. Uses the `history` and `last_document`
  icons (shipped by PT, also present in this repo's `icons/` set).

## Settings

Menu path (in the file browser):
`Top menu > first tab (settings) > Project: Title settings > Advanced settings > Footer > Show history & last-document icons`

| Option | Default | What it does | Recommended |
| --- | --- | --- | --- |
| Show history & last-document icons | off | Toggles the footer icon buttons; prompts for a restart | on |

The option is mutually exclusive with PT's "Replace folder name with device
info": turning either on switches the other off, since both compete for
footer space.

Persisted as `show_footer_nav_icons` in coverbrowser's settings database
(BookInfoManager), not in `G_reader_settings`.

## Disable

Turn the toggle off in the menu, or remove/rename
`koreader/patches/2-pt-footer-history-recent.lua` on the device (add a
`.disabled` suffix to keep it around), then restart KOReader.

## Interactions

None with the cover patches; this one only touches the footer row. It
coexists with PT's reversed-footer option and steps aside automatically when
"Replace folder name with device info" is enabled.
