# Native engine host

The engine now executes its real constructors and main on Linux x86_64 without
JIT. With an empty game folder it exits at missing `fsgame.ltx`. With the source
repository's filesystem config it mounts the native folder, enumerates files,
writes an OpenXRay log into a separate app-data overlay and exits at missing
`gamedata/configs/system.ltx`. No game frame has been rendered.

## Reproduce

The host needs a C compiler, CMake, pthreads and OpenAL development headers/library.
On macOS it uses the system OpenAL framework. On Linux, OpenAL Soft provides the
API; its `null` output driver is useful on runners without audio hardware.

```sh
python3 Scripts/prepare_engine.py
python3 Scripts/native_host.py Engine/Generated Engine/Inputs/xr_3da.js
cmake -S Engine -B Engine/Build -DCMAKE_BUILD_TYPE=Debug
cmake --build Engine/Build -j 3
ctest --test-dir Engine/Build --output-on-failure
mkdir -p /path/to/separate-writable-appdata
Engine/Build/zone_native_boot /path/to/game-folder /path/to/separate-writable-appdata
```

`ALSOFT_DRIVERS=null` selects the real OpenAL Soft headless backend for CPU tests.
The executable is a startup diagnostic. Worker records remain process-owned;
process exit cleans them up. Cooperative shutdown, frame scheduling and UIKit
input delivery are required before safe app integration and engine restarts.

## Native services

- Typed bindings match the pinned Wasm64 ABI. Unsupported imports trap by name;
  there are no graphics success stubs. The generated coverage file currently
  identifies 124 implemented entry points and 365 unsupported imports.
- POSIX clocks, entropy, timezone data, heap growth, native logging and exit.
- Per-thread module instances, guest stack/TLS initialization, actual pthreads,
  mailbox checks and WasmFS worker proxy queues. Shared memory is imported once.
- Native OPFS replacement: descriptor-relative directory traversal, read-only
  game files and a separate copy-on-write overlay. Shared access handles observe
  writes, use 64-bit offsets and recycle IDs. Rename/removal remain unported.
- All 29 imported OpenAL calls forward to native OpenAL. Opaque device/context
  handles are validated; strings and arrays are marshalled into guest memory.
- Native event registration is stored with a checked dispatcher for the owning
  engine thread. UIKit delivery and cross-thread event routing remain pending.
- Reviewed EM_ASM sites for errors, timing registration and raw-look registration
  use native operations. Unknown embedded-script sites trap.

Tests cover copy-on-write without modifying originals, shared handles, reads
above 4 GiB, parallel reads, path/symlink containment, 70,000 handle cycles, and
real OpenAL context/PCM/source queue operations using the null backend.

## Apple verification

`.github/workflows/native-engine.yml` builds/tests the host on macOS, runs real
engine main against an empty directory, and cross-compiles the engine and host
archives for iPhone ARM64. That workflow must pass before claiming Apple
compilation. Its diagnostic artifact is not an IPA.

The existing app still links only its input layer. Native graphics, engine
lifetime, game-file access grants and touch/controller delivery are still
necessary for a playable iPhone build. Loading a retail level is untested.
