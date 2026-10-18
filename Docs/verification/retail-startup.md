# Retail-data startup investigation

The player's supplied archive contains **Call of Pripyat Enhanced Edition**
data, rather than the original/classic release. Only its 13 data archives were
extracted for this test. ZIP CRCs were checked during extraction; inspected
archive members were also checked against their stored CRCs. Windows binaries
were not executed. Original game archives remain unchanged and private.

The native Linux engine mounts all 13 archives and reports 72,962 cached files.
This establishes archive-reading compatibility, not campaign compatibility.

## GLES shader repairs

Startup initially reports four shader compilation failures. Three sun shader
variants compare an undefined `SUN_QUALITY` macro under the minimum preset.
GLES requires a definition. The SSAO shader also adds integer `1` to float `0.3`,
which GLSL ES 3.00 rejects.

`prepare_support_data.py` now supplies a guarded `SUN_QUALITY=0` default and
changes that SSAO literal to `1.0`. Both patches require exactly one matching
source fragment in the pinned public support files. The manifest hashes the
resulting files and records the mobile-shader revision. Repeating native startup
with the same game archives removes all four compiler failures.

## Duplicate info-ID trap

The next trap occurs in `func[37156]`, the info-portion instantiation of
`CSXML_IdToIndex::InitInternal`. A temporary Linux diagnostic captured the
native stack and the current XML filename/ID. The failing ID is
`jup_b208_burers_hunt_done`, present twice in `info_jupiter.xml` (lines 16 and
229 in the supplied data). The inspected XML passed its archive CRC check.

At support-source commit `fd5baa6859561a2968098f829aeeb33975929c7e`,
`src/xrServerEntities/xml_str_id_loader.h` intends to log and skip duplicate IDs.
Its diagnostic passes an `xr_string` object through varargs instead of using
`.c_str()`. The pinned compiled snapshot contains an unconditional `unreachable`
on that duplicate path. Removing the extra controller-script registration did
not resolve this independent trap.

`patch_engine_snapshot.py` repairs this one path **before wasm2c translation**:

- Original snapshot SHA-256:
  `db894e66ec1b60c8c52bb1b3764e83f3e2131fbc6d56e0b309f5af1e08cf0b42`.
- At file offset `0xcda9bc`, change the `br_if` depth from 1 to 5. Full input
  hash, surrounding instruction bytes and full output hash are checked.
- The old branch targets the block ending at `0xcdaa71`, immediately before
  the broken diagnostic's trap. The new branch targets the block ending at
  `0xcdaacb`, after insertion and the info-index increment. Execution then
  increments the XML-node iterator and continues normally.
- Consequently the first ID is retained, the duplicate is skipped, and neither
  the vector end nor the info-ID index advances for a duplicate. Temporary
  comparison references have already been released before this branch.
- Repaired snapshot SHA-256:
  `908735569303555a54a2c03fc8f094f119b8d3cf767478fbfa62a4381ae508b0`.

The original downloaded snapshot stays intact. Custom `--wasm` builds are not
patched. The final iOS app still executes ahead-of-time compiled native code;
this repair introduces no runtime code generation or JIT.

## Current verification

A separate copy of the previously built native Linux executable was used to
test the equivalent branch repair directly. The conditional jump at native
address `0x2fddfd2` was redirected from `0x2fde3e7` (trap) to `0x2fde39b`
(XML-node increment), as checked against its generated-function disassembly.
This diagnostic changes no other engine code or game data.

With both shader repairs and that equivalent native branch repair, the engine
yields into its real frame loop, renders 80 frames and captures a 1280 × 720
framebuffer. Visual inspection shows the game backdrop and cursor; menu labels
are not visible. This is **not** a verified working menu or playable campaign.

The complete reproducible path now also passes:
[Linux run 39050698557](https://github.com/Lupc9102/stalker-ios/actions/runs/39050698557)
at `5ba6be8` translates the repaired snapshot, compiles the engine and passes
native service/GPU tests. Its downloaded executable reproduces 80 frames with
the player's unchanged archives and committed support shaders, without the
temporary native executable repair. Coverage metadata records the repaired
snapshot hash. The artifact ZIP's verified SHA-256 is
`5c72fc51e0cd2d67e289675c91e8bd446f3424042833ff72f877b3b14491cf2b`.

[iOS run 39050698630](https://github.com/Lupc9102/stalker-ios/actions/runs/39050698630)
at the same commit passes device/simulator compilation, actual UIKit menu
screenshots, and the same-process background/resume check. That test uses the
official free benchmark, not the private Enhanced Edition archives. See the
[iOS runtime record](native-ios-runtime.md).

## Font-mask compatibility

The inspected Enhanced Edition UI fonts use BC3/DXT5 textures with zero RGB
and glyph coverage in alpha. The pinned `hud_font.ps` samples red, so ordinary
menu labels are transparent. Sampling alpha in a private shader override makes
those labels visible; the device's default shader should not be changed this
way because classic data uses a different font format.

The optional `Scripts/convert_font_masks.py` instead creates loose L8 DDS
overrides from extracted, colorless BC3 font textures. GLI maps L8 to red, which
the existing shader expects. It preserves the decoded base-level mask byte for
byte, without resizing. Other texture formats or nonzero RGB endpoints are
skipped, malformed/truncated inputs are rejected, existing output directories
are refused, and originals are never changed. Output is staged before being
published and includes source/result hashes. Only base levels are retained.

All 136 converted masks in this test match an independent Pillow alpha decode
exactly; 22 other font files were skipped. A selected atlas also matched the
converter's current output exactly, and a truncated texture was rejected.
Repeating the 80-frame native test with these loose L8 masks and the unchanged
committed shaders makes the ordinary menu labels visible. The selected first
menu entry remains invisible, and Enhanced Edition's extra menu actions have
not been validated. This converter is a manual diagnostic tool; automatic iOS
archive extraction/font conversion is not implemented. No font assets are
committed or included in the IPA.

## Campaign boundary

The temporary `user.ltx` command
`start server(all/single/alife/new) client(localhost)` exercises real campaign
startup. Object/model/texture prefetch completes, then the supplied
`sound_theme.script` fails because `xr_sound_impl` is absent from this engine.
The supplied `xr_sound.script` and seven related scripts depend on that newer
Enhanced Edition sound binding. They are not ordinary missing texture files.

Private compatibility diagnostics using original implementations extracted
from GSC's free benchmark get further. Restoring those eight sound-related
scripts reaches a missing `get_cached_ini` call. A real Lua INI cache adapter
then allows 6,464 spawn points to load. Additional logging/game-graph adapters
reach NPC creation, where Enhanced Edition expects `get_platform_id` and
`platform_ids`. Replacing the entire benchmark script set instead fails an
object-creation assertion. These diagnostic overlays are not shipped fixes or
evidence of a playable campaign.

Retail-level rendering, saves, combat and physical iPhone performance remain
unverified. Enhanced Edition also has unsupported `mtb_*` renderer commands,
blender names and changed scripts/UI. The original/classic CoP 1.6.02 data is
still needed for the intended campaign baseline; Enhanced Edition support is a
separate compatibility effort.
