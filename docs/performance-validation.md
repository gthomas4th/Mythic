# Laptop performance target and runtime validation

Owner requirement: tune each launch engine to the actual laptop, not generic maximum
settings. Current machine: MacBook Pro Mac15,6, Apple M3 Pro, 11 CPU / 14 GPU cores,
18 GB reported memory, macOS 26.6.2. Hardware identifiers and private paths are excluded.

## Starting policy

- Prefer native Apple silicon execution when available. Use the renderer supported
  by the selected game and exact runtime; renderer options are not interchangeable.
- Begin demanding-game measurements at 1920×1080, on AC power, with a repeatable scene.
  Compare a stable 30 FPS cap against 60 FPS where achievable. These are test targets,
  not current performance claims. Favor consistent frame pacing over peak FPS.
- Select texture quality, upscaling and internal resolution using measured memory
  pressure and image quality. Do not invent a dedicated VRAM allocation from the
  laptop's shared 18 GB memory, or apply every emulator enhancement globally.
- Benchmark sustained gameplay after shader warm-up. Record renderer/runtime,
  resolution, quality settings, cap, power mode, controller, temperatures if available,
  average/p95 frame times, stutter, memory pressure and audio/visual faults.
- Native and emulator profiles are per game/system. Demanding local Wine candidates
  also get a Remote PC target when configured; remote availability is measured.

## Required pin and rollback contract (not yet implemented)

A verified profile records the exact engine version and artifact SHA-256, renderer,
settings and hardware/OS. Testing an upgrade creates a separate candidate and retains
the previous working engine/profile. App updates cannot silently replace a pinned
runtime. Saves remain outside profile rollback.

An untested or menu-only result stays unverified. A useful gameplay window and repeat
launch are required before marking a profile playable. The owner selected FFVII Rebirth
on Steam as the first Windows target, overriding the handoff sequence. FFXV remains
excluded. Store identities remain tied to the owner's actual purchases.

## Current evidence and remaining work

Native Steam and the Deck reference importer compile and run. The verified installer
installed stable engine 2.6.1+0 (catalog 2.6.1); wine64 reports wine-7.7 and D3DMetal
is present. The new Steam container uses Windows 11, MSync and AVX2, with DXVK off.
Retina mode was explicitly disabled through the corrected settings UI and reported
success. This is an initial shared-container baseline, not a benchmarked per-game profile.

The official Steam installer completed its update to client build 1788652215.
The Steam UI helper repeatedly restarted before showing a login window, including
a clean container restart and executable checksum verification. This runtime/client
combination failed storefront acceptance; login and the game download remain blocked. No Rebirth gameplay, compatibility result,
or measured FPS is claimed. Storage cleanup left over 300 GB available before setup.

The installer now verifies the publisher's SHA-256 over HTTPS before extraction,
validates the staged engine, and records its exact version and digest. Preview 3.0.0
has no checksum entry and is rejected. Existing engine folders are preserved by
installation. The inherited explicit remove/update flow is not yet the required
side-by-side upgrade and rollback implementation; do not use it for a pinned profile.

## Free-runtime follow-up

An isolated free Wine 10 candidate has passed the initial Steam UI startup failure
seen above. See [free runtime validation](free-runtime-validation.md) for provenance,
companion-library requirements and evidence. Windows Steam login is verified and Rebirth is fully installed in that test container
(171.06 GB; Steam scheduler result No Error).
D3DMetal loading and owner-driven gameplay are now verified. The owner reports poor
but steady frame rate; an unlabelled 60-second HUD window averaged 34.56 FPS.
Performance acceptance remains open. A 720p comparison is prepared, not yet measured;
see the free-runtime notes for the current evidence.

## Owner acceptance supersedes earlier tuning interpretation

The owner clarified that the game's displayed resolution remains 1080p and roughly
40 FPS is acceptable. Preserve this configuration; further local performance tuning
was not requested. See [current project status](project-status.md) for the persisted
profile and remaining live acceptance gates. The roughly 78 FPS follow-up sample
cannot establish improvement because scene and resolution were not controlled.

## Local Game Hub launch integration

The installed hub launched Steam Rebirth using the accepted local profile from its
keyboard-controlled game-details flow. Steam tracked both the launcher and game
process with `-windowed -ResX=1920 -ResY=1080`. The owner confirmed the game was on
the Mac's other monitor. No fresh FPS benchmark is claimed; the previously accepted
approximately 40 FPS profile remains unchanged. Yoda was not running Rebirth during
this local test. The Home PC preference was restored afterward without launching a
second copy or changing game saves.
