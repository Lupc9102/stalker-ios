# Native engine host

The engine now executes its real constructors and main on Linux x86_64 without
JIT. With an empty game folder it exits at missing `fsgame.ltx`. With the source
repository's filesystem config it mounts the native folder, enumerates files,
writes an OpenXRay log into a separate app-data overlay. With the official free
CoP benchmark and the source project's GL shaders it reads four archives,
enumerates about 48,000 files, selects the renderer and creates a native GLES
context. No game frame has been rendered yet.

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
  identifies 451 implemented entry points and 38 unsupported imports when the
  optional GLES backend is enabled. Coverage is not gameplay validation.
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

## Native graphics test

On Linux, install EGL/GLES development headers plus a working Mesa driver, then:

```sh
python3 Scripts/native_host.py Engine/Generated Engine/Inputs/xr_3da.js --gles
cmake -S Engine -B Engine/Build -DZONE_NATIVE_GLES=ON
cmake --build Engine/Build --target zone_native_gles_test zone_native_boot -j 3
Engine/Build/zone_native_gles_test /tmp/triangle.ppm
```

The test uses the actual memory64 module and native EGL/GLES, compiles and links
shaders, uploads vertices and uniforms, draws a triangle, checks pixels read from
the framebuffer, and tests opaque GPU sync handles. Mesa llvmpipe passed this
test. This validates the graphics bridge, not an engine-rendered game frame or
iPhone GPU performance. GLES bindings are generated from the Khronos header in
`Engine/ABI/GLES3.h`; pointer-bearing calls require explicit bounds recipes.

Imported procedures in WABT 1.0.42's static function table receive the wrong
namespace context. `patch_generated.py` corrects the 291 imported entries from
their emitted metadata while preserving internal engine function contexts. The
graphics test calls through that real table, as GLAD does, to catch regressions.

The original generated runtime leaks its call-depth counter when exceptions
unwind native C frames. A minimal module reproduced a leaked depth after its
first catch. `patch_exception_depth.py` saves depth on entering a try region and
restores it in its catch path, including unmatched tags and rethrows. The
generated regression fixture passes 10,000 nested catch/rethrow rounds.
Full-engine startup with this correction is being tested.

The earlier default 500-call limit stopped during Lua binding registration.
Generated prologues now check the native thread's actual stack boundary, with
128 KiB kept for trap handling, and retain a 4096-call cap. Live-runtime yields
restore the call-depth baseline. The higher limit is being tested along the
real startup path; raising it alone does not establish scripting correctness.

`GraphicsIOS.m` supplies an EAGL/ES 3 provider for a caller-owned CAEAGLLayer.
It draws at game resolution into a separate framebuffer, scales into the phone
drawable at presentation and restores framebuffer/scissor state. It is not yet
connected to the app and still requires an Apple compile/device check.

Only reviewed native extensions are exposed. Browser-only base-vertex, polygon
mode and timer-query APIs remain unsupported; they are not advertised. Native
GLES is the initial iOS provider; ANGLE/Metal is a possible later provider. DXT
fallbacks and real game shader/texture compatibility still need validation.

The existing app still links only its input layer. Native graphics, engine
lifetime, game-file access grants and touch/controller delivery are still
necessary for a playable iPhone build. Loading a retail level is untested.
