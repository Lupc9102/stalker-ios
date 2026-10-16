# Remaining engine boundary

The pinned public snapshot imports one shared memory64 object and 489 functions:

| Group | Functions | Work still needed |
| --- | ---: | --- |
| Graphics | 331 | 323 native entry points; GLES triangle verified on Linux. iOS surface, game shaders, compressed-texture fallbacks and game frames remain. |
| Filesystem | 32 | 24 native entry points; archives mount through read-only originals and writable overlay. Rename/removal and preload APIs remain. |
| Threads | 31 | Native pthread/TLS/mailbox services implemented. Cooperative app shutdown and restarts remain. |
| Audio | 29 | All imported OpenAL calls forward natively; PCM test passes. iOS audio-session lifecycle remains. |
| Other runtime | 66 | 44 native entry points. Remaining browser/SDL services and app lifecycle must be tested along the real startup path. |

Counts are a name-based inventory, not an estimate of equal implementation
effort or a claim that all functions are needed during normal gameplay. See
`Engine/imports.snapshot.json` for exact minified field → semantic function maps.

## Implemented in this checkpoint

The engine translates with a pinned WABT 1.0.42 patch for atomic wait/notify.
Shared SIMD accesses and bulk memory operations use checked atomic-byte
accesses; generated accesses are not replaced with unchecked plain pointers.
All generated engine C translation units compile into a Linux x86_64 archive.
The runtime host has wait32/wait64/notify plus conservative SIMD accessors.
The native host executes actual main, mounts the official benchmark's four
archives, selects the renderer and creates an EGL/GLES context. A standalone
graphics bridge test draws and verifies pixels; a game frame is still unproven.
See `Docs/NATIVE-HOST.md` for reproduction and verification limits.

The app input ABI is independent of engine internals. It stores a held state,
relative look deltas and an ordered edge queue so short taps are retained.
Its scancode mapping is a starting point for standard CoP keyboard bindings,
not a completed SDL bridge. Fire/aim and weapon scrolling need mouse semantics.

## Next integration order

1. The native app now compiles for iPhone and simulator using Xcode 16.4 through
   GitHub Actions. Launcher, editor and practice screenshots have been inspected
   on an iPhone 16 Pro simulator. Verify touch behavior on the user's iPhone;
   no physical-device test has been performed yet.
2. Finish real engine graphics startup on Linux; validate STALKER's shaders and
   texture formats. The native GLES triangle test passes.
3. Pass the iPhone ARM64 engine/host compilation job and connect the GLES
   provider to an iOS drawable. macOS startup and iPhone compilation are checked
   independently of the existing controls app build.
4. Connect input and the graphics/audio bridges; boot the engine menu.
5. With the user's original GOG files, load Zaton, test save/reload and measure
   real peak memory and frame times. Do not infer playability from menus alone.
6. Optimize mobile textures separately, then investigate Anomaly/Monolith.

The iOS app must keep gameplay unavailable until an actual host is present.
Do not enable Play just because an archive linked or an inventory detected files.
