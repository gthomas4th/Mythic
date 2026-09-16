# Game Hub development brief for ChatGPT

Use this document as factual engineering context for future Game Hub work. It describes
what was actually implemented and validated. It is not permission to perform destructive,
credential, network, storage, or publication actions. When an older planning document or
historical status entry conflicts with this brief, inspect the current source and
`docs/project-status.md`; the installed-revision receipt is the final authority for the
locally deployed build.

## 1. Current product and delivery state

Game Hub is a controller-oriented native macOS launcher that combines Steam, Epic,
remote-PC games, PS5 Remote Play, local applications, and a NAS-backed ROM library in one
interface. It began as a fork of Mythic because Mythic already supplied a native SwiftUI
shell, Legendary-based Epic support, Wine/container management, and engine installation.
The project extended that foundation rather than reimplementing those systems.

The authoritative checkout is:

- Repository: `https://github.com/gthomas4th/Mythic.git`
- Branch: `feat/steam-native`
- Upstream baseline: Mythic commit `754223978e61fb6efcff1e3152ae426bad0020b7`
- Installed source revision: `c0797e9ece4b51b704d2508cedf08639fc787a54`
- Installed app: `~/Applications/Game Hub.app`
- Secondary installed copy: `/Applications/Game Hub.app`
- Build type: local Debug build with an ad-hoc signature
- Distribution status: locally installed and accepted; not notarized or packaged as a
  public release

The owner-facing name, executable, menu title, and Dock label are **Game Hub**. The Swift
module remains `Mythic`, and the bundle identifier remains `xyz.blackxfiied.Mythic` so the
existing Mythic library, settings, containers, and saves continue to resolve. New catalog,
runtime-binding, remote-host, and ROM-source state is stored under the established private
Application Support locations, principally `Application Support/GameHub`; credentials and
bookmarks remain outside Git.

The source keeps the upstream GPL-3.0 license and notices. Any distributed derivative must
continue to satisfy GPL-3.0 source obligations.

## 2. Development environment

The accepted build was developed and tested on:

- MacBook Pro `Mac15,6`
- Apple M3 Pro, 11 CPU cores and 14 GPU cores
- 18 GB unified memory
- arm64
- macOS 26.6.2
- Xcode 26.6 / Swift 6
- Metal Toolchain 17F109
- Deployment target: macOS 14 or newer

Builds explicitly select `/Applications/Xcode.app/Contents/Developer` because the system
Command Line Tools directory does not contain the full Xcode build environment.

