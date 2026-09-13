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
the preset to that session; the hub does not rewrite Dolphin's graphics files,
controller mappings, firmware or saves. Fullscreen batch launch uses Dolphin's
verified `-b`, `-e`, `-C` and `-v` options.

Emulator application metadata is inspected without running a program. Missing or
incomplete apps, oversized metadata and executable path escapes are rejected.
The version at source creation is displayed. Older source records with no version
or graphics preset remain decodable and keep existing emulator settings.

Validation: 72 core tests and the full locally signed Debug build pass. New tests
cover Dolphin argument boundaries, rename-stable GameCube discovery, version
inspection without execution, missing executables, traversal and symlink escape.
No real GameCube game has been launched yet; content transfer and controller/game
acceptance remain separate live checks. Linux Deck emulator backups are preserved
as backups and are not presented as installed macOS applications.

Sources: [official release download](https://dl.dolphin-emu.org/releases/2606a/dolphin-2606a-universal.dmg),
[official command parser](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/CommandLineParse.cpp),
[official graphics settings](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Config/GraphicsSettings.cpp).
