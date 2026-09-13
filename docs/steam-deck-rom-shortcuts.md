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

## Implemented reference import

Library → Steam Deck opens a persistent, searchable inventory. The owner selects a
copied binary `shortcuts.vdf`; bounded parsing rejects truncation, duplicates,
unsupported types and ambiguous entries. A literal supported EmuDeck ROM path in
LaunchOptions produces `Files on Steam Deck`; unknown mappings stay unresolved.
No shortcut command is executed or persisted. Only title, device UUID, shortcut ID
and an optional ROM reference path enter the private local JSON inventory.

Re-imports merge by device/shortcut identity and preserve entries absent from a later
export. Invalid files and future/corrupt inventory schemas do not overwrite the prior
inventory. No remote reachability is inferred from a file path. Local Play is not
exposed until emulator/content preflight exists. Ten synthetic tests cover parser,
identity and merge behavior; the app screen and file chooser were verified. The
owner's real Deck export and a populated live import remain pending.

Steam-native scanning remains separate. The Mac's local shortcut file was empty;
no Deck inventory or ROM files have been transferred yet. See the
[copy-only transfer guide](steam-deck-transfer-guide.md).

## Central storage recommendation

Use a NAS master ROM library and local working copies on each device. This keeps
normal play independent of a mounted share or tunnel. Track which copies are available
in the hub; copy on demand instead of relocating the owner's current library.

Keep saves separate from ROM distribution. Plan backup/conflict handling and emulator
compatibility before synchronizing saves; ROM availability must never overwrite saves.
Direct NAS access can remain an opt-in launch location after testing that emulator,
format and network path. The empty central folders were created on the owner-selected archive NAS. No SMB share, firewall, mount or existing game files were changed.

Steam ROM Manager documents its entries as non-Steam shortcuts:
https://github.com/EmuDeck/emudeck.github.io/blob/main/docs/tools/steamos/steam-rom-manager.md
