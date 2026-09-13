# Game Hub discovery and acceptance status

Status: Debug builds and runs; native Steam integration is implemented. Real game
launch validation is pending because the configured Steam libraries are empty.

| Check | Result |
|---|---|
| Mac | MacBook Pro Mac15,6; M3 Pro, 11 CPU / 14 GPU cores; 18 GB memory |
| Toolchain | macOS 26.6.2; Xcode 26.6; Metal Toolchain 17F109 |
| Installed clients | Steam, Steam Link, Tailscale |
| Steam discovery | 0 installed manifests, 0 native records, 0 diagnostics |
| Other clients | Moonlight, RetroArch, PCSX2 and RPCS3 not found in standard locations |
| Tests | 24 synthetic XCTest tests pass |
| Debug | Full build passes; Firebase upload skipped; setup screen remains open |
| Data | No game installs, moves, deletions, logins or legacy catalog migration |

## Implemented boundaries

- Bounded recursive Valve KeyValues parser and modern/legacy library discovery.
- Stable `steam:<appid>` identities, deterministic deduplication and sanitized diagnostics.
- Conservative native payload evidence: matching application name, complete manifest,
  supported Mach-O architecture, bounded search and no escaping symlinks.
- Native Steam URL launches, cached client artwork and icon fallback.
- Steam records overlay the existing Epic/local library without expanding its defaults
  blob. Favorites and recent state survive refresh, but not restart until Phase 2.
- Unsupported file-management controls are disabled for Steam.
- Contained Epic actor-boundary and startup-timer repairs; Debug Firebase disabled.

## Verification

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$(xcrun --show-sdk-path)"
xcrun swift test --package-path Packages/GameHubCore
python3 scripts/verify-debug-build.py --package-cache <existing-SourcePackages-directory>
plutil -lint Mythic.xcodeproj/project.pbxproj
git diff --check
```

Tests use temporary synthetic fixtures, no network or live library writes. The same
core source files compile into the app. Tests cover VDF, manifest/native evidence,
identity and actor-bound work/metadata. They do not replace live storefront validation.

## Remaining acceptance

- Install an owned native Mac game through Steam, then demonstrate tile → Play.
- Complete Windows setup and interactive storefront login when that slice is ready.
- Validate Steam Deck shortcut inventory using the owner's exported file.
- Unified catalog persistence/resolution, pinned profiles, Windows Steam, Remote PC,
  emulation launching, Xbox and controller navigation remain subsequent milestones.
- Unknown native layouts are deliberately excluded; executable evidence is not a
  gameplay compatibility claim. Release telemetry/distribution remains unreviewed.
