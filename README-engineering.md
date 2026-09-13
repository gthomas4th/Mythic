# Game Hub engineering checkout

A native macOS game hub built on Mythic, retaining GPL-3.0 and upstream notices.
Work continues on `feat/steam-native`; no rebrand or large UI rewrite is underway.

The Debug app builds and opens successfully. Installed native Steam discovery and
launch integration are implemented. The local Steam libraries currently contain no
installed manifests, so a real game launch remains pending an installed Mac title.
Native-only onboarding avoids requiring Windows components for Steam discovery.
Verified engine installation and Wine registry readback are implemented; the current
core suite has 41 passing tests. Windows Steam setup is in progress; an [isolated free Wine candidate](docs/free-runtime-validation.md)
has initialized Steam's UI after the bundled runtime failed.
Library → Steam Deck imports a copied shortcut list and keeps unavailable references
visible offline. See the [transfer guide](docs/steam-deck-transfer-guide.md) and
[hardware tuning requirements](docs/performance-validation.md).

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$(xcrun --show-sdk-path)"
xcrun swift test --package-path Packages/GameHubCore
python3 scripts/verify-debug-build.py --package-cache <existing-SourcePackages-directory>
```

Build logs stay in ignored `.build-local`. Debug Firebase initialization and symbol
upload are disabled; Release behavior still needs review before distribution.

See [discovery and acceptance status](docs/discovery-report.md),
[upstream baseline](docs/upstream-baseline.md), and
[Steam Deck ROM plan](docs/steam-deck-rom-shortcuts.md).
The [original handoff](docs/game-hub-vscode-engineering-handoff.md) is retained as
project reference; owner decisions and current acceptance evidence take precedence.
