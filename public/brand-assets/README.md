# Brand assets

Every logo, favicon and app icon bundled with WaDesk is generated from the SVGs in `source/`.
The current artwork is a **placeholder** (white chat bubble on blue `#2781F6`, "WaDesk" wordmark).

| Source | Used for |
| --- | --- |
| `source/icon.svg` | favicons, apple/android/ms icons, sidebar logo, widget and design-system thumbnails |
| `source/icon-badge.svg` | favicon with the unread-messages dot |
| `source/wordmark-light.svg` / `wordmark-dark.svg` | `logo.svg` / `logo_dark.svg` and the design-system PNG logos |
| `source/bot-avatar.svg` | the bot avatar (`chatwoot_bot.png`; the file name is a code identifier and stays) |
| `source/team-signature.svg` | the sign-off on the year-in-review slide |

## Changing the brand

1. Replace the SVGs in `source/` (keep the canvas sizes).
2. From the repo root run `sh public/brand-assets/generate-icons.sh` (needs `rsvg-convert` from librsvg).
3. Commit the regenerated files. File names never change, so no code or config edits are needed.

`Logo.vue` in `components-next/icon/` inlines the icon artwork; update it when `source/icon.svg` changes.
Per-installation logos can also be set without a deploy in the Super Admin settings (LOGO, LOGO_DARK, LOGO_THUMBNAIL), which take priority over these files.
