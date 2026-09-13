# Upstream baseline

- Upstream: https://github.com/MythicApp/Mythic.git
- Revision: `754223978e61fb6efcff1e3152ae426bad0020b7` (2026-02-12).
- Subject: Reorganized Help menu and replaced Buttons with Links.
- Origin: https://github.com/gthomas4th/Mythic.git; upstream remote preserved.
- Feature branch: `feat/steam-native`; GPL-3.0 and source notices retained.

## Toolchain and historical result

macOS 26.6.2 (25G83), arm64; Xcode 26.6 (17F113), Git 2.54.0.
Use Xcode explicitly through `DEVELOPER_DIR` and its matching `SDKROOT`; the system
Command Line Tools selection was not changed. `lean-ctx` was unavailable locally.

Automatic approval review rejected the untouched upstream build because its
Crashlytics phase uploads symbols/build events. A disposable baseline with only that
phase removed reproduced Swift 6 actor-isolation errors in Epic install/uninstall
and metadata entry points. No unmodified build or launch success is claimed.

Package resolution initially stalled. Eleven binary artifacts fetched from the
package-declared URLs matched declared SHA-256 checksums and populated the cache.
No dependency versions or checksum validation were changed. Dependency pins are
tracked. Apple's Metal Toolchain 17F109 was installed through Xcode's downloader.

## Approved repairs and current result

The owner approved the [Epic concurrency repair](architecture-decisions/epic-concurrency-decision.md)
and [Debug Firebase policy](architecture-decisions/development-telemetry-decision.md).
The actual checkout now builds successfully with full Swift 6 checks. A subsequent
[startup timer repair](startup-crash-fix.md) resolves the observed Sparkle queue trap;
the Debug app opens and remains on its setup screen.

`python3 scripts/verify-debug-build.py` is the current build entry point. It builds
the actual checkout, retains local logs, and never launches the app. Historical
no-upload source copies are not authoritative implementations.

## Inherited configuration audit

A bounded text pattern scan inspected 276 upstream tracked files up to 2 MB. Its only
Google API-key-shaped finding was inherited Firebase client configuration in
`Mythic/GoogleService-Info.plist`; the value is not reproduced. Server restrictions
were not verified. Binary payloads and unknown secret formats were not covered.
Debug does not initialize Firebase or invoke its symbol uploader. Release privacy
and distribution review remains outstanding.
