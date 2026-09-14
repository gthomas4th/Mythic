# Game Hub delivery and acceptance

The Mac implementation and live verification are still in progress. The complete original
project acceptance is **not yet closed**. Owner authorization permits continuing all
routine implementation, builds and clean commits; it does not turn missing tests
into passes.

## Installed candidate

Authoritative local app: `~/Applications/Game Hub.app`.
The exact installed source revision is recorded in the private
`.build-local/installed-revision.json` receipt on `feat/steam-native`. Xcode performed the local ad-hoc signing; the installed copy
passes `codesign --verify --deep --strict`. This is not a notarized public release.
The original app and runtime are preserved. Development builds and the test host
are not the user entry point. Do not remove recovery copies before final live acceptance.

## Current emulator snapshot

Owner-accepted gameplay: GameCube/Melee, PS2/Hulk, SNES/Super Mario World,
N64/Super Mario 64, Mega Drive/Sonic 2 and Dreamcast/Power Stone. PS1/Gundam gameplay is now also owner-accepted. Dreamcast/Power Stone is also indexed in the hub; its hub Play check remains open. Save-reload tests and Apex 5 rear-paddle customization are deferred.

SNES, N64 and Genesis sources are indexed in the hub alongside GameCube, PS2
and PS1. Their hub Play checks remain pending. Installed revision `a348a9b3`
labels network-volume ROMs **Server**, local-volume ROMs **Local**, and unavailable
volume metadata **ROM**. Both regular and controller library views use the label;
storefront identity and recent-launch history are unchanged. Build, signature and
actual NAS/local volume classification checks passed.

## Working configuration

- FFVII Rebirth, Steam app 2909400; 171.06 GB installed in the shared Windows Steam
  environment. The owner launched and moved through gameplay, then accepted about
  40 FPS at the game's displayed 1080p resolution.
- Free WS12WineSikarugir10.0_6 plus D3DMetal 3.0, default synchronization,
  AVX advertisement, Retina off. The existing runtime and saves are retained.
- Profile `steam-2909400-accepted`, runtime `sikarugir-10-d3dmetal-3`, manual runtime
  update policy. A local binding hashes 4,755 runtime/renderer files and keeps folder
  bookmarks outside source control. Launch verifies pinned file content off the UI thread.
- Profile copies are separately stored. Imports are bounded, validated and become
  test copies; selecting one requires closing Windows Steam first. Restore the
  accepted profile using Launch Settings. Profile revision rollback never changes saves.
- The previous 34.56 FPS sample and subsequent roughly 78 FPS sample had unlabelled
  scenes. They are not an A/B benchmark. The owner confirmed the 720p request did not
  change the displayed 1080p resolution; no performance increase is claimed.

## Implemented and checked

| Area | Evidence |
|---|---|
| Windows Steam library | Live read-only discovery finds `steam:2909400`; app-created SQLite catalog contains it |
| Launch integration | Main library Play resolves native/Windows targets and uses official Steam `-applaunch`; Home PC tile-to-game verified; local launch through the controller view verified by Steam process tracking and owner confirmation of the game window |
| Catalog | SQLite schema version 2, deterministic provider identities, target merge/resolver, favorite/recent/preference persistence; reopening covered by tests |
| Legacy data | Epic/local records now persist in SQLite after a one-way import; original defaults and schema-1 backup are retained; existing launch/install APIs remain intact |
| Profiles | Validation, export/import, clone, selection and revision rollback; original profile remains available |
| Deck | Device-scoped shortcut references remain offline-readable; imported commands are never executed |
| ROMs | Folder/application/core bookmarks, incremental content hashes, cue/m3u grouping, missing-part/traversal/cycle checks; real Deck inventory imported; central copy in progress; Melee launch/Metal 3× rendering verified; owner-confirmed gameplay/reconnect; basic save/relaunch passed |
| Remote | Home PC form, automatic startup and prelaunch checks, five-second timeout, direct Rebirth tile; Moonlight 1080p60/20 Mb/s/HDR off; TCP reachability is not labelled stream quality |
| Xbox | Official Xbox Cloud library link; no purchase or Wine-based Microsoft Store promise |
| Controller | Keyboard search, Return/details, Escape/back, favorite/filter, and immediate target switching verified; local Rebirth input and mouse-click/reconnect sequence owner-confirmed with current configuration; first connection after launch and physical hub navigation still open |
| Diagnostics | Correlation IDs and private durable journal capped at 200 events; bounded reads, atomic writes, and unreadable-snapshot preservation; non-Steam identifiers are hashed; export excludes raw runtime logs, bookmarks, credentials, filesystem paths and network addresses |
| Build | Full Debug build; 75 synthetic tests pass; SwiftLint zero errors, nine inherited warnings |

