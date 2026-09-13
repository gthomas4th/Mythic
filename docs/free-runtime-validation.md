# Free Wine runtime validation

Owner constraint: no purchases, paid runtime dependencies, or time-limited trials.
The existing Mythic runtime and original Steam container remain intact.

## Candidate and provenance

Sikarugir (the maintained successor to Wineskin/Kegworks) lists
WS12WineSikarugir10.0_6 as its supported D3DMetal-capable engine. Its Wine 11
alternative explicitly lacks D3DMetal and was not selected for this test.

| Component | Verified SHA-256 |
|---|---|
| WS12WineSikarugir10.0_6.tar.xz | `9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2` |
| Template-1.0.15.tar.xz | `34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3` |

Sources: [engine release](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0),
[companion libraries](https://github.com/Sikarugir-App/Wrapper/releases/tag/v1.0),
[supported engine list](https://github.com/Sikarugir-App/Sikarugir/blob/main/.github/ISSUE_TEMPLATE/bug.yml).
Both archive hashes matched their GitHub release asset digests before extraction.
The executable reports `wine-10.0 (Sikarugir)`.

The standalone engine requires companion libraries normally supplied by its wrapper.
Only top-level dylibs and their relative symlinks from the verified template's
Contents/Frameworks were copied into the candidate's lib directory. No wrapper
launcher was installed. The renderer was staged separately during the later
first-launch preparation described below. Runtime and
container files are under Application Support/GameHub/RuntimeCandidates, outside Git.
A local candidate receipt records artifact URLs, hashes and executable hashes.

## Isolated test host

`scripts/runtime-test-host.swift` is a development-only AppKit launcher, not a new
production launch strategy. Compile with Xcode's Swift 6 compiler and AppKit into
an ignored app bundle. Its local Info.plist supplies absolute TestRuntimeRoot,
TestPrefix and TestLog paths, along with the normal executable/bundle identifiers.
The test prefix is a copy of the existing Steam container; preserve symlinks while
copying, and never use the original prefix for candidate upgrades.

The host's Launch Windows Steam button starts bin/wine with the copied steam.exe,
sets WINEPREFIX explicitly, uses the Steam directory as its working directory, and
writes diagnostics to a local ignored log. Stop Test Container calls that candidate's
wineserver with the same prefix. Do not commit local paths or Steam account data.

## Evidence

Current Steam client build 1788652215 failed repeatedly on Mythic engine 2.6.1+0.
With the free Wine 10 candidate, the copied prefix upgraded, Steam reported
BrowserReady, established its UI websocket, and created a popup window. The previous
webhelper restart loop did not recur during the initial observation.

The owner completed Windows Steam login; its connection log confirmed a successful
logon. Rebirth (2909400) completed installation in the isolated container. Steam
reported Fully Installed (manifest StateFlags 4), scheduler result No Error, and
171.06 GB installed. Both ff7rebirth.exe and End/Binaries/Win64/ff7rebirth_.exe exist. The native test host now also exposes
Install Rebirth through Steam's installation URI; download state is independently
verified from its manifest and content log. The owner subsequently launched the game and moved through gameplay, but reported
a steady, poor frame rate. Performance acceptance remains open. Production runtime
selection and per-game pinning still require implementation after validation.

## Rebirth first-launch preparation

D3DMetal 3.0 was staged separately from the same verified Template-1.0.15 archive,
with its original license, acknowledgements, README and a local file-hash receipt.
The test host accepts TestRendererRoot in its local bundle configuration. The
Sikarugir loader requires WINEDLLPATH_PREPEND and CX_APPLEGPTK_LIBD3DSHARED_PATH;
setting WINEDLLPATH alone caused Steam webhelper to fail before game launch. With
the loader hooks configured, Steam's UI initialized successfully again.

The initial test enables AVX advertisement and the Metal HUD/logging, uses default
synchronization (MSync/ESync off), and requests 1920x1080 windowed mode through
Steam -applaunch 2909400. These are candidate settings, not a measured optimum or
confirmation that the game honored its requested resolution.

Steam completed its Visual C++/DirectX first-run installers, then held the launch at
SynchronizingCloud with pendingcloudsessions. Its cloud log reports one pending
remote operation while the locally downloaded saves match cloud change number 23.
Five downloaded saves were copied and hash-verified outside Git before resolving
the remote-session prompt. The owner confirmed the game was not running elsewhere, accepted the warning,
and launched the game manually. Save backups remain separate from runtime changes.

## First performance observation

The live Rebirth process loaded the staged D3DMetal framework and libd3dshared,
verified through its mapped files. A 59.983-second Metal HUD frame-counter window
advanced 2,073 frames: 34.56 frames/second. This is an unlabelled scene observation,
not a controlled gameplay benchmark or a claim of acceptable performance. The owner
reported poor but steady frame rate.

The development launcher now offers separate 1080p and 720p launch requests so the
resolution can be compared while retaining the same renderer and default sync mode.
720p has not yet been measured or confirmed as the actual output resolution. The
generated GameUserSettings.ini contains only a newline; do not pretend it exposes
the game's current quality settings or modify binary save data to tune graphics.
Save and exit the game normally before testing the other launch request.

## Integrated delivery

The owner accepts approximately 40 FPS at the game's displayed 1080p. The ineffective
720p comparison is not the accepted profile. The production library bridge now uses
the selected JSON profile and local bookmarked/hash-pinned runtime binding. The test
host remains an ignored development artifact, not the primary launcher. See
[project status](project-status.md) for precise implementation and live-test limits.

## Local controller validation — 2026-09-13

The owner connected an Xbox One S controller after Rebirth was already running.
Game Hub reported it connected, Windows Steam logged the device arrival, and Wine
registered an XInput-compatible device. The owner reported no game input. After
exiting normally and relaunching through Game Hub with the controller connected,
the owner confirmed that input worked. The accepted 1080p runtime profile was unchanged.

Connecting before launch is the verified workaround, not the desired final behavior.
First connection during gameplay remains unresolved. The owner subsequently confirmed
one successful disconnect/reconnect, then a failure on a second cycle after clicking
the game with the mouse. Pressing controller buttons again did not recover input.
This is a correlation, not proof that mouse input causes the failure. Steam logged
both reconnects and selected Rebirth bindings; these loaded controller_base/empty.vdf
and reported no XInput mapping. The owner authorized closing the game without waiting for another save confirmation.
After Windows Steam and its Wine processes stopped, its local configuration was
backed up privately outside Git and a Rebirth-only root apps/2909400 override
UseSteamControllerConfig=1 was added. Existing configuration text was preserved.
Steam restarted, signed in, and retained the override. After the owner dismissed
Steam's sync warning, Steam recorded the Rebirth launcher and game process at
1920×1080. The owner then confirmed that the mouse-click and controller reconnect
sequence worked. Retain the current configuration as the successful tested state.
The logs still reported no XInput mapping, so this test does not establish that
Steam Input emulation caused the recovery. First connection after a launch with no
controller, and repeated reconnect cycles, remain separate unverified cases.
No driver or graphics-profile changes have been applied. Physical controller
navigation through the hub is also still pending.
