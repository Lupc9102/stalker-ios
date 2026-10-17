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