Home now includes Continue Playing, Favourites, Recently Played, Recently Added, Final Fantasy,
Retro, and Ready on Home PC collections (empty collections are omitted). Containers
remain available under Management. Artwork contrast and fallback images were
visually checked; release notes remain dismissed after restarting. Debug game IDs
no longer crowd game cards. Recently Added uses persistent first-seen catalog dates; rescans and preference edits preserve ordering. Existing entries are dated when first observed by this version, not by an invented historical install date.

Windows discovery reads secondary libraries within explicitly supplied drive roots.
The runtime currently supplies its authorized C drive. Other drives are reported
as unmapped until separately configured; no external filesystem mapping was added.
Fixtures cover duplicate preference, malformed/oversized library lists, unmapped
paths, traversal, and symlink escape. The real Rebirth installation remains visible.

Controller details now show destination, availability, controller connection, profile
acceptance and requested resolution. Menu/S opens the selected profile's advanced
settings; B/Menu closes the sheet without operating the library behind it. Keyboard
opening/closing and local/Home PC detail switching were verified in the installed
app. Physical controller shortcuts remain a live test. Save-location discovery and
per-game controller compatibility metadata are still incomplete. Legacy catalog
refreshes now update title/artwork without resetting preferences or first-seen dates.

## External/live gates still open

1. **Yoda:** paired, with Desktop and Steam applications visible. After an initial
   disconnect and control-channel retry failure, a Desktop stream recovered and
   displayed Rebirth gameplay at approximately 60 FPS. The owner accepted gameplay
   and controller support. See `remote-lan-validation.md` for measured samples.
   Direct Rebirth launch and automatic selection of the game display are verified.
   Formal ten-minute active-gameplay stability and external direct-tunnel
   measurement remain open. Restricted SSH administration was separately approved.
2. **UI — access restored:** Home artwork, collections, release-note persistence,
   keyboard search/details/back, favorite/filter, and live target-label updates passed.
   A local Rebirth launch through the keyboard-controlled hub used the accepted
   profile; Steam recorded 1920×1080 launch arguments and the owner located the game
   on the Mac's other monitor. The original favorite state and Home PC preference
   were restored after testing. Physical hub controller browsing remains open.
3. **Content:** the real Deck shortcut inventory is imported and the direct central
   ROM/BIOS copy is running with checksums and hourly notifications. Dolphin 2606a
   is installed as a native Apple Silicon application; its signature and actual CLI
   were checked. The hub supports ISO/GCM/RVZ/WIA/WBFS/CISO discovery and Dolphin
   fullscreen launch with optional Metal/native or Metal/3× presets. Emulator app
   version detection and executable validation are tested. Melee launches from the hub
   at Metal 3× (1920×1584 internal), about 60 FPS at its initial prompt. The owner subsequently confirmed Xbox controller gameplay and both reconnect
   sequences, including after mouse interaction. After game-data creation, normal exit and a fresh hub launch preserved the GCI
   save and bypassed the creation prompt; basic save/relaunch passed. PS2 gameplay, firmware setup for other emulators, and a native Mac Steam title
   launch remain open. PCSX2 v2.8.2 recognizes the copied owner BIOS and boots it
   using Metal on the M3 Pro at 3× native resolution. Both emulator sources are
   saved in Game Hub; Dolphin controller gameplay is owner-confirmed, while PCSX2
   controller gameplay remains unverified.
   See `emulator-readiness.md`.
4. **App updater — resolved:** owner explicitly approved manual fork updates on
   2026-09-13. Sparkle initialization and update requests are disabled by default for
   this fork, and the menu/settings explain manual app and security updates.
   Existing runtime pins and engine controls are unchanged.

## Remaining product refinements from the complete handoff

The current delivery keeps legacy Epic/local operations as adapters and stores their
records in SQLite. Direct/relay
telemetry, complete remote/controller acceptance, emulator BIOS/version detection,
ROM artwork editing and fuller game details require follow-up. Unknown or unavailable targets must
remain labelled honestly. Do not describe this delivery as every handoff phase complete.

## Source references

