# STALKER Port — Call of Pripyat on iOS

An early engine-port project with a native landscape UIKit launcher and an
editable touch layout adapted from the MIT-licensed GTA V iOS port.

**The native engine build renders the real CoP main menu in an iOS simulator,
without JIT.** It links the translated engine, native graphics/audio/file services
and customizable touch controls. Retail levels and physical iPhone gameplay
remain unverified. See [STATUS.md](STATUS.md) and the
[runtime record](Docs/verification/native-ios-runtime.md).

Use `ZonePort-Native.ipa` for engine testing. The older `ZonePort.ipa` is the
launcher/controls-practice build.

## App and controls

- GTA-style launcher: Zone art, game-files card, mode cards, Play, Settings and
  Controls layout. The original GTA artwork and branding are not included.
- Labels enabled by default; move with the left thumb and swipe the right side
  to look. Tap Tools to reveal detector, knife, bolts, healing and leaning.
- Move, resize, hide and reassign action buttons. Size 60–180%; per-button
  opacity 20–100%; three saved layouts; JSON import/export; left-handed mirror.
- Floating movement stick; hold or toggle aiming; sensitivity and global opacity.
- Bluetooth controller input shares the engine input hub with touch input;
  physical-device controller behavior remains unverified.
- Reset held input on backgrounding, cancelled touches and controller disconnect.
- File picker can remember an installed original CoP folder. Presence checks
  detect resources/, levels/ and localization/ archives; they are **not** full
  game-integrity or compatibility validation. Original GOG/Steam PC version only.

## Launcher-only build on Linux with xtool

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

Run **Build iOS native engine app** under
[Actions](https://github.com/Lupc9102/stalker-ios/actions/workflows/ios-engine.yml).
The macOS job builds and verifies an unsigned ARM64 `ZonePort-Native.ipa`, then
builds the connected simulator app. It tests the actual engine using GSC's free
benchmark archives outside the app, checks framebuffer and screen content, and
checks background/resume. Test archives are not uploaded with the artifacts.

Download `ZonePort-Native-iOS` from a successful run, extract the IPA, and
sign/install it with your existing sideloading tool. Minimum iOS version: 17.0.
The workflow needs no Apple ID, certificate or retail game data. See the
[device build record](Docs/verification/native-ios-build.md) for verification
and limitations.

On a Mac with Xcode, CMake, Python and `xcodegen`:

```sh
bash Scripts/build_native_ios.sh
```

The separate [Build iOS app](https://github.com/Lupc9102/stalker-ios/actions/workflows/ios.yml)
workflow and `Scripts/build_ios.sh` build only the launcher and controls practice.
The xtool configuration also targets that smaller variant.

## Load your game files

1. Install/extract your original GOG or Steam PC copy of Call of Pripyat.
2. Copy the installed folder to the iPhone and make sure its files are fully
   downloaded. Keep `resources/`, `levels/`, `localization/` and `patches/`
   (when present) together.
3. In the native engine app, select that folder and start CoP. Changes and
   engine logs go to `Documents/ZonePortData`, separate from the originals.
4. The app starts with direct taps for the game menus. In Controls, choose
   Show game controls for the customizable movement/action HUD; Use game menus
   switches back. CoP draws its own cursor, so this mode is selected manually.

This is an experimental engine checkpoint. Level loading, saves and performance
still require testing with retail files. Only one engine session is supported
per app process; relaunch the app after ending a session.

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

The newer [native host](Docs/NATIVE-HOST.md) goes further: it runs constructors
and real engine main on Linux, mounts files through a native OPFS replacement,
and uses native pthreads and OpenAL. With the official free benchmark it mounts
four archives, initializes textures/scripts and renders the real main menu.
Native pointer input opens Options on Linux. The connected iOS simulator app
also visibly renders the menu through GLES and UIKit. These menu tests do not
establish retail-level compatibility, physical-device gameplay or performance.

The supplied Enhanced Edition files now mount and render on the fresh native
Linux build after shader and duplicate-info-ID repairs. Its campaign scripts
expect additional engine APIs, so this is not Enhanced Edition support. The
current campaign baseline remains the original/classic CoP 1.6.02 release.
See [retail startup diagnostics](Docs/verification/retail-startup.md).

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
modified by this checkpoint. The optional `Scripts/convert_font_masks.py` creates
loose L8 font overrides from extracted, colorless Enhanced Edition BC3 masks;
it preserves the base-level glyph mask exactly. This manual compatibility tool
does not run automatically during iOS import. General texture resizing and GPU
compression have not been implemented.

For private data diagnostics on Linux, `Scripts/xray_archives.py` extracts only
scripts or font atlases and checks every selected member's CRC. It requires a
C++ compiler, liblzo2, and the public source checkout prepared by
`prepare_support_data.py`. Use a new output directory outside this repository:

```sh
python3 Scripts/xray_archives.py --input-root /path/to/installed-game --kind scripts --output-dir /path/to/private/extracted
```

Use `--kind fonts` for font conversion inputs; the extracted fonts retain their
`textures/ui/` directory. The native Linux diagnostic host also accepts
`ZONE_START_NEW_GAME=1`, so campaign tests need not alter `user.ltx`. If a frame
traps and a capture path was supplied, the host attempts to capture the last
framebuffer and still exits with failure. Such captures can show loading/error
screens and do not establish playable gameplay.

`Scripts/prepare_texture_overlay.py --input-root /path/to/installed-game
--output-dir /path/to/private/mobile-overlay --max-size 512` selects existing
BC1/2/3 mip levels into loose overrides. It preserves retained compressed bytes
and leaves original archives, UI atlases, cubemaps and unsupported formats alone.
Textures without smaller mip levels cannot be reduced by this tool. This is
manual asset preparation, not automatic iOS import or GPU format conversion.
The mobile app and diagnostic host disable bulk object/model prefetch to lower
the startup memory peak; assets still load when requested by the engine.
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