The normal validation commands are:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$(xcrun --show-sdk-path)"
xcrun swift test --package-path Packages/GameHubCore
python3 scripts/verify-debug-build.py --local-sign
codesign --verify --deep --strict "$HOME/Applications/Game Hub.app"
```

`scripts/verify-debug-build.py` builds the checked-out Xcode project, retains the complete
log under `.build-local`, does not launch the app, and can ad-hoc sign the local Debug
candidate. Generated builds, runtime bindings, local paths, account data, saves, and
private logs are ignored by Git.

## 3. Architectural changes from Mythic

The original Mythic app treated Epic/local games as the primary model and had no complete
Steam provider, durable unified catalog, emulator provider, or remote-launch strategy.
Game Hub introduced a provider-neutral core in `Packages/GameHubCore` and bridged it into
the existing app models so the established Epic and Wine behavior could be retained.

The core package contains:

- Stable provider identities such as `steam:<appid>` rather than title-only identity.
- Native and Windows Steam manifest discovery.
- A bounded Valve KeyValues parser.
- Deterministic catalog merge and launch-target resolution.
- SQLite catalog/preferences storage with schema migration and rollback protection.
- Compatibility profiles and pinned runtime bindings.
- Steam Deck shortcut parsing with device-scoped identity and command non-execution.
- ROM indexing, multipart-disc grouping, emulator command construction, and safe local
  ROM-download boundaries.
- Remote-host validation and sanitized launch diagnostics.
- Bounded artifact hashing and Wine registry parsing.

The app retains the existing `Game` subclasses and storefront managers where appropriate,
but unified display data is generated from a cached merged catalog. Epic and local records
were imported into SQLite without deleting the legacy data. Favorites, recently played,
first-seen dates, preferred launch targets, and display edits survive refresh and restart.
Provider identities are preserved even when two stores have similarly named games.

Security boundaries are explicit. Parsers are bounded; path traversal, symlink escape,
oversized metadata, malformed descriptors, unknown architectures, and incomplete emulator
bundles are rejected. Diagnostics use correlation IDs, cap the durable journal at 200
events, hash non-Steam identifiers, and omit raw bookmarks, credentials, network addresses,
runtime logs, and filesystem paths from exports.

## 4. Unified library behavior

The library can contain:

- Native Mac Steam games discovered from local Steam manifests.
- Windows Steam games discovered inside authorized Wine drive roots.
- Epic titles discovered through Mythic's bundled Legendary integration.
- Local/manual games supported by the original application.
- ROM and disc-image entries indexed from security-scoped source folders.
- Connection entries for Yoda and PS5 Remote Play.

Every game exposes a location badge and, when known, a library-type badge. Examples are
`Server + ROM`, `Local + Steam`, `PC + Epic`, and `PS5 + Remote Play`. ROM cards also show
the official system mark without repeating the system name inside the tag.

The Play model is intentionally simple:

- Cards never offer Install.
- Play routes through the selected available location.
- Steam can retain multiple launch targets and a preferred target.
- Epic titles hosted on Yoda launch the exact mapped Sunshine application through
  Moonlight.
- PS5 Remote Play launches chiaki-ng.
- Server ROMs launch directly from the mounted read-only NAS share.
- Only ROMs offer **Download locally**, and only after the owner explicitly chooses it.
  That path copies all referenced parts, verifies SHA-256, keeps the server original, and
  removes partial output after error or cancellation.

The main Library has always-visible system and alphabet filters, search, grid/list support,
and a Quick Play row for Yoda and PS5. Connections have their own system filter. Hacks,
homebrew, translations, unreleased builds, and similar material are grouped in a separate
sidebar category and hidden from Home and the normal Library. Title cleanup removes ROM-set
brackets, country/language tags, revision metadata, Switch dump counters such as
`(1G+1U+1D)`, and normalizes trailing articles such as `Addams Family, The`. Duplicate
versions prefer extracted launchable media and the highest identifiable revision.

## 5. Steam and local Windows gaming

Native Steam discovery validates manifests and payloads conservatively. A candidate Mac
application must match its manifest, contain a supported Mach-O architecture, and remain
inside the authorized library root. Windows Steam discovery reads the primary library and
mapped secondary libraries only within explicit drive roots. Unmapped Windows libraries
are reported rather than guessed.

Final Fantasy VII Rebirth is the main local compatibility target:

- Steam app ID: `2909400`
- Installed size observed: 171.06 GB
- Runtime: WS12WineSikarugir10.0_6 / Wine 10
- Renderer: D3DMetal 3.0
- Accepted profile: `steam-2909400-accepted`
- Runtime binding: `sikarugir-10-d3dmetal-3`
- Displayed game resolution: 1920 × 1080
- Owner-observed performance: about 40 FPS, steady and accepted
- Update policy: pinned/manual; a working runtime is not silently replaced

The runtime and renderer artifacts came from official Sikarugir/Wrapper releases and were
verified by SHA-256 before extraction. The local binding hashes 4,755 runtime/renderer
files and verifies pinned content away from the UI thread before launch. The Wine prefix,
runtime, private bookmarks, Steam account state, saves, and test logs are outside source
control. The initial validation used a copied Steam container and a development-only
AppKit host before the runtime was connected to production launching.

The accepted controller workaround is also preserved. Connecting the controller before
launch is verified. After a Rebirth-only Steam Input override and a normal relaunch, the
owner confirmed the mouse-click/disconnect/reconnect sequence worked. This remains
observational acceptance; repeated reconnect behavior and first connection after launching
without a controller are not guaranteed by the app.

## 6. Epic games and Yoda

Epic ownership and metadata continue to use Legendary. Epic games that are unavailable on
the Mac but mapped on the home gaming PC are treated as playable from location `PC`.
Fortnite add-on entitlements are filtered so the library shows the primary game rather than
many duplicate Fortnite products.

Yoda is the home Windows gaming PC. Moonlight 6.1.0 is paired with Sunshine on Yoda. The
accepted client profile is:

- 1920 × 1080
- 60 FPS target
- 20 Mb/s
- H.264
- HDR off
- VideoToolbox hardware decoding and Metal rendering on the Mac

Game Hub performs a short reachability check, launches a new Moonlight application instance
so command arguments are not lost to an already-running process, and sends the exact saved
Sunshine application name. A direct Sunshine entry for Rebirth uses Steam's official
`-applaunch 2909400` route. Sunshine captures the verified gaming display by stable device
ID; the display topology is restored after streaming. The owner accepted Rebirth gameplay
and controller support at approximately 60 FPS. Observed network latency was generally
1–4 ms on LAN with no measured network drops in the accepted samples; a formal ten-minute
active-gameplay run and away-from-home measurement remain open.

Fortnite, Fall Guys, and FFVII Remake were mapped individually. Managed PowerShell wrappers
send the exact Epic launch URI, leave the authenticated Epic launcher running, and minimize
it to the system tray rather than killing or restarting it. FFVII Remake can use its direct
game executable. This avoided the credential breakage caused by restarting Epic between
sessions. The final Fortnite stream opens on the captured 4K gaming display and appears
edge to edge in Moonlight.

Yoda administration uses a dedicated key-only SSH path restricted to this Mac's LAN source,
the Windows Private firewall profile, `sshd`, and TCP 22. Agent and TCP forwarding are
disabled. Router port forwarding was not added. Host-specific keys and receipts are private
and untracked.

## 7. PS5 Remote Play

Sony's official Remote Play client was retained for comparison, but chiaki-ng is the
permanent Game Hub route because it was substantially more playable in owner testing.

The accepted chiaki-ng profile is:

- chiaki-ng 1.10.0 ARM build
- H.264
- 1080p60
- 10 Mb/s
- HDR off
- Fast rendering
- VSync on
- large aspect-fit window; letterboxing is accepted to preserve the PS5 image
- `--exit-app-on-stream-exit` for normal cleanup

Game Hub includes a normal Close action and a guarded recovery path for chiaki sessions that
refuse to terminate. The recovery waits five seconds, then checks PID executable paths and
bundle identity before terminating only remaining chiaki processes. A stuck PS5 Remote Play
service once required restarting the PS5. The owner accepted the final client behavior with
minor persistent delay/stutter. Away-from-home play is intended but has not been measured in
an external-network acceptance session.

PS5 Remote Play and Yoda are first-class searchable Library entries with their own artwork,
badges, Details screens, Quick Play buttons, and Play actions. Their artwork is deliberately
free of card boxes: Yoda uses a circular portrait crop and PS5 uses a transparent official
mark.

## 8. ROM storage and emulator integration

The active design is NAS-first. ROMs are not silently cached on the Mac. The central library
is exposed through a dedicated read-only SMB account whose credential is stored in macOS
Keychain. Security-scoped bookmarks retain user-approved access to the share and emulator
applications. Saves, memory cards, shader caches, and emulator configuration remain local.
The ROM share denies writes; transfer internals, BIOS repositories, and incomplete files are
outside the share.

The source scanner uses incremental signatures, bounded reads, atomic index updates, and
visible throttled progress. It groups multipart CUE/M3U/GDI layouts, validates referenced
tracks, rejects cycles and paths outside the selected root, and uses content/layout identity
instead of filenames alone. The implementation recognizes the formats required by the
configured systems, including GameCube/Wii GCM, ISO, RVZ, WIA, WBFS and CISO; PlayStation
PBP; N64 V64; Sega GEN/MD/SMD/32X; Dreamcast GDI track sets; playlists; and supported ZIP
entries. Extracted images are preferred over archive duplicates.

Configured emulator adapters are:

| System group | Engine and accepted setup |
|---|---|
| GameCube/Wii | Dolphin 2606a, native Apple Silicon, Metal, selectable native or 3× preset |
| PlayStation 2 | PCSX2 2.8.2, Intel build through Rosetta, Metal 3× |
| PlayStation | DuckStation 0.1-11894, universal/arm64, Metal 4× and PGXP starting preset |
| SNES | RetroArch 1.22.2 with ARM64 bsnes-hd beta 10.6 |
| Nintendo 64 | RetroArch with Mupen64Plus-Next 2.8 Vulkan |
| Sega/32X | RetroArch with PicoDrive 2.05 |
| Dreamcast | RetroArch with Flycast and owner firmware |
| Switch | Ryujinx-compatible adapter, currently using the installed Ryubing/Ryujinx application and owner firmware |
| PlayStation 3 | RPCS3 adapter and installed firmware; gameplay acceptance is still pending |

Game Hub launches managed emulator sessions in fullscreen. Escape or the configured
controller exit gesture closes the managed session and returns to Game Hub without leaving
the emulator running. Emulator application metadata and executable paths are validated
without launching the app. Game Hub does not overwrite controller maps, firmware, saves, or
global emulator graphics settings unless a tested session-specific argument is available.

Owner-accepted gameplay covers GameCube, PS1, PS2, SNES, N64, Sega Mega Drive, Dreamcast,
and Switch. Representative titles include Super Smash Bros. Melee, Gundam Battle Assault 2,
Hulk, Super Mario World, Super Mario 64, Sonic 2, Power Stone, and Sonic Mania. PS3 gameplay,
some save/reload coverage, and Flydigi Apex 5 rear-paddle customization remain outside the
accepted set. The owner specifically declined local ROM caching as a network-lag workaround;
a future portable USB favorite set is deferred.

## 9. User interface and controller customization

The original Mythic interface was substantially replaced for the owner-facing flow.
The current design is an LCARS-inspired console interface rather than a standard macOS
storefront:

- Visual Studio-style charcoal canvas (`#1e1e1e`).
- Dark blue structural rails and dividers.
- Light blue/grey supporting surfaces.
- Green, yellow, and red status highlights.
- Purple Options/accent controls.
- Bundled Final Frontier display typeface with larger readable body text.
- Official console marks for GameCube, Nintendo 64, Nintendo Switch, PlayStation,
  PlayStation 2, Dreamcast, and Sega.
