# Physical iPhone startup diagnostics

On 18 October 2026, the first reported iPhone startup attempt stopped with
`Invalid call_indirect or return_call_indirect`. The failure alert pointed to
`ZonePortData/_appdata_/logs`, but that directory had no log. This is a real
device startup failure; the earlier world/gameplay captures were Linux and
the earlier UIKit engine captures were simulator menu tests.

## Missing log cause and diagnostic build

Before `8bcec07`, stdout/stderr redirection was compiled only for the simulator
and activated only by its smoke-test argument. Physical devices therefore did
not save `engine-native.log`. X-Ray's separate logger can also remain absent
if startup traps before it initializes.

Diagnostic v0.1.2 writes an initial `Documents/engine-native.log` before
prepared-file checks and captures native stdout/stderr before engine setup.
An engine failure also writes `Documents/engine-failure.txt`. The failure alert
offers **Share diagnostics** for both files; they are visible directly in
**Files → On My iPhone → ZonePort**. A rejected second session cannot rotate
away the original native log. A new app launch/start preserves one previous
native log.

The generated engine's checked indirect calls now report the generated caller,
table index and size, rejection reason, and expected/actual function-type
hashes. Host-invoked callbacks use the same diagnostics. All original bounds,
null and signature checks remain enabled. Startup stages and a native failure
backtrace are also recorded. This change does not establish the cause or fix
of the physical-device trap.

## Verification

- [iOS run 39129511086](https://github.com/Lupc9102/stalker-ios/actions/runs/39129511086)
  at `8bcec07` builds and verifies the unsigned ARM64 device package and builds
  the simulator host in Release. The local-folder/foreground-discovery test
  passes. The explicit early-trap test also passes: before engine main, it
  rejects index `4294967295`, traps, and saves both diagnostic files, including
  the rejected index, reason and native backtrace. This injected failure is
  separate from the phone's as-yet-unidentified failure.
  The entire workflow succeeds, including visible native benchmark-menu
  rendering, prepared override execution and same-process/fresh-frame
  background/resume checks. Its final report has 334 callbacks, phase 2, a
  visible engine surface and a hidden loading view. The game readback has
  779,806 lit pixels out of 921,600 with no GLES error. No private retail
  campaign data is used in that simulator check.
- [Native host run 39129984401](https://github.com/Lupc9102/stalker-ios/actions/runs/39129984401)
  at `ade6551` passes all six tests and iPhone ARM64 cross-compilation. The new
  generated-WAT fixture checks that a wrong function signature and an invalid
  table index still trap and produce the correct diagnostics. `ade6551` only
  adds a missing runtime header to that test; app code matches `8bcec07`.
- The extracted IPA is 47,393,314 bytes, SHA-256
  `30eedb2fd2ffaadcc84fb68c422939ac930f5007664a45b6aa156838545b311a`.
  Local packaged ARM64, landscape, fullscreen, Files and app-icon checks pass.
  Its support manifest matches the existing private prepared game pack.

Install the diagnostic IPA over the existing app, keeping its game files.
Reproduce once and share the diagnostic files before another startup attempt.
Physical-device menu rendering, level loading and gameplay remain unverified.
