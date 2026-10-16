# Remaining engine boundary

The pinned public snapshot imports one shared memory64 object and 489 functions:

| Group | Functions | Work still needed |
| --- | ---: | --- |
| Graphics | 331 | Implement the Emscripten GL boundary over a native GLES/ANGLE context, translate pointers and object handles, implement extension fallbacks, validate shaders and textures. |
| Filesystem | 32 | Replace OPFS with native files; mount read-only game archives and writable app data; account for the existing WasmFS ABI. |
| Threads | 31 | Main/worker initialization, per-thread engine instances sharing the memory, TLS, mailbox dispatch and shutdown. |
| Audio | 29 | Supply native OpenAL semantics or an equivalent mixer; pause/resume cleanly with the audio session. |
| Other runtime | 66 | SDL/browser services, clocks, memory growth, signals, environment, errors and exit. |

Counts are a name-based inventory, not an estimate of equal implementation
effort or a claim that all functions are needed during normal gameplay. See
`Engine/imports.snapshot.json` for exact minified field → semantic function maps.

## Implemented in this checkpoint

The engine translates with a pinned WABT 1.0.42 patch for atomic wait/notify.
Shared SIMD accesses and bulk memory operations use checked atomic-byte
accesses; generated accesses are not replaced with unchecked plain pointers.
All generated engine C translation units compile into a Linux x86_64 archive.
The runtime host has wait32/wait64/notify plus conservative SIMD accessors.
The diagnostic host stops at unsupported browser imports and does not run main.

The app input ABI is independent of engine internals. It stores a held state,
relative look deltas and an ordered edge queue so short taps are retained.
Its scancode mapping is a starting point for standard CoP keyboard bindings,
not a completed SDL bridge. Fire/aim and weapon scrolling need mouse semantics.

## Next integration order

1. The native app now compiles for iPhone and simulator using Xcode 16.4 through
   GitHub Actions. Launcher, editor and practice screenshots have been inspected
   on an iPhone 16 Pro simulator. Verify touch behavior on the user's iPhone;
   no physical-device test has been performed yet.
2. Build/import ANGLE for iOS, render a real triangle through GLES → Metal, then
   validate STALKER's shader paths. This has not been implemented yet.
3. Build the engine for ARM64 with the host helpers; implement boot-time runtime,
   thread and filesystem imports based on the recorded startup boundary.
4. Connect input and the graphics/audio bridges; boot the engine menu.
5. With the user's original GOG files, load Zaton, test save/reload and measure
   real peak memory and frame times. Do not infer playability from menus alone.
6. Optimize mobile textures separately, then investigate Anomaly/Monolith.

The iOS app must keep gameplay unavailable until an actual host is present.
Do not enable Play just because an archive linked or an inventory detected files.
