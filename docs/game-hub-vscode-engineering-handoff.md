# Unified Mac Game Hub — VS Code/Codex Engineering Handoff

Status: Ready to execute  
Prepared: 2026-09-13  
Working title: **GameDeck** (placeholder only; do not spend time branding yet)  
Foundation candidate: [Mythic](https://github.com/MythicApp/Mythic), GPL-3.0

## 1. Mission

Build a controller-friendly native macOS game hub that presents one library and one consistent launch experience across:

1. Steam — primary source and backbone of the user's catalog.
2. Epic Games — authenticated, legitimate Epic ownership and installs.
3. Retro games purchased on Steam — treated as Steam games, not ROMs.
4. User-owned ROMs and disc images — launched through emulators.
5. Xbox — cloud play on the Mac and Windows/Xbox PC games streamed from the home gaming PC.
6. Native Mac games and manually imported games.
7. The user's home gaming PC — Sunshine host, Moonlight client, and a secure remote tunnel.

The UI must hide launch plumbing. A title can expose several launch targets, but the primary action is always **Play**. The app selects the best available target or lets the user override it.

This project must not bypass storefront authentication, DRM, anti-cheat, licensing, or console security. It must never download ROMs, BIOS files, cracks, or proprietary runtimes from unofficial sources.

## 2. Product decisions already made

- The app is not a Steam-branded product. Steam is the most important provider.
- Fork Mythic instead of rebuilding Wine/GPTK and Epic integration from zero.
- Final Fantasy is the initial compatibility target, especially FFVII Remake Intergrade and FFVII Rebirth. FFXV is explicitly out of scope.
- FFVII Remake/Rebirth PC copies must remain tied to the storefront where they are owned: Steam or Epic.
- Retro releases owned on Steam remain first-class Steam entries.
- ROM-based emulation is an additional provider, not a substitute for Steam purchases.
- Anti-cheat-incompatible games must be marked honestly and offered through Remote PC or Xbox Cloud when possible.
- Remote PC streaming through Sunshine/Moonlight is a core launch strategy, not a later accessory.
- The app should favor a known-good pinned configuration over automatically updating a working game's runtime.
- Move quickly through vertical slices. Do not attempt a complete rebrand or full UI rewrite before the first games launch.

## 3. What the current Mythic repository actually contains

Baseline inspected from upstream `main` at commit:

```text
754223978e61fb6efcff1e3152ae426bad0020b7
2026-02-12
Reorganized Help menu and replaced Buttons with Links
```

Important findings:

- SwiftUI macOS app, Swift 6, macOS 14 deployment target.
- Existing Windows runtime/container code is under `Mythic/Utilities/Engine` and `Mythic/Utilities/Wine`.
- Epic is implemented through bundled Legendary integration.
- The new model hierarchy is in `Mythic/Utilities/Game`.
- `SteamGame.swift` is only a deprecated placeholder; it does not constitute Steam support.
- `Game.Storefront` currently contains only `.epicGames` and `.local`.
- `GameDataStore` persists polymorphic games in `UserDefaults` and contains a TODO for SwiftData.
- `GameDataStore.refreshFromStorefronts()` only refreshes Epic.
- There is no test target in the current tree.
- The repository README still marks Steam support incomplete.

Do not treat upstream Steam support as implemented. Build ours behind clean provider and launch-strategy boundaries.

## 4. Non-negotiable engineering rules

1. Inspect before modifying. Record the exact upstream commit and local toolchain.
2. Do not delete user game files, Wine containers, Steam libraries, emulator saves, ROMs, or existing Mythic data.
3. Never use a user's live Steam library as a destructive test fixture.
4. Store tokens, API keys, and credentials in Keychain. Never place them in source, `UserDefaults`, logs, fixtures, or commits.
5. Do not expose the Sunshine management interface to the public Internet.
6. Do not automatically create router port forwards. Prefer a private point-to-point overlay tunnel.
7. Never auto-update the runtime assigned to a game known to work.
8. Keep the upstream remote so Mythic changes can be reviewed and merged selectively.
9. Keep GPL-3.0 license and upstream notices. If distributed, the modified application and corresponding source must comply with GPL-3.0.
10. Make small commits at accepted milestones. Do not mix rebranding, architecture, and compatibility fixes in one commit.
11. Add tests with every parser, catalog merge rule, launch-target resolver, and profile migration.
12. Ask the user only when credentials, physical access, a storefront login, or a destructive operation is required. Continue all unblocked work first.

## 5. Definition of the first usable MVP

The MVP is complete when all of these are true on the user's Mac:

- The fork builds and runs without changing the upstream runtime behavior.
- The app discovers installed native Mac Steam games from local Steam manifests.
- Steam titles appear in the same library as existing Epic/local titles.
- A native Steam game launches from its tile.
- A Windows Steam environment can install/sign in to Steam once.
- At least one Windows Steam game can be installed or recognized and launched through that environment.
- One Final Fantasy PC title has a persisted, pinned compatibility profile.
- A Remote PC entry reports whether the Sunshine host is reachable.
- The app can launch Moonlight for the home PC.
- LAN streaming is measured and recorded before remote-tunnel tuning.
- The project has automated tests for VDF parsing, identity/merge logic, and launch-target selection.
- No secrets are committed and no existing user library is modified unexpectedly.

The first vertical slice should be: **discover installed native Steam games → render one in the existing library → launch it**.

## 6. Target architecture

Do not add more storefront conditionals to SwiftUI views. Introduce provider-neutral domain objects and launch strategies.

### 6.1 Core domain

Suggested types (names may adapt to project conventions):

```swift
struct GameIdentity: Hashable, Codable {
    let provider: ProviderID
    let externalID: String
}

struct GameRecord: Identifiable, Codable {
    let id: GameIdentity
    var title: String
    var artwork: ArtworkSet
    var metadata: GameMetadata
    var launchTargets: [LaunchTarget]
    var preferredTargetID: UUID?
    var favorite: Bool
    var lastPlayed: Date?
}

enum ProviderID: String, Codable {
    case steam
    case epic
    case emulator
    case xboxCloud
    case remotePC
    case local
}

enum LaunchKind: Codable {
    case nativeMac
    case wineSteam
    case wineEpic
    case emulator
    case moonlight
    case webCloud
}

struct LaunchTarget: Identifiable, Codable {
    let id: UUID
    var kind: LaunchKind
    var availability: Availability
    var installation: InstallationStatus
    var compatibility: CompatibilityStatus
    var profileID: String?
    var locator: LaunchLocator
}
```

Identity rules:

- Steam: `steam:<appid>`.
- Epic: `epic:<catalog-or-app-id>` from Legendary.
- Emulator: `emulator:<system>:<content-hash>`; path is not identity.
- Xbox Cloud: `xbox-cloud:<stable-catalog-id>` when available.
- Remote PC application: `remote:<host-id>:<sunshine-app-id>`.
- Never deduplicate solely by title.
- Cross-store title grouping is presentation metadata added later. Preserve every provider identity.

### 6.2 Provider protocol

```swift
protocol GameProvider: Sendable {
    var id: ProviderID { get }
    func discoverInstalled() async throws -> [GameRecord]
    func refreshOwnedLibrary() async throws -> [GameRecord]
    func capabilities() async -> ProviderCapabilities
}
```

Initial adapters:

- `SteamNativeProvider`
- `SteamWindowsProvider`
- `EpicProvider` wrapping existing Legendary code
- `LocalProvider` wrapping the existing local manager
- `EmulatorProvider`
- `RemotePCProvider`
- `XboxCloudProvider`

Providers discover and normalize catalog data. They do not render UI and should not directly decide global launch preference.

### 6.3 Launch strategy protocol

```swift
protocol LaunchStrategy: Sendable {
    var kind: LaunchKind { get }
    func preflight(_ target: LaunchTarget) async -> PreflightResult
    func launch(_ target: LaunchTarget) async throws -> LaunchSession
    func stop(_ session: LaunchSession) async throws
}
```

Strategies:

- `NativeMacLaunchStrategy`
- `SteamURLLaunchStrategy`
- `WineSteamLaunchStrategy`
- `LegendaryLaunchStrategy`
- `WineEpicLauncherStrategy` only for titles that truly require the Epic launcher
- `EmulatorLaunchStrategy`
- `MoonlightLaunchStrategy`
- `XboxCloudLaunchStrategy`

Each preflight returns actionable reasons such as runtime missing, Steam signed out, ROM unavailable, BIOS missing, Sunshine offline, tunnel relayed, or controller unavailable.

### 6.4 Persistence

Do not expand the current `UserDefaults` game blob into the permanent catalog database.

Sequence:

1. Keep existing Mythic storage intact during the first Steam discovery slice.
2. Add a versioned `CatalogStore` abstraction.
3. Implement SwiftData or a versioned SQLite-backed store for the unified catalog on macOS 14+.
4. Add a one-way, idempotent importer for current Epic/local `UserDefaults` data.
5. Keep compatibility profiles in human-readable versioned JSON files, with user overrides separate from bundled defaults.
6. Store filesystem access as security-scoped bookmarks, not raw assumptions about permanent access.
7. Back up the pre-migration data before the first migration. Never delete it automatically.

## 7. Execution phases

### Phase 0 — Environment and baseline (start immediately)

Tasks:

1. Collect without modifying:

```bash
sw_vers
uname -m
system_profiler SPHardwareDataType SPDisplaysDataType
xcodebuild -version
xcode-select -p
git --version
```

2. Check whether Steam, Moonlight, Tailscale, RetroArch, PCSX2, RPCS3, and Epic-related data already exist. Record paths; do not install yet.
3. Fork/clone Mythic. Keep:

```text
origin   = our fork
upstream = https://github.com/MythicApp/Mythic.git
```

4. Record the chosen upstream commit in `docs/upstream-baseline.md`.
5. Run `xcodebuild -list`, resolve packages, and build the current app before editing.
6. Launch the unmodified Debug app and record baseline behavior/screenshots/errors.
7. Run a secret scan over tracked files. Pay special attention to the included Firebase plist and any inherited configuration.
8. Create `docs/discovery-report.md` containing Mac chip, memory, GPU, macOS version, Xcode version, installed clients/emulators, Steam paths, and unresolved blockers.

Acceptance:

- Reproducible baseline build, or an exact error with command/output and a narrow remediation.
- No source changes mixed into the baseline commit.

### Phase 1 — Steam-native vertical slice

Implement local installed-game discovery without requiring a Steam API key.

1. Locate standard and configured Steam libraries beginning with:

```text
~/Library/Application Support/Steam/steamapps/libraryfolders.vdf
```

2. Build a real Valve KeyValues/VDF parser. Do not use brittle regex for nested VDF.
3. Parse `libraryfolders.vdf`, then each `steamapps/appmanifest_<appid>.acf`.
4. Extract at minimum app ID, name, install directory, state flags, last update, and library root.
5. Determine installed native Mac availability conservatively. Do not label a Windows-only payload native just because a manifest exists.
6. Create `SteamNativeProvider` and map results into provider-neutral records.
7. Launch installed games through `steam://rungameid/<appid>` using `NSWorkspace`.
8. For uninstalled native titles added later, use the Steam client install path rather than implementing Steam content download.
9. Use Steam-hosted artwork when available, cache it responsibly, and show a clean fallback.
10. Add fixture-based tests for VDF edge cases, multiple library roots, malformed files, partial installs, duplicates, and missing artwork.

Acceptance:

- Installed native games from every configured Steam library appear.
- Selecting Play opens the correct app ID in the native Steam client.
- Missing/broken manifests generate a nonfatal diagnostic.
- No Steam credentials are needed for installed discovery.

Commit: `feat(steam): discover and launch installed native games`

### Phase 2 — Unified catalog and launch resolution

1. Add the provider-neutral catalog types and `CatalogStore`.
2. Adapt existing Epic and local Mythic records into the new catalog without removing old code.
3. Add deterministic merge rules based on provider identity.
4. Allow multiple launch targets for a title while retaining every storefront record.
5. Implement preference resolution in this order by default:

```text
Installed native Mac
Known-good local Wine target
Healthy Remote PC target
Xbox Cloud target
Unavailable/unsupported with explanation
```

This order is user-configurable per game. For demanding games, the user can set Remote PC as preferred even when local Wine works.

6. Add badges for source, installed state, compatibility, and remote availability.
7. Keep the existing UI largely intact. Replace data flow, not all visuals.

Acceptance:

- Steam, Epic, and local entries share one grid/list.
- Two games with the same title but different provider IDs do not overwrite one another.
- A game with local and remote targets can choose either.
- Launch resolution is fully unit tested.

Commit: `feat(catalog): add provider-neutral library and launch targets`

### Phase 3 — Windows Steam and pinned profiles

Use one primary Windows Steam container first. Do not install a full copy of Steam for every game.

1. Add `SteamWindowsProvider` and `WineSteamLaunchStrategy`.
2. Create or select a dedicated Steam Wine container through Mythic's current Engine/Wine APIs.
3. Install the official Windows Steam client into that container.
4. The user performs the interactive Steam login and Steam Guard flow. Never automate or store the password.
5. Discover Windows-Steam installs by parsing manifests inside the selected container/library.
6. Launch with the official Steam client (`-applaunch <appid>` or the verified equivalent), preserving authentication, updates, cloud saves, and DRM behavior.
7. Keep a single login/shared content library while applying per-game environment variables and renderer/runtime profiles.
8. Add opt-in isolated containers only for games proven to conflict with the shared container.

Compatibility profile schema should include:

```json
{
  "schemaVersion": 1,
  "profileID": "steam-<appid>-default",
  "gameID": "steam:<appid>",
  "runtime": {
    "engineID": "mythic-engine",
    "version": "pinned-version",
    "updatePolicy": "manual"
  },
  "renderer": "d3dmetal",
  "windowsVersion": "win10",
  "environment": {},
  "arguments": [],
  "knownIssues": [],
  "validation": {
    "status": "untested",
    "lastTestedAt": null,
    "macFingerprint": null
  }
}
```

9. Implement profile export, import, clone, validate, and rollback.
10. Updating the app or engine must not silently migrate a verified profile.

Final Fantasy validation order:

1. FFVII Remake Intergrade.
2. FFVII Rebirth.
3. Other user-owned, non-anti-cheat Final Fantasy PC titles.
4. Explicitly skip FFXV.

For each validated game, record:

- Storefront and app/catalog ID.
- Exact Mac hardware and OS.
- Engine/runtime version.
- Renderer and relevant toggles.
- Resolution, frame cap, HDR state, controller type.
- Launch result, gameplay duration tested, visual/audio issues, crash logs, and rollback point.

Acceptance:

- Windows Steam signs in once in the shared container.
- A Windows Steam title launches from the hub.
- FFVII Remake has a saved profile and rollback path.
- Changing a test profile does not mutate the verified profile.

Commit: `feat(steam): launch Windows games with pinned profiles`

### Phase 4 — Sunshine/Moonlight Remote PC as a first-class target

#### 4A. Establish a clean LAN baseline

Do not troubleshoot the tunnel until LAN streaming is measured. Otherwise local encoder or Wi-Fi problems will be misdiagnosed as tunnel problems.

Host PC checklist:

- Windows 10/11, current stable GPU driver, and current stable Sunshine.
- Gaming PC connected to the router/switch by Ethernet.
- Sunshine service starts reliably after reboot.
- Sunshine web UI credentials are configured.
- Pair Moonlight while Mac and PC are on the home LAN.
- Start with Sunshine's Desktop and Steam entries; add individual games later.
- Confirm the correct GPU encoder is selected.
- Confirm controller forwarding on the host.

Mac checklist:

- Current stable Moonlight client.
- Prefer wired Ethernet for the diagnostic; otherwise strong 5/6 GHz Wi-Fi.
- Disable conflicting VPN exit-node routing during the LAN baseline.
- Start at 1080p60, 20 Mbps, H.264; then test HEVC. Add HDR, 120 Hz, 1440p, or 4K only after the baseline is clean.
- Enable Moonlight performance statistics and capture screenshots/results.

Record:

- Host encode latency.
- Network latency and jitter.
- Client decode/render latency.
- Dropped network frames and dropped decode frames.
- Whether stutter is periodic, input-related, audio-related, or continuous.
- Display refresh rate and whether the stream frame rate matches it.

Initial quality gates:

- No sustained packet loss.
- Dropped frames below 1% during a ten-minute test.
- Stable frame pacing at 1080p60.
- Hardware encoding on the PC and hardware decoding on the Mac.
- Controller, audio, keyboard, and mouse behave correctly.

#### 4B. Create the private remote tunnel

Preferred MVP: Tailscale installed directly on the gaming PC and Mac.

Reasons: it creates a WireGuard-based private path, does NAT traversal, avoids exposing Sunshine management, and is quick to validate. It is acceptable only when the peer connection becomes direct.

Procedure:

1. Install/sign in on Mac and PC.
2. Pair Sunshine/Moonlight on LAN first.
3. From each end, run `tailscale status` and `tailscale ping <peer>`.
4. Confirm the final path reports direct, not DERP/relay.
5. Add the gaming PC's Tailscale IP or MagicDNS name to Moonlight.
6. Test from a genuinely external network, not the home Wi-Fi.
7. Do not use a Tailscale exit node for the stream.
8. If the path remains relayed, treat that as a blocker; do not tune bitrate around a relay.

Fallback only if direct Tailscale cannot be established:

- Investigate CGNAT/double NAT/firewall behavior.
- Prefer a direct WireGuard endpoint on the home gateway or a narrowly scoped overlay design.
- Manual Sunshine/GameStream port forwarding is last choice and requires explicit user approval and a security review.

#### 4C. Diagnose in the right order

Use this decision tree:

1. Bad on LAN and remote: fix host encoding, GPU/display capture, client decoding, or local Wi-Fi first.
2. Good on LAN, bad remotely, tunnel relayed: fix NAT traversal/direct tunnel.
3. Good on LAN, direct tunnel, high RTT/jitter: the remote network path is the limit.
4. Good latency but artifacts: lower bitrate/resolution or test HEVC/AV1 according to host/client support.
5. Stable video but poor input: test controller transport, Bluetooth interference, and client input settings.
6. Periodic stutter with low network loss: inspect refresh mismatch, host FPS pacing, V-Sync, and hardware scheduling.

Use `iperf3` between Mac and PC over LAN and over the tunnel when available. Record TCP throughput and UDP loss/jitter, but do not install or alter router services without approval.

#### 4D. Integrate with the hub

Add `RemoteHost` and `RemotePCProvider`:

```swift
struct RemoteHost: Identifiable, Codable {
    let id: UUID
    var name: String
    var lanAddress: String?
    var tunnelAddress: String?
    var preferredAddress: AddressPreference
    var wakeStrategy: WakeStrategy?
    var lastHealth: RemoteHealth?
}
```

Preflight should report:

- Moonlight installed.
- Host reachable.
- Sunshine streaming service reachable.
- LAN or tunnel path selected.
- For Tailscale, direct vs relay when the local CLI makes that observable.
- Measured RTT and a quality label.

Launching:

- Verify Moonlight's current supported command-line/URL interface before coding against it.
- Prefer a stable, documented invocation.
- Initially launch the Sunshine Steam/Big Picture entry or Desktop.
- Later map individual catalog records to Sunshine applications.
- Never log pairing secrets or tunnel credentials.

UI behavior:

- A game tile can show `On this Mac` and `Home PC` targets.
- A demanding title may default to Home PC.
- Show a small status such as `Home PC · Direct · 24 ms`.
- If the tunnel is relayed, show `Remote path relayed — streaming not recommended` with diagnostics.
- Provide a `Test connection` action that does not launch a game.

Future, not MVP:

- Wake-on-LAN through a narrowly scoped helper on the home network. Normal overlay tunnels do not carry broadcast magic packets by default.
- Automatic import of Sunshine's complete application list.
- Per-network bitrate presets.
- Seamless resume and cloud-save reconciliation.

Acceptance:

- Ten-minute 1080p60 LAN test passes quality gates.
- External test uses a direct encrypted peer path.
- The hub reports reachability and path quality accurately.
- The hub launches Moonlight to the intended host/application.
- Remote PC can be set as a per-game preferred target.

Commit: `feat(remote): add Sunshine Moonlight launch targets and diagnostics`

### Phase 5 — Epic integration

1. Retain Mythic's Legendary-backed Epic support and adapt it to the provider protocol.
2. Preserve Epic account authentication, entitlements, updates, DLC handling, and cloud-save behavior supported by Legendary.
3. Do not require the full Epic Games Launcher when Legendary can legitimately install and launch the owned game.
4. Add `WineEpicLauncherStrategy` only for a game that technically requires the official launcher.
5. Never bypass Epic authentication or DRM.
6. Test FFVII Remake/Rebirth through Epic only if that is where the user owns them.

Acceptance:

- Existing Epic library behavior is not regressed.
- Epic and Steam copies remain distinct records/targets.
- The user's owned Final Fantasy title launches through its actual provider.

Commit: `refactor(epic): adapt Legendary to unified provider model`

### Phase 6 — Emulation

Supported first wave:

- RetroArch for appropriate cartridge-era systems.
- DuckStation for PS1 where a dedicated core gives a cleaner experience.
- PCSX2 for PS2.
- RPCS3 for PS3.

Implementation:

1. Let the user select one or more ROM roots with macOS folder pickers.
2. Persist security-scoped bookmarks.
3. Scan incrementally; do not hash entire huge images on every launch.
4. Normalize cue/bin sets and multi-disc games into one record where safe.
5. Use a content fingerprint plus system ID for stable identity.
6. Build explicit emulator adapters with version detection and argument generation.
7. Validate required user-supplied BIOS/firmware without offering downloads.
8. Keep saves and emulator configuration outside the catalog database; record their locations.
9. Support manual artwork correction and metadata matching.
10. Keep Steam retro releases under Steam even if an emulated release shares the same title.

Acceptance:

- At least one game launches successfully through each installed target emulator selected for the first wave.
- Missing emulator/BIOS/content errors are clear and non-destructive.
- Rescanning does not duplicate unchanged titles.
- Multi-disc handling has fixture tests.

Commit: `feat(emulation): add ROM discovery and emulator adapters`

### Phase 7 — Xbox

Treat Xbox as two distinct capabilities:

1. `XboxCloudProvider`: open supported cloud titles using the official Xbox Cloud Gaming web experience on Mac.
2. Windows Xbox/Game Pass PC titles: launch on the home gaming PC through the Remote PC target.

Do not attempt to install Microsoft Store/Game Pass PC packages inside Wine. Do not promise a native macOS Xbox PC launcher.

Implementation:

- Provide a provider entry and authenticated web launch path.
- Use stable per-game cloud links only when verified; otherwise open the official library page.
- Allow a catalog title to map to a Sunshine app or Desktop/Steam-style remote session on the Windows PC.
- Xbox console Remote Play may be investigated separately; it is not part of the first Mac MVP.

Acceptance:

- Xbox Cloud opens the correct official experience.
- A Windows Game Pass game can be represented as a Home PC launch target without pretending it runs locally.

Commit: `feat(xbox): add cloud and remote-PC launch paths`

### Phase 8 — Console-style UI and controller navigation

Only begin the large visual pass after Steam-native, Windows Steam, and Remote PC vertical slices work.

Required experience:

- Home: Continue Playing, Favorites, Recently Added, Final Fantasy, Retro, Remote-ready.
- Library: search, filters, sort, installed-only, provider, local/remote availability.
- Details: Play, target selector, install state, controller, compatibility, graphics profile, save location.
- Full keyboard/controller navigation with visible focus and no mouse-only controls.
- Fast image loading, disk cache limits, graceful offline artwork.
- No exposure of Wine/container terminology on the primary path.
- Advanced panel exposes runtime, renderer, environment, logs, validation, and rollback.

Acceptance:

- Entire primary flow works with a controller: launch app, browse, search/filter reasonably, open details, select target, play, return.
- App remains usable with no network.
- Large libraries scroll smoothly.

## 8. Owned-but-uninstalled Steam catalog

Installed discovery is local and credential-free. The complete owned catalog is a separate capability.

Implement in this order:

1. Installed manifests — MVP.
2. Reliable locally cached ownership data, if present and verified — optional optimization, never the sole source of truth.
3. Optional Steam account connection through an official supported API flow.

If a Steam Web API key is required:

- Explain why.
- Store it in Keychain.
- Never log or commit it.
- Handle private profiles and API failures without breaking installed discovery.
- Cache only necessary catalog metadata.

Do not scrape credentials, browser cookies, or Steam Guard tokens.

## 9. Compatibility and update safety

Separate these version streams:

- App version.
- Mythic upstream commit.
- Engine/Wine runtime version.
- D3DMetal/DXVK/DXMT component versions.
- Emulator versions.
- Per-game compatibility profile version.

Rules:

- A verified game stays on its pinned runtime until the user chooses to test an upgrade.
- Upgrade tests clone the profile and preserve the prior runtime/profile.
- A successful test requires launch plus a useful gameplay window, not only reaching a menu.
- Rollback must be one action and must not delete saves.
- Catalog migrations are versioned and tested with old fixtures.
- Back up profile metadata before migration.

Compatibility states:

```text
Unknown
Testing
Verified Excellent
Verified Playable
Degraded
Broken
Unsupported — anti-cheat
Remote Only
Cloud Only
```

## 10. Security and privacy

- Store secrets in macOS Keychain.
- Use security-scoped bookmarks for user-selected folders.
- Sanitize logs before export.
- Redact account names, tokens, Steam IDs if the user marks them private, home public IPs, and tunnel details.
- Do not bundle the user's compatibility profiles with private filesystem paths when sharing.
- Validate downloaded runtime hashes/signatures where the upstream provides them.
- Sunshine management stays LAN/tunnel-only.
- Pairing is interactive and user-approved.
- No automatic firewall, router, or port-forward changes.
- Add a diagnostics export that includes versions and timings but excludes credentials.

## 11. Tests and CI

Create a macOS unit-test target immediately.

Minimum test suites:

- `ValveKeyValuesParserTests`
- `SteamManifestDiscoveryTests`
- `GameIdentityTests`
- `CatalogMergeTests`
- `LaunchResolverTests`
- `CompatibilityProfileMigrationTests`
- `SecurityScopedBookmarkTests`
- `RemoteHealthClassifierTests`
- `EmulatorCommandBuilderTests`

Use temporary directories and synthetic fixtures. Never copy the user's real manifests into the repository without redaction.

CI gates:

- Debug build.
- Unit tests.
- SwiftLint if already configured.
- Secret scan.
- GPL/license notice check.
- No network-dependent tests in the normal unit suite.

## 12. Observability and support bundle

Add structured categories:

- Catalog
- SteamNative
- SteamWindows
- Epic
- WineRuntime
- Emulator
- RemotePC
- LaunchResolver
- Migration

Every launch attempt should have a local correlation ID and record:

- Selected target.
- Preflight result.
- Runtime/profile version.
- Process start/exit state.
- Sanitized error.

Never record credentials, command lines containing tokens, or full private paths by default.

Support bundle should include sanitized logs, app/runtime versions, profile IDs, Mac hardware summary, and remote latency classification.

## 13. Suggested repository layout

Adapt names to Xcode conventions, but preserve boundaries:

```text
Mythic/
  Domain/
    GameIdentity.swift
    GameRecord.swift
    LaunchTarget.swift
    CompatibilityProfile.swift
  Catalog/
    CatalogStore.swift
    CatalogMergeEngine.swift
    LaunchResolver.swift
  Providers/
    SteamNative/
    SteamWindows/
    Epic/
    Local/
    Emulation/
    RemotePC/
    XboxCloud/
  LaunchStrategies/
  Infrastructure/
    Keychain/
    VDF/
    Networking/
    FileAccess/
  Views/
  LegacyAdapters/
Tests/
  Fixtures/
docs/
  upstream-baseline.md
  discovery-report.md
  architecture-decisions/
  compatibility/
```

Do not mechanically move all upstream files on day one. Add new boundaries around working code, then migrate deliberately.

## 14. Architecture decision records to create

- ADR-001: Fork Mythic and retain GPL-3.0 obligations.
- ADR-002: Provider-neutral catalog and multiple launch targets.
- ADR-003: Shared Windows Steam container with per-game profiles.
- ADR-004: Version-pinned runtimes and explicit upgrade/rollback.
- ADR-005: Tailscale direct tunnel for Remote PC MVP.
- ADR-006: SwiftData/SQLite catalog instead of expanding UserDefaults.
- ADR-007: Legendary-backed Epic integration with official-launcher exception.
- ADR-008: Xbox Cloud/Remote only; no Wine-based Microsoft Store promise.

## 15. Fast milestone order

| Milestone | Expected focused effort | Demonstration |
|---|---:|---|
| Baseline | 1–2 hours | Upstream builds and discovery report exists |
| Steam-native slice | 4–8 hours | Installed Mac Steam game appears and launches |
| Unified catalog | 4–8 hours | Steam + Epic + local render together |
| Windows Steam | 1–2 focused days | Windows Steam title launches from shared container |
| Final Fantasy profile | 0.5–1 day per difficult title | Verified profile plus rollback |
| Remote PC baseline/integration | 1 focused day, excluding network blockers | Direct LAN/remote measurements and Moonlight launch |
| Emulation first wave | 1–2 focused days | Selected systems launch from one library |
| Xbox paths | 0.5–1 day | Cloud and Remote PC targets work |
| Controller/UI polish | Iterative | Console-style primary experience |

These are engineering estimates, not promises. Hardware, storefront authentication, game downloads, and network path issues can extend validation.

## 16. Stop conditions requiring user input

Pause only the affected task when:

- Steam/Epic/Tailscale/Xbox interactive login is required.
- Steam Guard or 2FA is required.
- A macOS permission dialog requires the user.
- Router/firewall/port-forward changes appear necessary.
- A destructive data migration or deletion is proposed.
- The correct ROM/BIOS folder must be selected.
- The user's Mac hardware is insufficient for a requested local target and a product decision is needed.

Continue all unrelated implementation while waiting.

## 17. First instruction to give VS Code/Codex

Copy everything below into the engineering agent after placing this document in the repository:

---

You are the implementation engineer for the Unified Mac Game Hub. Read `game-hub-vscode-engineering-handoff.md` completely before changing anything.

Work autonomously and quickly, but preserve user data. Start with Phase 0 and the Phase 1 Steam-native vertical slice. Do not begin a full rebrand or large UI redesign. Do not delete or relocate any live Steam games, Mythic containers, emulator content, or saves. Never store credentials in source or logs.

Required first actions:

1. Inspect the repository, git state, remotes, current branch, Xcode schemes, build settings, and relevant `AGENTS.md` files.
2. Confirm or establish the Mythic upstream baseline and record the exact commit.
3. Create `docs/upstream-baseline.md` and `docs/discovery-report.md`.
4. Build the unmodified project and report the exact result.
5. Create a unit-test target if none exists.
6. Implement a tested Valve KeyValues parser.
7. Implement installed native Steam library discovery across every configured library root.
8. Add provider-neutral Steam records with stable `steam:<appid>` identities.
9. Display discovered Steam titles in the existing library UI with minimal visual change.
10. Launch a native installed Steam game through its app ID.

Use a feature branch and make a focused commit only after tests and the build pass. If blocked by a user login, permission prompt, unavailable Mac hardware detail, or a potentially destructive action, state the exact blocker and continue every unblocked task. Do not claim success without showing the build/test command and summarized result.

At the end of the first pass, report:

- Files changed.
- Build and test results.
- What can be demonstrated now.
- Any user action required.
- The next smallest vertical slice.

---

## 18. Source anchors

- Mythic upstream repository and license: https://github.com/MythicApp/Mythic
- Apple Game Porting Toolkit: https://developer.apple.com/games/game-porting-toolkit/
- Moonlight setup and Internet streaming guidance: https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- Sunshine documentation: https://docs.lizardbyte.dev/projects/sunshine/
