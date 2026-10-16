# STALKER Port — Call of Pripyat on iOS

An early engine-port project with a native landscape UIKit launcher and an
editable touch layout adapted from the MIT-licensed GTA V iOS port.

**The native launcher and controls compile for iPhone; Call of Pripyat does not
run yet.** The unsigned IPA contains a controls-practice screen. Gameplay stays
disabled until a real engine host is linked. See [STATUS.md](STATUS.md) for
verification and gaps.

## App and controls

- GTA-style launcher: Zone art, game-files card, mode cards, Play, Settings and
  Controls layout. The original GTA artwork and branding are not included.
- Labels enabled by default; move with the left thumb and swipe the right side
  to look. Tap Tools to reveal detector, knife, bolts, healing and leaning.
- Move, resize, hide and reassign action buttons. Size 60–180%; per-button
  opacity 20–100%; three saved layouts; JSON import/export; left-handed mirror.
- Floating movement stick; hold or toggle aiming; sensitivity and global opacity.
- Bluetooth controller input in practice; button states merge with touch input.
- Reset held input on backgrounding, cancelled touches and controller disconnect.
- File picker can remember an installed original CoP folder. Presence checks
  detect resources/, levels/ and localization/ archives; they are **not** full
  game-integrity or compatibility validation. Original GOG/Steam PC version only.

## Build on Linux with xtool

Install the Swift toolchain and xtool using its official instructions:
<https://xtool.sh/documentation/xtool/installation-linux/>

xtool still needs an Apple Darwin SDK created from an Xcode distribution:

```sh
xtool sdk install --slim /path/to/Xcode.xip
bash Scripts/build_ios.sh
```

The build path produces an unsigned app/IPA; Apple sign-in is unnecessary for
that unsigned build. Sign/install it with your existing sideloading tool.
This SwiftPM/xtool configuration has not yet completed an iOS compile here.

## Build with GitHub Actions (no Mac at home)

Run **Build iOS app** under [Actions](https://github.com/Lupc9102/stalker-ios/actions/workflows/ios.yml).
The macOS job runs Xcode, builds an unsigned `ZonePort.ipa`, compiles a simulator
app and captures the launcher, controls editor and controls-practice screen.
The device and simulator builds have passed with Xcode 16.4 on macOS 15.
All three screens have been inspected on an iPhone 16 Pro simulator.
See the [build record](Docs/verification/ios-build.md) for the exact source,
artifact and verification limits.
Download the `ZonePort-iOS` artifact from a successful run, extract the IPA, and
sign/install it with your sideloading tool. Minimum iOS version: 17.0.
The workflow never requests an Apple ID, certificate or game data. Public and
private repositories use GitHub's respective runner usage rules.

On a Mac with Xcode and `xcodegen`:

```sh
bash Scripts/build_ios.sh
```

## Engine experiment

The route is Emscripten WASM64 → patched WABT wasm2c → native C. No JIT is used.
The pinned engine snapshot comes from the existing ZoneVM port. Only the engine
and its JavaScript import map are fetched; no retail game archives are downloaded.
Public compiled-snapshot provenance is pinned by hash; correspondence to the
separate source commit has not been established by a reproducible source build.

Dependencies: Python 3.10+, git, CMake 3.23+, a C/C++ compiler, pthreads.

```sh
python3 Scripts/prepare_engine.py
python3 Scripts/cpu_probe.py Engine/Generated Engine/Generated/imports.json
cmake -S Engine -B Engine/Build
cmake --build Engine/Build -j 3
ctest --test-dir Engine/Build --output-on-failure
Engine/Build/zone_cpu_probe
```

The generated diagnostic host traps unsupported browser imports. A successful
module-instantiation message does not mean the engine main, renderer or game
works. This diagnostic archive is not linked into the iOS app.

`prepare_engine.py --wasm /path/to/custom.wasm --javascript /path/to/custom.js`
accepts an explicitly supplied custom engine build. Shared-memory assumptions
are checked by the postprocessor and must be reviewed if the module changes.

## Checks

```sh
bash Scripts/check.sh
```

The local C tests cover input edges, cancellation, queue overflow and bounds.
The engine CMake tests cover shared-memory wait/notify and SIMD helpers. The
macOS workflow compiles UIKit against the iOS SDK and captures simulator screens.
Physical-device testing is still outstanding; the Linux syntax check alone
does not establish iOS compatibility.

## Game content and later optimization

Players supply their own installed game files separately from the app. A GOG
installer needs installing/extracting first. The original installation is never
modified by this checkpoint. No texture conversion or compression has been done.
Once gameplay works, profile texture residency and streaming before making a
separate mobile asset pack. Archive compression and GPU texture compression
solve different problems.

## Credits and licenses

Launcher theme, home view, control visuals and atomic wait/notify patch are
adapted from <https://github.com/kevinerikjs/gta5-ios-port> (MIT).
OpenXRay source reference: <https://github.com/x8BitRain/xray-16-wasm/tree/wasm>.
ZoneVM: <https://github.com/x8BitRain/zone-vm>.
Third-party notices are in `Licenses/`; original game rights remain with their
owners. The bundled background is original generated artwork, not game content.
