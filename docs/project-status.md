# Game Hub delivery and acceptance

The Mac implementation is ready for final live verification. The complete original
project acceptance is **not yet closed**. Owner authorization permits continuing all
routine implementation, builds and clean commits; it does not turn missing tests
into passes.

## Installed candidate

Authoritative local app: `~/Applications/Game Hub.app`.
Built from source revision `4fb7b4d211274ea46a4abe2b402e22d36451a867` on
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
| Launch integration | Main library Play resolves native/Windows targets and uses official Steam `-applaunch`; final on-screen tile test still open |
| Catalog | SQLite schema version 1, deterministic provider identities, target merge/resolver, favorite/recent/preference persistence; reopening covered by tests |
| Legacy data | Epic/local metadata importer backs up the defaults blob and leaves existing launch/install APIs intact; no destructive migration |
| Profiles | Validation, export/import, clone, selection and revision rollback; original profile remains available |
| Deck | Device-scoped shortcut references remain offline-readable; imported commands are never executed |
| ROMs | Folder/application/core bookmarks, incremental content hashes, cue/m3u grouping, missing-part/traversal/cycle checks; no user ROMs available yet |
| Remote | Home PC form, five-second streaming-port check, documented Moonlight 1080p60/20 Mb/s invocation; successful TCP connection is not labelled good streaming |
| Xbox | Official Xbox Cloud library link; no purchase or Wine-based Microsoft Store promise |
| Controller | Optional library with directional navigation, details/Play, favorite/filter and target switching; controller hardware check still open |
| Diagnostics | Correlation IDs and bounded in-session events; export excludes raw runtime logs, bookmarks, credentials, filesystem paths and network addresses |
| Build | Full Debug build; 54 synthetic tests pass; SwiftLint zero errors, nine inherited warnings |

## External/live gates still open

1. **Yoda:** owner supplied its name and powered it on. Neither `yoda` nor
   `yoda.local` resolved from this Mac, and local streaming service discovery found
   no host. Tailscale is stopped. Await its IPv4 address and Sunshine installation
   status; do not infer absence of Sunshine from failed name resolution. Moonlight
   6.1.0 is installed from its official GitHub release and passes notarization/signature
   checks. Pairing, a ten-minute LAN test, external direct-tunnel measurement and
   per-game remote mapping remain unverified live. No network policy was changed.
2. **UI — access restored:** on 2026-09-13 the installed app opened successfully.
   Rebirth's library tile and accepted-profile badge were observed, and Settings →
   Updates displayed the approved manual app/security-update policy. The prior
   `cgWindowNotFound` capture failure is no longer blocking this check. A full
   tile-to-game launch and controller hardware acceptance remain open.
3. **Content:** no installed native Mac Steam title, copied Deck inventory, central
   ROMs or configured BIOS/firmware were supplied. Emulator launch/graphics tuning
   can only be validated after content and an installed emulator are selected.
4. **App updater — resolved:** owner explicitly approved manual fork updates on
   2026-09-13. Sparkle initialization and update requests are disabled by default for
   this fork, and the menu/settings explain manual app and security updates.
   Existing runtime pins and engine controls are unchanged.

## Remaining product refinements from the complete handoff

The current delivery keeps legacy Epic/local operations as adapters; it is not a
full replacement of their persistence. Direct/relay
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
