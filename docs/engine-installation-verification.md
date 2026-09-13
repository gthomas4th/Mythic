# Verified engine installation and container setup

The old installer extracted downloads without checking the published checksum. It
now requires the official HTTPS engine host, restricts redirects, bounds checksum
metadata, streams SHA-256 verification, and extracts into a unique staging directory.
It checks the executable and full semantic version before moving the engine into
place, refuses to overwrite existing runtime folders, and writes a version/hash receipt.

Stable catalog 2.6.1 installed successfully through the app. Its archive reports
2.6.1+0, wine64 reports wine-7.7, and D3DMetal is present. Verified archive SHA-256:
`e73ded51ff7775e56cb675c5ac0b11012d076257bab3f624f89bc18dabde903f`.

Setup now distinguishes missing-engine and empty-container states, refreshes when
installation completes, and detects an existing Rosetta runtime without depending on
its background process. Opening a Windows installer no longer blocks the main actor.

Registry reads extract the requested scalar value instead of returning the entire
output line. Reading Retina settings cannot write them back; explicit changes update
container metadata only after registry success. Live UI verification read Retina on,
then applied off successfully in the new Steam container.

Validation: full Debug build, 41 passing core tests, and live engine/container setup.
No Windows game compatibility is claimed. Per-game runtime pins and side-by-side
upgrade/rollback remain unimplemented; the inherited explicit removal flow remains.
