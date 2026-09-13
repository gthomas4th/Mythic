# Emulator readiness

Dolphin 2606a is installed from the official universal macOS release. The downloaded
artifact matches SHA-256 `15df1afeac686951647d81b0b62e11d82e8715c92927b849e2858379cee6b5ca`;
the installed app passes strict recursive code-signature verification and contains
an arm64 executable. `Dolphin --version` and `--help` were checked locally.

Game Hub now supports Dolphin as an explicit launch adapter. GameCube/Wii image
formats GCM, RVZ, WIA, WBFS and CISO join existing ISO support. Archives remain
unindexed until extracted. Content identity survives renaming; formats are not
silently converted or treated as interchangeable identities.

The source picker offers existing Dolphin settings, Metal/native resolution, or
Metal/3× resolution (approximately 1080p). The latter is a starting preset for the
owner's M3 Pro, not a measured per-game performance claim. Launch arguments apply
the preset to that session. Existing sources expose a saved graphics picker; changing
it refreshes the next launch without re-importing games. A failed save retains the
previous setting. The hub does not rewrite Dolphin's graphics files,
controller mappings, firmware or saves. Fullscreen batch launch uses Dolphin's
verified `-b`, `-e`, `-C` and `-v` options.

Emulator application metadata is inspected without running a program. Missing or
incomplete apps, oversized metadata and executable path escapes are rejected.
The version at source creation is displayed. Older source records with no version
or graphics preset remain decodable and keep existing emulator settings.

Validation: 72 core tests and the full locally signed Debug build pass. New tests
cover Dolphin argument boundaries, rename-stable GameCube discovery, version
inspection without execution, missing executables, traversal and symlink escape.
A checksum-verified local Melee RVZ was indexed and launched from Game Hub.
The live test exposed and corrected the CLI graphics system name: `Graphics`,
not the `GFX.ini` filename. The corrected launch showed Metal, 1920×1584
internal resolution (3×), about 59.96 FPS and 100% speed at the initial memory-card
prompt. This is a boot/rendering check, not a gameplay benchmark. Automated
keyboard events did not advance the prompt. The Xbox One S controller was then
configured with SDL button/axis bindings, preserving the prior configuration and
Apex profile. The owner confirmed gameplay and disconnect/reconnect checks,
including reconnect after mouse interaction, worked well. The owner clarified
that the reported mild lag was network lag, not input lag; its connection has
not yet been identified. After the owner created game data, a normal exit wrote the Melee GCI save.
A fresh Game Hub launch advanced directly into the intro without the save-creation
prompt; basic save persistence passed. The Xbox mapping and Metal 3× preset
persisted. This does not verify every unlock or future save operation. The full build and all 72 tests passed after the correction. Linux Deck emulator backups are preserved
as backups and are not presented as installed macOS applications.

Sources: [official release download](https://dl.dolphin-emu.org/releases/2606a/dolphin-2606a-universal.dmg),
[official command parser](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/CommandLineParse.cpp),
[official graphics settings](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Config/GraphicsSettings.cpp).

## PS2 setup verification

PCSX2 v2.8.2 is installed from its official macOS release. Its package matches
SHA-256 `3ed9eb40a33eae67134142c24255a079be444f0616ca29575a04a37981f7d426`.
Strict signature verification and Gatekeeper assessment pass as a notarized
Developer ID application. This build is Intel x86_64 and runs through Rosetta;
it is not described as a native Apple Silicon build.

The owner's BIOS was copied from the verified central backup, retaining its hash.
PCSX2 recognizes USA v01.90 and successfully boots it. The emulator log confirms
Metal initialized on the Apple M3 Pro. Graphics are set to Metal and 3× native
(~1080p), with compatibility defaults retained and automatic updates disabled.
No external BIOS download was used, and Deck/NAS originals remain unchanged.
The BIOS session was shut down normally. This validates initialization, not PS2
game performance or controller behavior.

Both GameCube/Dolphin and PS2/PCSX2 source bookmarks are saved in Game Hub. Their
real versions were displayed and the settings layout checked visually. Local
working-copy folders are separate from the NAS master. No game is labelled
playable until a real local copy has been indexed. Dolphin now has a saved Xbox
One S mapping; the owner confirmed gameplay and both reconnect sequences.
Dolphin's optional telemetry was declined and its FPS, speed and internal-resolution
overlays enabled for live verification.

Source: [official PCSX2 setup](https://pcsx2.net/docs/setup/running/) and
[release package](https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-macos-Qt.tar.xz).

CLI system-name reference: [Dolphin 2606a configuration mapping](https://github.com/dolphin-emu/dolphin/blob/2606a/Source/Core/Common/Config/Config.cpp).
