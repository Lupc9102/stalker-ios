# Checkpoint: 2026-10-18

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
- Workflow YAML files, the xtool configuration and Info.plist parse.
- The engine and native GLES/drawable host cross-compile for iPhone ARM64.
  Actual engine main also runs on Apple Silicon and reaches the expected
  missing-data boundary. The Apple workflow's three tests pass, including
  10,000 exception catch/rethrow rounds and file reads using guest addresses
  and file offsets above 4 GiB. See `Docs/verification/apple-engine-build.md`.
- A reproducible compiler bug leaked the guest call-depth counter on caught
  exceptions. The patched generator passes the nested exception regression
  fixture and actual engine startup registers 251 script-export nodes, loads
  game scripts, and renders three real main-menu frames. The official free
  benchmark supplies the test archives; forced BC1/2/3 decoding also renders
  the same menu with the iPhone-compatible RGBA upload path; see `Docs/verification/native-engine-menu.log`.

- The native iOS engine now visibly renders the real CoP main menu in UIKit on
  an ARM64 simulator. Game and display framebuffer readbacks and an actual
  simulator screenshot confirm the result; see
  `Docs/verification/native-ios-runtime.md`.
- The player's Enhanced Edition upload mounts on the native Linux host. Two
  bundled shader repairs eliminate four GLES compilation failures. A duplicate
  info-ID diagnostic in the pinned engine was then identified as the startup
  trap. A fresh CI translation/build of the repaired snapshot reproduces 80
  real frames. The optional font-mask converter makes ordinary Enhanced Edition
  menu labels visible; all 136 tested masks match an independent alpha decode.
  Campaign startup still encounters newer script APIs. See
  `Docs/verification/retail-startup.md`.
- The repaired engine also passes a fresh native iOS device/simulator build
  and UIKit benchmark-menu/background-resume test at `5ba6be8`. The same app
  process renders 32 new callbacks after foregrounding (278 → 310).
- At `055de63`, fresh Linux/Apple engine checks, iOS device/simulator builds,
  visible UIKit menu and same-process background/resume checks pass with bulk
  prefetch disabled. The new unsigned IPA passes packaged ARM64/metadata checks.
- A private classic-script/UI compatibility layer with the player's registry
  loads Zaton's geometry and objects from Enhanced Edition archives. Selecting
  existing 512px DDS mips avoids the earlier host OOM kill. Matching classic
  achievement definitions then allow 100 callbacks and a successful diagnostic
  exit. The capture is the final "Press any button to play" loading screen;
  world rendering is not established. See `Docs/verification/retail-startup.md`.

## Not implemented / not verified

- The original `ZonePort.ipa` is the launcher/controls-practice variant. The new
  `ZonePort-Native.ipa` links the real engine and enables campaign startup with
  the player's own files. Device compilation/package checks passed; see
  `Docs/verification/native-ios-build.md`. Physical-device gameplay remains
  unverified.
- The UIKit engine surface, action/pointer delivery and background pause
  checkpoints are connected. Visible simulator menu rendering is verified; the
  background/resume run and the stricter same-process/fresh-frame check passed.
  This first integration retains one session per app process; safe worker
  teardown/restart remains outstanding. See `Docs/IOS-ENGINE.md`.
- The native host implements 452 typed import entry points with GLES. The other 37 imports
  remain explicit traps. Native input tests cover the callback ABI, surface
  listener removal and thread ownership. Real pointer input opens Options;
  see `Docs/verification/native-engine-options.log` and `Docs/NATIVE-HOST.md`.
- Campaign startup with the experimental Enhanced Edition/classic overlay now
  reaches the final loading prompt. No retail world view has been verified.
  Saves, combat, game memory budget and sustained
  frame rate remain unverified.
- No physical-device engine test has completed. The new native app build does
  contain the translated engine.
- Original retail archives remain unchanged. A manual font-mask converter is
  tested, along with selection of existing BC mipmaps. General texture resizing,
  GPU format conversion and automatic mobile asset preparation are not implemented.
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
The native engine renders the menu and responds to input. The native
UIKit simulator/resume test and unsigned device package checks pass. Test the
player's files next: the supplied Enhanced Edition data now reaches backdrop
rendering with the reproducibly rebuilt engine. Resolve Enhanced Edition's
script/UI differences or test original/classic CoP 1.6.02 files for the campaign
baseline. Retail-level rendering, saves and physical-device controls remain.
