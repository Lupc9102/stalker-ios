# Native engine device app

[Run 39006368982](https://github.com/Lupc9102/stalker-ios/actions/runs/39006368982)
passed for commit `0626b86` on 17 October 2026. This is the first verified device
app that links the actual engine rather than only the controls-practice layer.

- Xcode 16.4 on the macOS 15 ARM64 runner built the engine/host archives and the
  UIKit/Objective-C/Swift integration for iPhone ARM64, targeting iOS 17+.
- Executable checks found defined native engine/session symbols. App C symbols
  use hidden visibility, so verification includes defined local symbols rather
  than looking only at exported symbols.
- Source support shaders/scripts, the filesystem config and mobile profile
  were present. The app contained no WASM/JavaScript runtime, Windows binaries
  or game archives.
- The unsigned IPA passed the existing ARM64, landscape, Info.plist and Files
  integration checks.

The device build/upload steps of [run 39007060588](https://github.com/Lupc9102/stalker-ios/actions/runs/39007060588)
also passed for `1319ed7`, which preserves UI default bindings and adapts touch
to the main menu's animated selector. Its simulator runtime test is in progress.
This record establishes compilation and packaging, not physical-device
gameplay, level loading or performance.


## Visible native menu build

[Run 39026671344](https://github.com/Lupc9102/stalker-ios/actions/runs/39026671344)
for `5acffea` also passed device and simulator compilation. Unlike the earlier
frame-counter smoke test, its simulator diagnostics include the actual CoP
menu visibly composited in UIKit. See [the runtime record](native-ios-runtime.md)
for framebuffer counts and the separate screenshot-verifier failure.

Its unsigned `ZonePort-Native.ipa` is 41,341,843 bytes, SHA-256
`4f339fd7627ef844701db0b66a8154765fd5396dbc07cc27e20f9955ba7e2afc`.
Downloaded artifact bytes matched the GitHub artifact digest, and local package
verification passed ARM64, landscape, fullscreen and Files checks. No WASM,
JavaScript runtime, Windows executable or game archive is packaged. This is
still simulator menu evidence, not physical iPhone gameplay validation.


The follow-up `ae1e908` device artifact from
[run 39028193756](https://github.com/Lupc9102/stalker-ios/actions/runs/39028193756)
passed the same package checks: 41,342,199 bytes, SHA-256
`068c0cf628e0e083f43663cf3c5f3307659857ab889645ae318d24451ff595f3`.
Its only source changes are in verification scripts. The run also compiles the simulator app and type-checks the screenshot
verifier before running the engine.


The stronger simulator check in
[run 39028985702](https://github.com/Lupc9102/stalker-ios/actions/runs/39028985702)
passed for `a26a064`: process identity stayed unchanged across backgrounding,
30 or more new frame callbacks completed after foregrounding (240 → 274),
and both actual screen checks passed. Engine/app source is unchanged from the
shared `ae1e908` test IPA; these later changes only strengthen verification.
