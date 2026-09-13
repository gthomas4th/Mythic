# Steam Deck ROM shortcuts

Owner clarification: the Steam library includes ROM shortcuts that reference files
on the Steam Deck and remain visible when that device/storage is disconnected.

## Catalog rules

- A non-Steam shortcut is not evidence of Steam ownership or a native Mac install.
- Preserve shortcut provenance and its originating device. Show `Steam Deck ROM
  shortcut` when that origin and ROM mapping are established; otherwise show
  `Non-Steam shortcut` with an unresolved target. Do not guess from title or artwork.
- Keep unavailable references visible with `Files on Steam Deck` / `Device offline`
  / `ROM unavailable`, and disable local Play until the actual emulator, BIOS when
  required, and content have passed preflight.
- Keep purchased Steam retro releases as Steam records, even when a similarly named
  ROM shortcut exists. Never merge solely by title or treat shortcut IDs as app IDs.
- Before content is accessible, retain a device-scoped shortcut reference. Once files
  can be fingerprinted, associate it with the emulator content identity rather than
  using a filesystem path as permanent ROM identity.
- Store per-device locations and availability separately from title identity. Later
  centralization updates locations, not ownership or favorites, and must not rewrite
  existing Steam Deck shortcuts without an explicit migration plan.

The current Steam-native slice only scans installed store manifests and verifies a
native Mac payload. It does not import non-Steam shortcuts or treat remote visibility
as proof of installation. Mac inspection found a 13-byte shortcuts file; no Deck ROM
inventory has yet been imported. Steam UI inspection was blocked by a ScreenCaptureKit
capture error, so no claims about the visible Steam library or account state are made.

## Central storage recommendation

Use a NAS master ROM library and local working copies on each device. This keeps
normal play independent of a mounted share or tunnel. Track which copies are available
in the hub; copy on demand instead of relocating the owner's current library.

Keep saves separate from ROM distribution. Plan backup/conflict handling and emulator
compatibility before synchronizing saves; ROM availability must never overwrite saves.
Direct NAS access can remain an opt-in launch location after testing that emulator,
format and network path. No share, firewall, mount or file migration has been changed.

Steam ROM Manager documents its entries as non-Steam shortcuts:
https://github.com/EmuDeck/emudeck.github.io/blob/main/docs/tools/steamos/steam-rom-manager.md
