# Checkpoint: 2026-10-16

## Verified here

- Original Zone artwork bundled with a native UIKit launcher adapted from the
  GTA iOS port's MIT code. No GTA art is included.
- All app Swift files pass the Swift 6.2 frontend syntax parser in Swift 5 mode.
  This is a syntax check, not UIKit type checking or a successful iOS build.
- SwiftPM manifest evaluates with `swift package dump-package`.
- C input tests pass: short tap edges, finite/clamped axes, one-shot look deltas,
  input reset and overflow recovery.
- Four Python Wasm-inventory tests pass.
- Host wait/notify tests pass for timeout, value mismatch, two waiting threads
  and exact notification count. Shared SIMD tests include unaligned full-vector,
  zero-extending and lane reads/writes.
- The 22,777,962-byte public STALKER WASM snapshot translates to 64 C units using
  patched WABT 1.0.42. All units compile into a Linux x86_64 native static archive.
- A diagnostic native executable successfully initializes the translated Wasm
  module without JIT or retail game files. Its console output is preserved in
  `Docs/verification/module-startup.log`.
- Both workflow YAML files, the xtool configuration and Info.plist parse.

## Not implemented / not verified

- **There is no playable STALKER iOS port or completed IPA in this checkpoint.**
- The translated engine is not connected to the app. Campaign Play is disabled.
- Native GLES/ANGLE → Metal renderer, filesystem host, worker/TLS integration,
  audio host and SDL input bridge are still outstanding.
- The 489 imported functions have been inventoried, not implemented. The native
  probe's import bodies are diagnostic traps, never gameplay substitutes.
- Engine main is not called by the probe. No menu, level, save, combat, memory
  budget or sustained frame-rate test has been performed.
- No ARM64 engine compile, UIKit type check, simulator UI test or physical-device
  test has completed.
- No retail game archives or textures have been compressed, resized or modified.
- Full archive integrity/compatibility checks are not implemented; the app checks
  for archive presence and obvious missing/empty/cloud-only files.

## Build environment blockers

xtool 1.22.2 was downloaded and its CLI help/SDK status commands run on Linux.
`xtool sdk status` reports **Not installed**. xtool needs Apple's Darwin SDK,
normally extracted from a user-provided Xcode.xip/Xcode.app distribution.

An attempted `xtool dev build --configuration release --ipa` additionally aborts
inside SwiftNIO while registering a descriptor with `epoll`: `Operation not
permitted`. This workspace's runtime restriction prevents that path as tested.
No authentication credentials were requested or used.

The GitHub macOS workflow is prepared for this repository. Its first build is
pending; this file will be updated with the actual compiler and simulator results.

## Next action

Run `.github/workflows/ios.yml` in a dedicated accessible repository. Resolve
actual iOS compile/layout issues, obtain a controls-practice IPA, then continue
the native engine host in the order documented in `Docs/ENGINE-HOST.md`.