- A native Icon Composer `Mythic.icon` bundle and original controller/navigation portal
  artwork, which fills the macOS Dock icon mask correctly without a second grey frame.

The app opens at the full usable size of the active display. Home provides Continue Playing,
Recently Played, Recently Added, Final Fantasy, Retro, and other populated collections while
omitting empty sections. The Library uses exposed artwork without card background tiles,
keeps Play as a blue capsule and Options as a purple capsule, and centers primary page
headings. The Containers navigation item is hidden from owner-facing navigation while the
underlying container data remains available to the runtime.

Controller navigation is app-wide:

- D-pad or left stick: move selection.
- A: Play or activate the selected control.
- B: Back through Details, content, and sidebar.
- X: Options; in the editor it can delete.
- Y: context action such as favorite, filter, save, or moving/still artwork.
- Menu: enter or re-enter the sidebar.

Visible colored button icons appear beside the actions they trigger. Home, Library, sidebar,
Details, and editing all participate in the same focus model. The on-screen editor uses a
normal QWERTY keyboard with Shift, symbols, Space, Backspace, and Clear. Escape uses the same
back route and no longer indexes a cleared options array during dismissal.

## 10. Artwork and cinematic Details screens

Artwork is treated as part of the product rather than decoration. Box-art resolution uses
local caches and exact title normalization. Libretro thumbnail repositories supply retro
box art and gameplay snapshots. Switch uses exact curated Nintendo CDN URLs for the seven
installed titles, with TitleDB as the bounded fallback for future titles. Steam Details
queries the official Steam app-details endpoint for screenshots and HLS/MP4 trailer media.
Epic uses Legendary storefront key art.

