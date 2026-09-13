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
real versions were displayed and the settings layout checked visually. The owner now requires NAS-only ROMs. The earlier local Melee test copy was
removed after its checksum matched a fresh NAS read; emulator saves were preserved.
No further local ROM staging is authorized. NAS source mounting and launch
acceptance remain pending; previous local gameplay checks do not validate NAS play. No game is labelled
playable until a real local copy has been indexed. Dolphin now has a saved Xbox
One S mapping; the owner confirmed gameplay and both reconnect sequences.
Dolphin's optional telemetry was declined and its FPS, speed and internal-resolution
overlays enabled for live verification.

Source: [official PCSX2 setup](https://pcsx2.net/docs/setup/running/) and
[release package](https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-macos-Qt.tar.xz).

CLI system-name reference: [Dolphin 2606a configuration mapping](https://github.com/dolphin-emu/dolphin/blob/2606a/Source/Core/Common/Config/Config.cpp).

## NAS-only performance investigation

The Mac-to-NAS SSH stream test (268.44 MB discarded in memory) measured
11.20 MB/s; this is not an SMB benchmark. A full NAS-side Melee SHA-256 read
measured 434.27 MB/s, potentially served from ARC cache. Ten ICMP samples
showed 4.54 ms average, 5.25 ms maximum and no packet loss. The Mac used Wi-Fi;
its listed Ethernet adapters were inactive. NAS Ethernet negotiated 1 Gb/s.
These samples suggest investigating the network path before storage tuning;
they do not prove a 100 Mb/s link or exclude intermittent latency.
No SMB share currently exposes the ROM directory, and no SMB volume is mounted
on the Mac. NAS-only game launch has not yet been tested. Network/storage
settings were not changed.

## PS2 controller configuration

Port 1 now maps the Xbox controller through SDL-0: face buttons, both sticks,
D-pad, Start/Select, shoulders, triggers, stick clicks and both rumble motors.
The previous INI was backed up before editing; BIOS, graphics and other sections
were retained. Bindings use the installed v2.8.2 SDL names and survived restart.
The final device list contained only keyboard and mouse, so physical PS2 input,
rumble and gameplay remain unverified until the controller is connected and a
verified PS2 game is available through the approved external storage path.

Source: [PCSX2 v2.8.2 SDL bindings](https://github.com/PCSX2/pcsx2/blob/v2.8.2/pcsx2/Input/SDLInputSource.cpp).

## Transfer link review

A private read-only inventory review classified all 731 Emulation symlinks:
710 resolve within the Emulation tree and 21 resolve into Deck home. Of the
internal targets, one is a regular file and 32 are directories containing
manifested regular files; 677 are absent from that regular-file inventory.
Absence does not prove a broken link: empty directories and link-to-link targets
need separate checking. No links were recreated or modified. The five home-backup
links require their own reconciliation. Portable USB setup is deferred until the
end at the owner's request; no local ROM staging is authorized.

## NAS SMB trial

The owner selected a separate SMB account. A dedicated no-login account and
read-only ROM share are configured; its generated credential is stored in macOS
Keychain, not source control. Access ACLs were backed up before granting narrowly
scoped read/traverse access to the verified Melee trial path. Transfer internals,
BIOS and saves are outside the share. Existing owner permissions were retained.
A 67.11 MB SMB read discarded in memory measured 12.21 MB/s. A write probe was
denied as required. Game Hub is configured with the mounted NAS GameCube folder.
No local ROM copy is made. The existing Xbox mapping and local save remain.

Access to future transferred ROMs is not yet automated: the worker creates private
temporary files before promotion, so directory inheritance alone is insufficient.
Current ACL coverage is the Melee trial, not the entire incoming library. The
private NAS-share folder contains account/share receipts, Keychain-backed mount
helper and access notes. No new router or firewall rule was added.

The emulator application picker now explicitly selects files rather than folders.
The full Debug build and installed code-signature verification passed. A stale
Computer Use picker state also required refreshing the automation session; the
code change is defensive and does not prove that stale state was caused by the app.

Direct NAS launch passed: Dolphin's running command references the RVZ under the
mounted SMB volume, and the game reached its main menu with the existing save.
Metal 3× remained active. The local ROM folder remains empty. Sustained NAS
match performance is still awaiting owner feedback; a menu-transition FPS sample
is not a gameplay benchmark. The hub's generic “Local” label currently describes
its emulator provider and does not identify the ROM storage location.

## Owner acceptance and continuing transfer integration

The owner reported that direct NAS Melee gameplay works great. This confirms the
NAS trial separately from the earlier local-copy check. No local ROM remains.
The dedicated reader now has read/traverse access to 375 already-verified files
under the ROM tree; prior ACLs are preserved in the private transfer directory.
The PS2 NAS folder and PCSX2 bookmark are saved in Game Hub, currently with zero
games until the disc image is transferred and verified.

A tested worker update is queued for the next verified batch boundary. It applies
reader ACLs after checksum verification and prioritizes the smallest PS2 image
(Hulk) next. It preserves the prior worker, completed checkpoints and ACLs.
The isolated tests cover read access, content preservation, rejecting paths
outside ROMs, rejecting symlinks and avoiding broadened masked ACL entries.
The update is scheduled, not yet confirmed active; its private status receipt
is authoritative. Existing transfer and hourly notification services continue.
