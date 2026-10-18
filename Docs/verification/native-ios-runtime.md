# Native iOS runtime verification

The connected ARM64 simulator app executes the translated engine with native
GLES, OpenAL, threads and file services. No browser or JIT executes the engine.
Test archives come from GSC's free benchmark and remain outside the app/IPA.

## Visible UIKit rendering

[Run 39026671344](https://github.com/Lupc9102/stalker-ios/actions/runs/39026671344)
at `5acffea` compiled both the device and simulator apps. Its diagnostics
establish actual rendering in three places:

| Capture | Dimensions | Non-black pixels |
| --- | --- | --- |
| Engine game framebuffer | 1280 × 720 | 779,803 / 921,600 |
| iOS drawable framebuffer | 2622 × 1206 | 2,209,182 / 3,162,132 |
| Simulator app screenshot | 1206 × 2622 | Visually inspected: real CoP menu and UIKit Controls button |

Both framebuffer readbacks reported no GLES error. The full simulator screenshot
contains the game artwork and menu inside the actual app. The simulator writes
its screenshot in the device's portrait pixel coordinates; its visible UI is
landscape. The scene comes from the real engine, not a launcher backdrop.

Presentation now samples the game color texture with a fullscreen GLES draw,
forcing alpha to one, and explicitly flushes Core Animation transactions on
the engine pthread. That thread has no Cocoa run loop. Earlier blit-based
presentation produced valid game readbacks but black UIKit screenshots; alpha
alone did not fix it. These presentation changes were tested together, so the
individual effect of the draw and transaction flush has not been isolated.

The runtime step in that run failed in the screenshot verifier itself: it used
an unavailable AppKit initializer. `ae1e908` switches to `NSBitmapImageRep(data:)`
and type-checks the verifier before the expensive engine builds.

[Run 39028193756](https://github.com/Lupc9102/stalker-ios/actions/runs/39028193756)
for `ae1e908` completed successfully, including both real simulator screenshots
and their screen-content checks. The app was foregrounded after Settings at
11:29:04 UTC with 383 reported frame callbacks; the final diagnostic report
contained 534 callbacks and phase 2 (running). Both screenshots visibly contain
the engine menu and UIKit Controls button.

That test used a pre-background frame baseline, allowing earlier frames to
satisfy its post-resume wait. The later diagnostic count establishes continued
rendering in this run, but `a26a064` strengthens the automated gate: it compares
simctl's process identity across background/resume and waits for 30 new
callbacks beyond the count observed after foregrounding.

[Run 39028985702](https://github.com/Lupc9102/stalker-ios/actions/runs/39028985702)
for `a26a064` passed that stronger gate. The same simctl-reported app process
survived the Settings round trip, and frame callbacks advanced from the
post-foreground baseline of 240 to 274 before the resumed screenshot. Both
actual screenshot-content checks passed. Its game readback contained 779,808
non-black pixels; its drawable contained 2,209,185. The verification-only source
changes do not alter the engine/app code in the shared `ae1e908` test IPA.
Selected CI output is preserved in [native-ios-resume.log](native-ios-resume.log).

## Earlier checks and control mode

[Run 39050698630](https://github.com/Lupc9102/stalker-ios/actions/runs/39050698630)
at `5ba6be8` passes the same complete device/simulator and UIKit runtime checks
with the repaired engine snapshot and mobile shader fixes. The app process
survives background/resume, and fresh callbacks advance from 278 to 310 after
foregrounding. Both screenshot-content checks pass. The final report has 553
callbacks, phase 2, a visible surface and a hidden loading view. Game/drawable
readbacks contain 779,808 and 2,209,185 non-black pixels respectively, with no
GLES errors. Actual menu and resumed screenshots were inspected. These use
GSC's free benchmark; private Enhanced Edition campaign data is not in CI.

[Run 39024669702](https://github.com/Lupc9102/stalker-ios/actions/runs/39024669702)
at `9c1787b` first established real iOS game-framebuffer output. Its system-cursor
flag was false while the main menu was visible: CoP draws its own cursor. That
flag cannot select touch-control modes. The app therefore starts with direct
menu taps; Controls → Show game controls enables the customizable gameplay HUD,
and Use game menus restores direct tapping.

Frame callback counts alone produced a misleading pass in an earlier smoke
test. The current test checks RGB content in the game and drawable readbacks,
visibility/loading state, and the actual simulator screenshot. It then
backgrounds the app, returns, waits for more frames and verifies another screen.

## Additional build checks

[Run 39103015993](https://github.com/Lupc9102/stalker-ios/actions/runs/39103015993)
at `055de63` passes device/simulator compilation, both actual screenshot checks
and the same-process/fresh-frame background/resume gate with bulk prefetch
disabled. The final diagnostic has 497 callbacks, phase 2, a visible surface
and a hidden loading view. Game and drawable readbacks again report 779,808 and
2,209,185 non-black pixels with no GL errors. The actual menu screenshot was
visually inspected. The unsigned IPA is 41,343,013 bytes, SHA-256
`38b00ccf25325826d091930058fa7dfd8a417c491058ad14a8d95124b12dbfc4`;
packaged ARM64, landscape, full-screen and Files checks pass. This uses the
official benchmark, not the private campaign compatibility overlay.

[Run 39105956344](https://github.com/Lupc9102/stalker-ios/actions/runs/39105956344)
at `e0fd8f3` passes the complete device/simulator and background/resume workflow
with prepared-file verification enabled. A public support script is modified
in a fixture profile outside the app bundle. The app verifies its manifest,
the test reads back the exact installed script hash, and the real engine emits
`Prepared profile override loaded` through the unconditional `log1` binding.
Both actual screenshots and the same-process/fresh-frame resume gate pass.
The final report has 542 callbacks, phase 2, a visible surface and a hidden
loading view. Game/drawable readbacks contain 779,803 and 2,209,182 non-black
pixels with no GL errors. The actual final simulator screenshot was inspected.

The unsigned IPA is 41,356,722 bytes, SHA-256
`556c16f3422f61cd79864dec4be3e05dfea7d3f49b7850a3e47e2b39cf6723f1`.
Its packaged ARM64, landscape, full-screen and Files checks pass. The bundled
support-manifest hash matches the private prepared data pack. The diagnostics
ZIP has SHA-256 `24f8ff916a1ee1fb04146f674deada227292f6cd768ce6739b631e2171bcb4f2`.

Earlier fixture checks used `printf`, then `log`, which do not emit this
marker's message in the release snapshot. Those runs reached the menu but failed
the additional execution assertion. `log1` is verified both in a separate native
Linux benchmark run and in the successful UIKit run. This fixture contains
public support source, not the player's private campaign archives.

## Limits

Physical iPhone gameplay, iOS retail-world loading, iOS save/reload, combat,
sustained performance and device memory use remain unverified. This integration retains one
engine session per app process; exiting a session requires relaunching the app.
The simulator's Apple software renderer is not evidence of iPhone GPU speed.