The final rendering rules are:

- Images are never stretched out of proportion.
- Native 16:9 scenes fill the Details canvas with aspect-fill cropping.
- 4:3 and portrait scenes remain fully visible over a blurred/softened copy of the same
  image, preventing distorted retro pixels and awkward empty space.
- A cover is displayed immediately while remote landscape art loads.
- Loading or failed remote art leaves a designed LCARS background rather than a blank blue
  panel or an error card.
- Wide-only storefront art receives a contained card composition instead of disappearing.
- Steam trailer video is muted, loops, prefers 720p and 2.5 Mb/s, and uniformly overscans
  enough to avoid a one-frame uncovered edge while AVPlayer prepares HLS output.
- Non-video ROM/Epic scenes use a restrained 18-second GPU-backed drift. Reduce Motion and
  the Details Still image control disable it.
- Video pauses while editing, launching, or inactive and releases its player when Details
  closes.

The active Switch scene cache contains seven unique, title-verified 16:9 images. The old
cache that incorrectly assigned one unrelated image to several titles was removed from the
active path and archived privately. The final visual acceptance covered Home, Epic cards,
007: Agent Under Fire, Sonic Mania, Fortnite, Final Fantasy VII Rebirth, Gundam Battle
Assault 2, PS5 Remote Play, and Yoda.

Local image decoding happens asynchronously through a bounded `NSCache` with a 160-image,
approximately 192 MB cost limit. This prevents the original full-library decode behavior
from slowing the entire Mac.

## 11. Performance work

The most serious UI stall came from resolving NAS bookmarks and volume metadata repeatedly
while SwiftUI rendered location badges. That work was moved off the main thread and cached
per source. Startup no longer asks the NAS about every ROM. Catalog paths remain stable and
the current source root is resolved only when needed, especially at launch.

