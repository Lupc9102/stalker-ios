# iOS build verification — 2026-10-16

[Successful Xcode run](https://github.com/Lupc9102/stalker-ios/actions/runs/38924371922)
from source commit `83c1a77386cd2db998ddab0c9db3d3cb2575ec77`.

| Check | Result |
| --- | --- |
| Environment | GitHub macOS 15 runner, Xcode 16.4 (16F6), iPhoneOS 18.5 SDK |
| Device application | Release ARM64 build passed; unsigned IPA packaged |
| Simulator application | Debug build passed |
| Real app launch | Launcher, editor and practice controllers captured on iPhone 16 Pro simulator |
| Native input tests | Tap ordering, bounds, look-delta consumption, reset and overflow passed |
| Wasm parser tests | Four Python tests passed |
| Packaged metadata | Full-screen landscape, launch-screen metadata and Files integration passed |

## Artifact

Download `ZonePort-iOS` from the linked run. It contains `ZonePort.ipa` and three
simulator PNG captures. The app is version 0.1.0 (1), minimum iOS 17.0.
Sign the IPA with a sideloading tool before installing it on a phone.

- IPA size: 462,099 bytes.
- IPA SHA-256: `4b3b04e63da4334208a181e0013dcccb4727a7356c6c0fbbba3ffdcb7c009f3a`.
- No retail game data or translated engine archive is included. Its small size
  does not represent a compressed game installation.

Visual inspection confirmed that the launcher uses the modern full-screen
landscape area, avoids the camera cutout, and displays both mode titles. The
editor has readable profiles and labels, plus a collapsible panel for reaching
controls underneath it. The first capture exposed overwritten Info.plist
metadata; the project now uses the checked-in plist directly and validates the
packaged result.

## Limits

The captures open each real controller with Debug launch arguments. They verify
rendering and app startup, not automated navigation, multitouch behavior,
controller hardware or file-picker access. No physical iPhone install or touch
test has been performed here.

This is a native launcher and controls-practice application. It does not run
CoP, instantiate the engine on iOS, render an engine frame or validate any game
archives in gameplay. See [STATUS.md](../../STATUS.md) and
[the engine boundary](../ENGINE-HOST.md) before evaluating engine progress.
