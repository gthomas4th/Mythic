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

## Pin and rollback contract

A verified profile records the exact engine version and artifact SHA-256, renderer,
settings and hardware/OS. Testing an upgrade creates a separate candidate and retains
the previous working engine/profile. App updates cannot silently replace a pinned
runtime. Saves remain outside profile rollback.

An untested or menu-only result stays unverified. A useful gameplay window and repeat
launch are required before marking a profile playable. FFVII Remake precedes Rebirth;
FFXV remains excluded. Store identities remain tied to the owner's actual purchases.

## Current evidence and remaining work

Native Steam and the Deck reference importer compile and run. No game payload is
installed locally yet, and the Windows engine has not been installed. Therefore no
local gameplay benchmark, tuned runtime profile, or Final Fantasy compatibility result
is claimed. The upstream Wine settings expose msync, Retina mode, DXVK and AVX flags;
these are options to test, not blanket performance guarantees.

The official engine catalog offers stable 2.6.1 with a checksum; preview 3.0.0 lacks a
checksum entry. The upstream installer currently ignores checksums. Verified artifact
installation and per-game profile persistence must precede Windows tuning. Interactive
license acceptance, storefront login and game selection remain user-facing steps.