Additional optimizations include:

- generation-cached merged library data;
- batched preference reads and inserts;
- one library snapshot for Home collections;
- one filter/sort pass per render;
- asynchronous bounded image decoding;
- coalesced Switch index lookup instead of repeated 86 MB downloads;
- utility-task emulator version inspection;
- static placeholders rather than perpetual shimmer animation;
- throttled scan progress and atomic source replacement.

Measured development evidence:

- 100 cached catalog reads: approximately 6.11 ms in the final installed regression,
  compared with 556.67 ms before the caching/batch work.
- First cold Switch cover: 1.87 seconds, compared with 9.74 seconds before optimization.
- Post-install idle spot check: 0.0% CPU, about 248 MB resident memory, and no open network
  sockets.
- Live interaction sampling after optimization found no ROM bookmark/location resolution
  stacks during Library click/scroll activity.

These measurements are scoped development samples, not universal benchmarks.

## 12. Swift package and external dependencies

The Xcode target directly declares these Swift packages:

| Package | Resolved state | Role inherited or used by Game Hub |
|---|---:|---|
| SwiftyJSON | 5.0.2 | Existing JSON handling, including Legendary metadata |
| Sparkle | 2.9.6 | Upstream updater framework; automatic fork updates are disabled by default |
| SemanticVersion | 0.5.3 | Version comparison |
| Glur | `main` at the resolved revision | Blur rendering used by the inherited UI |
| ColorfulX | 2.6.2 | Existing visual/color support |
| SwiftUI-Shimmer | 1.5.1 | Existing loading UI; perpetual artwork shimmer was removed from the main flow |
| SwordRPC | resolved `master` revision | Upstream Discord RPC integration |
| WhatsNewKit | 2.2.1 | Upstream release notes |
| Firebase iOS SDK | 11.15.0 | Upstream analytics/crash products; Debug initialization and upload are disabled |
| swift-markdown-ui | 2.4.1 | Help/release-note Markdown UI |
| DockProgress | 5.1.0 | Existing Dock progress integration |

`Package.resolved` also pins transitive Google/Firebase, gRPC, protobuf, Markdown, Socket,
and image-loading dependencies. Do not hand-edit transitive versions; update and verify the
resolved graph as a unit. `GameHubCore` itself has no third-party package dependency and
uses Foundation, CryptoKit, SQLite, AppKit-facing bridges, and XCTest.

Operational dependencies are separate from Swift packages: Steam, Legendary/Epic,
Sikarugir Wine, D3DMetal, Moonlight, Sunshine, chiaki-ng, the configured emulator apps,
macOS Keychain, security-scoped bookmarks, and the NAS SMB share. Game Hub must continue to
degrade honestly when any of these is missing or unreachable.

## 13. Testing and acceptance

The final `GameHubCore` suite contains 83 passing XCTest cases. Test groups cover:

- catalog persistence, schema migration, profile clone/import/rollback, and preferences;
- Valve KeyValues and Steam manifest parsing;
- native Mac payload/architecture evidence;
- Windows library mapping, duplicate preference, traversal, and symlink escape;
- Steam Deck shortcut bounds, Unicode, truncation, and device-scoped identity;
- emulator arguments, app-bundle validation, ROM grouping, title normalization, and
  rename-stable identity;
- safe ROM local-download behavior, multipart copies, hashes, cancellation, and rollback;
- engine artifact hashes;
- Legendary operation boundaries and install metadata;
- private launch-event journal behavior;
- Wine registry parsing.

The app also contains Debug-only native regressions:

- `--test-controller-navigation` exercises sidebar entry, Home/Library movement, direct A
  launch interception, X Details, B/Escape dismissal, QWERTY editing, invalid artwork URL
  rejection, all six Details rows, and 100 catalog reads. The final installed run reported
  `passed: true`, no failures, and 6.11 ms for 100 catalog reads.
- `--render-game-cards` renders representative populated SwiftUI cards through
  `NSHostingView` into `/private/tmp` for layout inspection.

Final build evidence:

- Full Xcode Debug build passed with Swift 6 checks.
- 83/83 core tests passed.
- Both installed app copies passed `codesign --verify --deep --strict`.
- Installed controller/navigation regression passed with zero failures.
- Live UX checks covered Home, Library, search/filtering, controller routes, Details/back,
  Game Sources, PC & PS5, Accounts, Epic cards, ROM art, connection art, and Steam video.
