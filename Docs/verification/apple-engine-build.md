# Apple engine compilation

[GitHub Actions run 38949046447](https://github.com/Lupc9102/stalker-ios/actions/runs/38949046447)
passed on 16 October 2026 for commit `1b57a79`.

- Runner: macOS 15, ARM64; Xcode 16.4 (16F6).
- Native engine and host compiled; both registered tests passed.
- Actual engine main ran on Apple Silicon and reached the expected missing-data
  boundary. This test used an empty game folder.
- The engine and native GLES/drawable host cross-compiled for iPhone ARM64.
- `lipo` identified both `libxray_aot.a` and `libzone_native_host.a` as ARM64.

This establishes compilation and native Mac startup. It does not establish a
rendered iPhone game frame, app integration, level loading or device performance.
