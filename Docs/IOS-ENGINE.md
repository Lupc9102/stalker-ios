# Native engine app bring-up

`project-engine.yml` and `Scripts/build_native_ios.sh` build a separate unsigned
device IPA that links the ARM64 engine and native host archives. The original
`project.yml` remains the smaller launcher/controls-practice build. Native app
compilation and device behavior must be verified separately; adding this target
is not a device-playability result.

The native app bundles pinned source shaders/scripts, a filesystem config and
an initial 720p/Minimum mobile profile. It bundles no WASM/JavaScript engine,
Windows binaries or game archives. The player selects their original CoP
installation. Support files and later engine writes live in
`Documents/ZonePortData`; native file services keep the selected originals
read-only. The security-scoped folder grant lasts for the native session.

The engine owns an off-main pthread with a 16 MiB stack and the fixed 2 GiB
logical heap. Worker threads share that heap. GLES renders to its own
framebuffer and presents into a retained CAEAGLLayer, preserving aspect ratio.
BC1/2/3 texture uploads decode when the native device lacks the PC format.
This compatibility path increases texture memory; phone asset optimization
and level memory budgets are not established yet.

Touch controls retain the existing customizable layout. Keyboard/mouse events
are constructed in the pinned guest ABI on the owning engine thread. A small
native pointer queue preserves direct menu taps; action edges are retained
across frames. Controller sticks/buttons feed the same input hub. Menu touches
account for the game's letterboxed rectangle. The Controls button opens the
editor/settings or sends Escape to the actual game menu.

Pause requests reach the engine at generated function checkpoints, graphics
calls, sleep slices and periodic atomic-wait checkpoints. Atomic waits retain
their registration and release the shared queue mutex while paused, allowing
notifications to arrive. The owner finishes/releases its GLES context and
mutes the OpenAL listener before acknowledging pause. These paths have native
unit/GPU checks; UIKit background behavior still needs physical-device testing.

This first app integration permits **one session per app process**. A stopped
session retains its shared heap, module/worker records, file grant and layer.
A stop request parks the owner rather than longjmp out of a registered atomic
wait or free memory that workers may still reference. Normal engine exit and
fatal errors return a message requiring app relaunch. Cooperative worker
shutdown and safe in-process restart remain future work.

The standalone Linux engine has rendered the real main menu with native BC
support and with forced BC decoding. Full retail levels, saves, combat, iPhone
performance and sustained memory use remain unverified. The app target's
workflow verifies that real engine symbols and support data are present in the
packaged executable; it is not a substitute for those runtime tests.
