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
No further local ROM staging is authorized. NAS source mounting and direct gameplay subsequently passed, as recorded below. No game is labelled
playable until a verified accessible image has been indexed. Dolphin now has a saved Xbox
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
At the time of these measurements the ROM SMB share had not been created.
The subsequent read-only share and accepted direct launch are recorded below.
No network tuning was performed.

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

The initial trial covered only Melee. The worker now grants read access after
checksum verification and promotion; private partial files remain inaccessible. The
private NAS-share folder contains account/share receipts, Keychain-backed mount
helper and access notes. No new router or firewall rule was added.

The emulator application picker now explicitly selects files rather than folders.
The full Debug build and installed code-signature verification passed. A stale
Computer Use picker state also required refreshing the automation session; the
code change is defensive and does not prove that stale state was caused by the app.

Direct NAS launch passed: Dolphin's running command references the RVZ under the
mounted SMB volume, and the game reached its main menu with the existing save.
Metal 3× remained active. The local ROM folder remains empty. The owner subsequently accepted NAS gameplay; the earlier menu-transition FPS
sample is not a gameplay benchmark. The hub's generic “Local” label currently describes
its emulator provider and does not identify the ROM storage location.

## Owner acceptance and continuing transfer integration

The owner reported that direct NAS Melee gameplay works great. This confirms the
NAS trial separately from the earlier local-copy check. No local ROM remains.
The dedicated reader now has read/traverse access to 375 already-verified files
under the ROM tree; prior ACLs are preserved in the private transfer directory.
The PS2 NAS folder and PCSX2 bookmark are saved in Game Hub, currently with zero
games until the disc image is transferred and verified.

The tested worker update is active after a verified batch-boundary handover. It applies
reader ACLs after checksum verification and prioritizes the smallest PS2 image
(Hulk) next. It preserves the prior worker, completed checkpoints and ACLs.
The isolated tests cover read access, content preservation, rejecting paths
outside ROMs, rejecting symlinks and avoiding broadened masked ACL entries.
The private handover receipt confirms startup of the updated worker, and live
status confirms that copying continues. Existing transfer and hourly notification services continue.

## Additional native Mac engines

DuckStation 0.1-11894 (c66b2694d) and RetroArch 1.22.2 (69a4f0ea) are installed
in the owner's Applications folder. Both universal app bundles include arm64
and pass strict recursive signature verification. DuckStation's official download
matched its published GitHub SHA-256. RetroArch's download hash is recorded for
provenance, not described as independently authenticated. Automatic DuckStation
updates are disabled; no runtime auto-update was run.

DuckStation recognizes two owner BIOS images (USA and Europe), copied from the
checksum-verified NAS backup. Metal BIOS boot rendered at 60 FPS / 100% speed.
Its 4× internal-resolution preset, PGXP geometry correction and Xbox SDL mapping
are saved; game-native aspect ratio remains selected. PGXP is a starting preset
and may require per-game adjustment. This is a firmware/rendering check, not
PS1 gameplay or physical-controller acceptance. No PS1 game is indexed yet.

RetroArch uses Vulkan/MoltenVK on the M3 Pro, verified by a successful 120-frame
menu startup and clean exit. Native controller autodetection remains enabled.
Its browser starts at the mounted NAS ROM share. Saves and states remain local,
organized by core, with automatic state loading/saving disabled. Four official
ARM64 cores were installed and dynamically loaded to query their actual APIs:

| System | Core | Installed version |
|---|---|---|
| SNES | bsnes-hd beta | 10.6 |
| N64 | Mupen64Plus-Next | 2.8-Vulkan 6752836 |
| Sega Mega Drive / 32X | PicoDrive | 2.05-ab02114 |
| Dreamcast | Flycast | 9869ea8 |

