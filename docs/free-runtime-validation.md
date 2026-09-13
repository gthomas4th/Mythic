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
launcher or proprietary renderer was installed from that archive. Runtime and
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
verified from its manifest and content log. Sustained Rebirth gameplay remains an
acceptance gate.
No Rebirth compatibility or FPS claim is made. Production runtime selection,
renderer integration and per-game pinning still require implementation after validation.