- [Moonlight official release](https://github.com/moonlight-stream/moonlight-qt/releases/tag/v6.1.0)
- [Moonlight command parser](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/cli/commandlineparser.cpp)
- [PCSX2 command line](https://pcsx2.net/docs/advanced/cli/)
- [RetroArch command line](https://docs.libretro.com/guides/cli-intro/)
- [Runtime provenance and historical tests](free-runtime-validation.md)
- [Original supplied handoff](game-hub-vscode-engineering-handoff.md)

## Current ROM storage requirement

Owner requires NAS-only ROMs, with no local ROM copies. The 1.13 GB local
Melee test image was removed after matching its hash against a fresh NAS read;
its save remains intact. Future testing must use a mounted NAS source. An authenticated read-only SMB trial now exposes the verified Melee path
through a dedicated no-login account. Direct NAS launch reached the main menu
using the existing save; the owner confirmed NAS gameplay works great. Existing verified ROM read
access is extended; the tested future-file permission update is active after the
verified batch-boundary handover. PS2 NAS source setup is saved. See `emulator-readiness.md` for measured network observations.

DuckStation and RetroArch are installed as native Apple Silicon engines. PS1 BIOS
Metal boot and RetroArch Vulkan startup passed; four native cores load successfully.
NAS archive/format integration and new-system gameplay checks remain open. See
`emulator-readiness.md` for exact versions, firmware provenance and limitations.

Latest emulator integration: installed code `eca3a002` adds PBP, V64, Sega
cartridge formats and validated GDI track sets. Full build/signature verification
and 75 tests pass. Melee, Hulk and Gundam are indexed from NAS sources. Gundam's
hub launch and Hulk's direct emulator boot passed. New-system physical gameplay
and PS2 memory-card setup remain open; ROMs have not been staged locally.

Installed code is now `376b845c`: visible ROM source folders and throttled scan
progress, with the full build and all 75 tests passing. Prior app/source-index
recovery copies are retained privately. New UI visual acceptance remains pending
because native desktop control is unavailable in this session. The owner is
testing Hulk with Xbox connected; PS2 card formatting/write is confirmed in logs
and by its filesystem signature. Do not mark gameplay accepted until feedback.

The owner has now accepted Hulk controller operation, but not NAS playback
performance. Live latency spikes are common to the Mac's router, NAS and Yoda
paths; the NAS-to-router sample remains fast. Network isolation testing is in
progress. See `emulator-readiness.md`; do not describe PS2 performance as accepted.

Follow-up network testing did not reproduce severe stalls with Xbox connected,
including a 45-second Hulk-running sample (NAS ping 12.90 ms average, 106.25 ms
maximum, all 90 replies). Intermittent spikes remain; the cause is unresolved.
Owner playback feedback is pending, so PS2 performance is not marked accepted.

The owner subsequently accepted the follow-up Hulk NAS gameplay session as
“great”; Xbox controls were already accepted. PS2 gameplay acceptance is now
recorded for this session. Earlier intermittent network stalls remain unexplained;
no permanent network fix is claimed. PS2 saved-game reload remains unverified.

Owner direction: defer save-state/reload testing and continue emulator coverage.
SNES/Super Mario World is now running directly from the NAS in native RetroArch
bsnes-hd beta, with Xbox port 1 detected. Gameplay feedback and the SNES Game Hub
source bookmark remain pending. The pilot transfer preserves the original ZIP
and does not alter or stop the main copy worker.

SNES gameplay and left-stick convenience are owner-confirmed. N64 testing is
now active with Super Mario 64 from the NAS, native Mupen64Plus-Next, Apple M3
Pro GLCore and Xbox port 1. N64 gameplay acceptance and both RetroArch source
bookmarks remain open; save-reload testing stays deferred by owner direction.


Current emulator follow-up: N64 Vulkan gameplay is owner-accepted. The controller
is an owner-confirmed Flydigi Apex 5 using an Xbox-compatible Bluetooth identity;
rear-paddle configuration is deferred. Mega Drive Sonic 2 now passes a native
PicoDrive/Vulkan screenshot check directly from the NAS, with core-only
left-stick movement enabled. Gameplay acceptance remains pending. SNES, N64
and Sega Game Hub source bookmarks are still outstanding; save-reload testing
remains deferred.


Latest: owner accepted Sonic 2 gameplay. SNES, N64 and Genesis sources are now
saved and indexed (one title each), with all prior sources preserved. Hub visual
and Play checks remain pending. Power Stone is copying directly to NAS for the
Dreamcast pilot; Flycast settings are prepared but game boot remains unverified.


Owner priorities: finish PS1 and PS3, with Switch high priority. PS1 gameplay
is accepted. Native RPCS3 is installed with 4.91; Sony 4.93 downloaded/verified
and the upgrade dialog is pending. PS3 Spider-Man pilot is copying on NAS.
Ryubing is installed with verified owner firmware; Sonic Mania is on NAS and
its first launch initializes Vulkan/controller/firmware, but visible gameplay
and hub integration remain unverified. See emulator-readiness.md for details.


Current follow-up: RPCS3 4.93 firmware installation is verified. PS3 game transfer
continues. Switch's normal GUI launch reaches Sonic Mania's title screen;
explicit Apex 5 assignment and owner-requested A/B swap are saved. Final Switch
gameplay acceptance remains pending. Installed revision 972281d4 adds Switch
format discovery and GUI launch; 76 tests/build/signature checks passed.
