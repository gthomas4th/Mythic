# Game Hub delivery and acceptance

The Mac implementation and live verification are still in progress. The complete original
project acceptance is **not yet closed**. Owner authorization permits continuing all
routine implementation, builds and clean commits; it does not turn missing tests
into passes.

## Installed candidate

Authoritative local app: `~/Applications/Game Hub.app`.
Built from source revision `11e3cfa8133a0e65e499d3355cdccb3d65a3c953` on
`feat/steam-native`. Xcode performed the local ad-hoc signing; the installed copy
passes `codesign --verify --deep --strict`. This is not a notarized public release.
The original app and runtime are preserved. Development builds and the test host
are not the user entry point. Do not remove recovery copies before final live acceptance.

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
| Launch integration | Main library Play resolves native/Windows targets and uses official Steam `-applaunch`; Home PC tile-to-game verified; local Wine tile verification still open |
| Catalog | SQLite schema version 2, deterministic provider identities, target merge/resolver, favorite/recent/preference persistence; reopening covered by tests |
| Legacy data | Epic/local records now persist in SQLite after a one-way import; original defaults and schema-1 backup are retained; existing launch/install APIs remain intact |
| Profiles | Validation, export/import, clone, selection and revision rollback; original profile remains available |
| Deck | Device-scoped shortcut references remain offline-readable; imported commands are never executed |
| ROMs | Folder/application/core bookmarks, incremental content hashes, cue/m3u grouping, missing-part/traversal/cycle checks; no user ROMs available yet |
| Remote | Home PC form, automatic startup and prelaunch checks, five-second timeout, direct Rebirth tile; Moonlight 1080p60/20 Mb/s/HDR off; TCP reachability is not labelled stream quality |
| Xbox | Official Xbox Cloud library link; no purchase or Wine-based Microsoft Store promise |
| Controller | Optional library with directional navigation, details/Play, favorite/filter and target switching; controller hardware check still open |
| Diagnostics | Correlation IDs and bounded in-session events; export excludes raw runtime logs, bookmarks, credentials, filesystem paths and network addresses |
| Build | Full Debug build; 59 synthetic tests pass; SwiftLint zero errors, nine inherited warnings |

The latest small Home-screen changes use available portrait artwork when a banner is
missing and persist release-note dismissal. Build/signing/lint passed; their final
visual check is pending because Computer Use began returning `cgWindowNotFound`
for both Game Hub and Finder. The installed app process remains running.

## External/live gates still open

1. **Yoda:** paired, with Desktop and Steam applications visible. After an initial
   disconnect and control-channel retry failure, a Desktop stream recovered and
   displayed Rebirth gameplay at approximately 60 FPS. The owner accepted gameplay
   and controller support. See `remote-lan-validation.md` for measured samples.
   Direct Rebirth launch and automatic selection of the game display are verified.
   Formal ten-minute active-gameplay stability and external direct-tunnel
   measurement remain open. Restricted SSH administration was separately approved.
2. **UI — access restored:** on 2026-09-13 the installed app opened successfully.
   Rebirth's library tile and accepted-profile badge were observed, and Settings →
   Updates displayed the approved manual app/security-update policy. The prior
   `cgWindowNotFound` capture failure is no longer blocking this check. Remote tile-to-game launch passed. Local tile-to-game launch and hub controller
   browsing acceptance remain open.
3. **Content:** no installed native Mac Steam title, copied Deck inventory, central
   ROMs or configured BIOS/firmware were supplied. Emulator launch/graphics tuning
   can only be validated after content and an installed emulator are selected.
4. **App updater — resolved:** owner explicitly approved manual fork updates on
   2026-09-13. Sparkle initialization and update requests are disabled by default for
   this fork, and the menu/settings explain manual app and security updates.
   Existing runtime pins and engine controls are unchanged.

## Remaining product refinements from the complete handoff

The current delivery keeps legacy Epic/local operations as adapters and stores their
records in SQLite. Direct/relay
telemetry, complete remote/controller acceptance, emulator BIOS/version detection,
and ROM artwork editing require follow-up. Unknown or unavailable targets must
remain labelled honestly. Do not describe this delivery as every handoff phase complete.

## Source references

- [Moonlight official release](https://github.com/moonlight-stream/moonlight-qt/releases/tag/v6.1.0)
- [Moonlight command parser](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/cli/commandlineparser.cpp)
- [PCSX2 command line](https://pcsx2.net/docs/advanced/cli/)
- [RetroArch command line](https://docs.libretro.com/guides/cli-intro/)
- [Runtime provenance and historical tests](free-runtime-validation.md)
- [Original supplied handoff](game-hub-vscode-engineering-handoff.md)