These are pinned downloads from the official nightly core distribution, not
claims of stable core releases. Source URLs and computed artifact hashes are
retained in the private emulator receipts. Owner Dreamcast firmware was copied
from the verified NAS backup into RetroArch's system/dc directory. Core loading
does not establish game compatibility, renderer initialization inside each core,
or controller behavior. No local ROM copies were created.

Remaining integration: much of the SNES/N64/32X/PS1 inventory is ZIP-compressed,
and some system folders appear misfiled. Inspect archive contents on the NAS
before assigning systems. At initial setup Game Hub excluded archives and lacked some
raw Sega formats and Dreamcast GDI track grouping; the implementation below
adds the unambiguous cartridge formats and grouped GDI handling. ZIP archives
still require preparation on the NAS. Do not mark these sources
ready or silently extract ROMs onto the Mac. The large-game transfer continues;
additional NAS source bookmarks and per-system live launches follow verified
content availability and format handling.

Sources: [DuckStation](https://github.com/stenzek/duckstation),
[RetroArch macOS setup](https://docs.libretro.com/guides/install-macos/),
[official ARM64 core distribution](https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/),
[DuckStation SDL bindings](https://github.com/stenzek/duckstation/blob/master/src/util/sdl_input_source.cpp).

## NAS image preparation and format integration

The verified Gundam Battle Assault 2 ZIP contains one PBP image. It was extracted
on the NAS into its own game folder, retaining the original archive. The original
archive SHA-256, member CRC, PBP header, extracted size and fresh on-disk SHA-256
were checked before granting the dedicated reader access. No game bytes were
written to Mac storage. The extraction receipt remains with the private NAS job.

Game Hub now discovers PBP, V64 and unambiguous Sega cartridge extensions
(GEN/MD/SMD/32X). Loose BIN/RAW files and ZIP archives remain excluded. Dreamcast
GDI descriptors group their tracks into one game; M3U can group GDI discs. Bounded
parsing checks track counts, numbering, types, sectors, offsets and referenced
files. Missing files and paths outside the selected root are rejected. Ordered
track payloads and layout determine identity, while renamed tracks keep identity.
All 75 core tests pass, including archive exclusion, grouped tracks, renamed
tracks, changed layouts, malformed descriptors and symlink escape.

Format reference: [Flycast GDI reader](https://github.com/flyinghead/flycast/blob/master/core/imgread/gdi.cpp).

The full Debug build and installed signature verification passed after the format
change. Direct NAS Gundam boot reached its opening sequence with Metal at 1280×960,
30 game FPS / 60 video FPS and 100% emulation speed. A local 128 KiB memory card
was created. This verifies boot and a card write, not physical input, gameplay,
or save/relaunch acceptance. The PS1 folder/application bookmark is saved; the
first combined scan also hashes the newly verified 4.12 GB Hulk PS2 image.

Direct NAS Hulk boot also reached the memory-card prompt using Metal 3×
(1920×1344), displaying 60 FPS / 60 VPS. The virtual card was reported unformatted;
no formatting was performed. PS2 gameplay, physical input and save/relaunch remain
open. Both test emulator sessions were shut down normally.

The combined scan completed with three NAS entries: Melee, Hulk and Gundam.
A subsequent unchanged rescan returned immediately with the same three entries.
Game Hub's Gundam Play button launched DuckStation with the PBP path on the
mounted share; the opening sequence rendered successfully at Metal 4×. The
fullscreen render window was not initially visible to automation; F11 exposed
windowed game output for visual verification. This was an observation limitation,
not a failed launch. The session was shut down normally. The local ROM folder
remains empty. Installed code revision: `eca3a002`; later documentation commits
do not require another app build.

## Scan visibility and PS2 controller setup

ROM sources now display their actual folder paths. Scans identify the current
game and report decimal GB read/total, with throttled updates and an activity
indicator. Cached files retain the existing fast path. Completion/failure clears
the progress token so queued messages cannot replace the final result.

Both PCSX2 cards were confirmed entirely blank and backed up privately. During
the owner's controller session, PCSX2 detected Xbox One S Controller as SDL-0,
reported rumble support, and wrote slot 1. The card now contains the PS2 filesystem
signature. These observations verify detection and formatting/card writes, not
physical gameplay or a successful saved-game reload. The running Hulk session
is preserved. Desktop automation became unavailable (native pipe startup, then
missing enabled-surfaces configuration); no system permission changes were made.

The progress change passes the full Debug build and all 75 existing core tests.
Visual verification of the new progress UI awaits restored desktop automation.

## Owner PS2 control acceptance and network stall diagnosis

The owner confirmed Hulk controls are good, but reported excessive network lag.
PS2 input acceptance is recorded separately from playback performance, which is
not accepted. No emulator graphics changes or local ROM caching were introduced.

During the affected session, Mac-to-NAS ping measured 265.79 ms average and
907.32 ms maximum over 12 replies. A subsequent concurrent 20-packet comparison
showed approximately 403 ms average to the Mac's gateway, 411 ms to the NAS and
403 ms to Yoda; each had 35% unanswered when the short test ended. Delayed replies
can affect this short-test loss figure. NAS-to-Mac-gateway ping measured 0.94 ms
average and 1.20 ms maximum with all ten replies received. These observations
localize the common delay toward the Mac/access-point path, rather than proving
a NAS disk fault. The brief NAS pool sample showed no physical disk I/O; cache
and the short duration limit that observation. Ethernet error counters were zero,
with historical missed/drop counters present; no interval increase was measured.

The Mac routes through en0 and the local gateway. Wi-Fi reported channel 40,
5 GHz / 160 MHz, 802.11ax and a negotiated 2401 Mb/s (not measured throughput).
Its reported 0 dBm signal value is unusable. SMB is 3.1.1, with zero recorded
reconnections. A controller-off comparison was requested to test wireless
coexistence as a hypothesis, not an established cause. No router, security,
Bluetooth or network configuration was changed; the NAS transfer remains active.

## Follow-up baseline with games closed

On the next session, Bluetooth inventory listed the Xbox controller as not
connected and neither PS1 nor PS2 emulator was running. Mac-to-NAS ping measured
9.83 ms average / 44.09 ms maximum with all 12 replies. A memory-only workload
of 96 random 64 KiB reads from Hulk (6.29 MB total) took 1.98 seconds, with median
14.90 ms, p95 40.40 ms and maximum 110.14 ms per read. Concurrent ping measured
14.42 ms average / 88.98 ms maximum with all 30 replies. The source ISO remained
on the NAS; the test wrote no local game data.

This is an improved baseline, not a controlled explanation of yesterday's stalls:
the game state, controller state and observation time all changed. A repeat with
controller connected and games still closed was requested. The copy worker had
174.73 GB verified, remained active, and the hourly notification timer was active.

## Controller-on comparison and running-game latency

The owner connected the controller with games closed; Bluetooth inventory confirmed
Xbox Wireless Controller connected. Repeating the same offsets hit the Mac's RAM
cache, so those read timings are not a network benchmark. Concurrent ping was
10.96 ms average / 69.98 ms maximum, all 30 replies received. A new random-offset
sample of the same size then measured 13.44 ms median / 42.09 ms p95 / 99.43 ms
maximum per read, with 13.94 ms average NAS ping and all replies received. This
did not reproduce the prior severe stalls merely by connecting the controller.
It does not rule out intermittent interference or other load-dependent behavior.

Hulk was reopened from the NAS; PCSX2 confirmed Xbox input, Metal and execution
of SLUS-20422. During a 45-second running-game sample, router ping averaged
12.55 ms (111.26 ms maximum) and NAS ping averaged 12.90 ms (106.25 ms maximum),
with all 90 replies from each destination. Owner gameplay feedback for this
session remains pending; emulator execution alone is not active-gameplay
acceptance. The running session is preserved. No network or graphics settings
were changed, and no local ROM copies were made.
