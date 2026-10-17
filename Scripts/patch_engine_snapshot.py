"""Restore the pinned engine's intended handling of duplicate info IDs.

The source's duplicate-ID diagnostic passes an xr_string through varargs.
Clang emits an unconditional trap for that call. Skip the duplicate as the
source intends, retaining the first entry and leaving retail data untouched.
This is a build-time input repair before wasm2c, never runtime code generation.
See Docs/verification/retail-startup.md for the reviewed control-flow targets.
"""
import hashlib
import json
from pathlib import Path


SOURCE_SHA256 = 'db894e66ec1b60c8c52bb1b3764e83f3e2131fbc6d56e0b309f5af1e08cf0b42'
OUTPUT_SHA256 = '908735569303555a54a2c03fc8f094f119b8d3cf767478fbfa62a4381ae508b0'
OFFSET = 0xCDA9BC


def prepare_mobile_snapshot(source: Path, destination: Path):
    data = bytearray(source.read_bytes())
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise ValueError('Snapshot repair requires the reviewed, pinned engine hash')
    before = bytes.fromhex('0b20062903082004520d010b200142003703')
    if data[OFFSET - 10:OFFSET + 8] != before:
        raise ValueError('Duplicate-info branch changed; review the engine repair')
    # func[37156], br_if 1 -> br_if 5: bypass the broken diagnostic and
    # insertion, then advance the XML-node iterator normally. Do not advance
    # the info-ID index or the vector end for a skipped duplicate.
    data[OFFSET] = 5
    if hashlib.sha256(data).hexdigest() != OUTPUT_SHA256:
        raise ValueError('Unexpected repaired engine hash')
    if not destination.exists() or destination.read_bytes() != data:
        destination.write_bytes(data)
    destination.with_suffix('.patches.json').write_text(json.dumps({
        'source_sha256': SOURCE_SHA256,
        'output_sha256': OUTPUT_SHA256,
        'patches': [{'name': 'skip-duplicate-info-id', 'function_index': 37156,
                     'offset': OFFSET, 'before': 1, 'after': 5}],
    }, indent=2) + '\n')
    print('Prepared pinned engine repair: skip duplicate info IDs; no retail data changed.')
    return destination