- Physical gameplay was owner-accepted for local Rebirth, Yoda streaming, chiaki-ng, and
  the emulator systems listed above.

Synthetic tests deliberately avoid real account writes, ROM modification, destructive
library operations, and gameplay claims. Live owner acceptance is recorded separately in
`docs/project-status.md`, `docs/emulator-readiness.md`, `docs/remote-lan-validation.md`, and
`docs/free-runtime-validation.md`.

## 14. Update, deployment, and recovery policy

The fork uses manual owner-approved application updates. Sparkle initialization and update
requests are disabled by default because upstream releases cannot safely replace this
custom branch or its pinned game-runtime behavior. Engine/runtime updates are also manual
and per-profile. A working game profile is never silently upgraded.

Before installing a candidate, the running Game Hub process is closed and the prior app
bundle is moved to a private backup or temporary recovery path. The new signed bundle is
copied to both installed locations and verified recursively. The private
`.build-local/installed-revision.json` receipt records the exact commit, branch, build type,
acceptance state, and installed path.

The authoritative source tree should stay clean after each milestone. Unique untracked work
is archived before removal, obsolete mockups are removed from active folders, and tracked
history remains available in Git. Do not delete Wine containers, saves, ROMs, firmware,
catalog databases, bookmarks, or NAS content as part of an application update.

The final accepted binary contains two local source commits that are ahead of the
published remote:

- `53628bf75096ac02e5798de659d6282047c70054` — native full-size macOS icon
- `c0797e9ece4b51b704d2508cedf08639fc787a54` — final cinematic artwork polish

The documentation commit containing this brief is also unpublished. All unpublished
commits require the owner's explicit final push approval before publication.

## 15. Known limits and honest status

- This is a local ad-hoc-signed Debug delivery, not a notarized public installer.
- A native Mac Steam game launch remains less extensively exercised than the Windows Steam
  and remote launch paths.
- Yoda's formal ten-minute gameplay stability test and away-from-home tunnel measurement
  remain open, although LAN gameplay is owner-accepted.
- PS5 away-from-home acceptance was not measured.
- PS3 gameplay is pending.
- Some emulator save/reload and rear-paddle scenarios are deferred.
- Intermittent NAS/Wi-Fi latency was observed during some sessions. The owner chose NAS-only
  ROMs, so the app does not hide this with automatic local copies.
- Physical controller navigation has extensive owner feedback and simulated app regression,
  but the latest automated run did not have a controller connected.
- Release telemetry/privacy, notarization, and public distribution need a separate review.

## 16. Important files for future work

- `docs/project-status.md` — current delivery and acceptance ledger.
- `.build-local/installed-revision.json` — private exact installed-build receipt.
- `README-engineering.md` — concise engineering entry point and validation commands.
- `Packages/GameHubCore/Sources/GameHubCore/` — provider-neutral parsers, catalog, profiles,
  ROM, remote, and safety logic.
- `Packages/GameHubCore/Tests/GameHubCoreTests/` — the 83-test core suite.
- `Mythic/Views/Navigation/ContentView.swift` — shell, sidebar, controller regression hooks.
- `Mythic/Views/Navigation/ControllerLibraryView.swift` — controller library, Details,
  options editor, cinematic scenes, and Steam video.
- `Mythic/Views/Navigation/LibraryView.swift` — search, system/alphabet filtering, Quick Play.
- `Mythic/Views/Navigation/ROMLibraryView.swift` — source bookmarks, scanning, launch and
  managed emulator sessions.
- `Mythic/Views/Navigation/ConnectionsView.swift` — Yoda/PS5 connection UI and checks.
- `Mythic/Views/Unified/Components/GameImageCard.swift` — theme, platform marks, artwork
  resolution, caching, aspect-preserving rendering.
- `Mythic/Utilities/Game/SteamGame.swift` — Steam target bridge.
- `Mythic/Utilities/Game/EpicGamesGame.swift` — Legendary and Yoda launch bridge.
- `Mythic/Utilities/Engine/` and `Mythic/Utilities/Wine/` — retained Mythic runtime layer.
- `scripts/verify-debug-build.py` — reproducible local build/sign entry point.

Future ChatGPT work should inspect these sources and the current Git diff before proposing
changes. Preserve provider identity, the owner's NAS-only policy, existing saves and
credentials, manual runtime pins, controller-first navigation, full-screen clean exit,
aspect-correct artwork, and the accepted launch profiles.
