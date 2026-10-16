# Checkpoint: 2026-10-16

## Verified here

- Original Zone artwork bundled with a native UIKit launcher adapted from the
  GTA iOS port's MIT code. No GTA art is included.
- Xcode 16.4 (16F6) on the GitHub macOS 15 runner successfully compiled the
  Release ARM64 iPhone app, packaged its unsigned IPA, and compiled the Debug
  simulator app. UIKit type checking passed in these builds.
- The launcher, controls editor and controls-practice screen launched on an
  iPhone 16 Pro simulator. Screenshots were visually inspected for safe areas,
  full-screen landscape layout, readable labels and the editor panel.
- Packaged-IPA validation checks ARM64 code, landscape support, launch-screen
  metadata, full-screen mode and Files integration. This catches the project
  generator overwriting the supplied Info.plist.
- All app Swift files also pass the Swift 6.2 frontend syntax parser in Swift 5
  mode on Linux.
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
- The newer native host executes the engine's constructors and real main on
  Linux. It reads the filesystem config, mounts a native folder, writes a log
  into a separate app-data overlay and stops at missing `system.ltx`. The exact
  output is in `Docs/verification/native-engine-main.log`.
- Native host tests pass for 64-bit file offsets above 4 GiB, parallel reads,
  read-only originals with copy-on-write data, symlink/path containment, shared
  access handles, 70,000 open/close cycles and native OpenAL PCM/source queues.
- The optional native GLES bridge renders and verifies a real triangle through
  memory64 import bindings using EGL/Mesa. Shader compilation, uniforms,
  reflection, buffers, readback/packing and GPU sync handles pass. This is a
  bridge test, not a rendered game frame.
- Both workflow YAML files, the xtool configuration and Info.plist parse.

## Not implemented / not verified

- **The compiled IPA is a launcher and controls-practice build, not a playable
  STALKER port.**
- The translated engine is not connected to the app. Campaign Play is disabled.
- iOS graphics surface integration, the engine lifecycle and SDL input delivery
  are still outstanding. Filesystem/pthread/OpenAL/GLES services now work in
  Linux host tests; they have not yet been integrated into UIKit.
- The native host implements 451 typed import entry points with GLES. The other 38 imports
  remain explicit traps. Event registration is stored; UI event delivery is not
  connected. See `Docs/NATIVE-HOST.md` for the exact scope.
- No menu, level, save, combat, game memory-budget or sustained frame-rate test
  has been performed. Reaching missing game data is a startup test only.
- No ARM64 engine compile, automated UI interaction test or physical-device test
  has completed. The ARM64 app build does not contain the translated engine.
- No retail game archives or textures have been compressed, resized or modified.
- Full archive integrity/compatibility checks are not implemented; the app checks
  for archive presence and obvious missing/empty/cloud-only files.

## Build environments

xtool 1.22.2 was downloaded and its CLI help/SDK status commands run on Linux.
`xtool sdk status` reports **Not installed**. xtool needs Apple's Darwin SDK,
normally extracted from a user-provided Xcode.xip/Xcode.app distribution.

An attempted `xtool dev build --configuration release --ipa` additionally aborts
inside SwiftNIO while registering a descriptor with `epoll`: `Operation not
permitted`. This workspace's runtime restriction prevents that path as tested.
The Xcode path through GitHub Actions bypasses these Linux blockers. The actual
device and simulator compile results are recorded in
[run 38924371922](https://github.com/Lupc9102/stalker-ios/actions/runs/38924371922).
Artifact details and verification limits are in
[the iOS build record](Docs/verification/ios-build.md).

## Next action

Continue the native engine host in the order documented in `Docs/ENGINE-HOST.md`.
The native rendering test passes. A real game frame and the iOS engine surface
are next. Physical-device controls testing remains outstanding; the existing
controls IPA still contains no linked engine.
