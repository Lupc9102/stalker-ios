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

The repaired Wasm input has passed its hash and instruction checks. A fresh
translation/build and runtime test of that generated executable remain necessary
to confirm the complete reproducible build path. Retail-level loading, saves,
combat and physical iPhone performance remain unverified. Enhanced Edition has
additional renderer/configuration differences, including unsupported `mtb_*`
commands and blender names; rendering the backdrop does not establish full
Enhanced Edition support.
