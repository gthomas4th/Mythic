# Game Hub engineering checkout

Native macOS game hub based on Mythic, retaining GPL-3.0 and upstream notices.
Authoritative source: this checkout, branch `feat/steam-native` on the owner's fork.
See [current delivery and acceptance status](docs/project-status.md).

Implemented: native and Windows Steam discovery in the existing library, pinned
Windows launch profiles, SQLite catalog/preferences, profile import/export/clone/
rollback/selection, safe Deck references, ROM indexing and emulator adapters,
Moonlight launch/connection controls, official Xbox Cloud entry, controller library,
and sanitized diagnostic export. Epic and local launchers retain their existing APIs.

Rebirth is installed and the owner accepts its 1080p gameplay at approximately
40 FPS on this M3 Pro. The accepted free runtime is preserved; a 720p test override
was ineffective and is not the accepted profile. No paid runtime is required.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$(xcrun --show-sdk-path)"
xcrun swift test --package-path Packages/GameHubCore
python3 scripts/verify-debug-build.py --package-cache <existing-SourcePackages-directory>
```

72 core tests pass. The full Debug build passes; lint has no errors and nine
inherited warnings. Generated apps, private runtime bindings, logs, account data and
save backups are excluded from Git. Runtime bindings and profiles are stored under
Application Support/GameHub on this Mac. Debug telemetry remains disabled.

This is a local Debug delivery, not a notarized public release. Yoda streaming and local Rebirth gameplay have owner acceptance.
ROM gameplay/BIOS validation, native Steam tile launch and full controller acceptance
remain open. Dolphin is installed locally, with GameCube image discovery and
selectable Metal launch presets implemented. These checks
are explicitly open, not replaced by synthetic tests.
