"""Decode private BC7_UNORM textures into legacy RGBA8 DDS for mobile GLES.

Uses Pillow's offline BC7 decoder, retains existing mip levels, and never runs
on the phone. No resizing or new lossy compression is performed. Supports 2D
textures and complete cubemaps; originals remain unchanged.
"""
import argparse
import ctypes
import ctypes.util
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tempfile
from PIL import Image
from xray_archives import Archive, decoder


def convert(data, maximum=512):
    if len(data) < 148 or data[:4] != b'DDS ' or data[84:88] != b'DX10':
        return None
    if struct.unpack_from('<I', data, 4)[0] != 124 or struct.unpack_from('<I', data, 76)[0] != 32:
        raise ValueError('Invalid DDS header sizes')
    fmt, dimension, misc, array, _ = struct.unpack_from('<5I', data, 128)
    if fmt != 98:  # BC7_UNORM; do not silently lose sRGB metadata.
        return None
    if dimension != 3 or array != 1 or struct.unpack_from('<I', data, 24)[0] > 1:
        raise ValueError('Unsupported BC7 texture array/volume')
    height, width = struct.unpack_from('<II', data, 12)
    count = struct.unpack_from('<I', data, 28)[0] or 1
    if not width or not height or max(width, height) > 32768 or count > max(width, height).bit_length():
        raise ValueError('Invalid BC7 dimensions/mip count')
    cube = bool(misc & 4)
    if cube and width != height:
        raise ValueError('Non-square BC7 cubemap')
    extents, sizes = [], []
    for mip in range(count):
        w, h = max(1, width >> mip), max(1, height >> mip)
        extents.append((w, h)); sizes.append(((w + 3) // 4) * ((h + 3) // 4) * 16)
    faces, face_bytes = (6 if cube else 1), sum(sizes)
    if len(data) != 148 + faces * face_bytes:
        raise ValueError('Incomplete or unexpected BC7 payload')
    drop = 0
    while drop < count - 1 and max(extents[drop]) > maximum:
        drop += 1
    output = bytearray()
    for face in range(faces):
        offset = 148 + face * face_bytes
        for mip, ((w, h), size) in enumerate(zip(extents, sizes)):
            if mip >= drop:
                header = bytearray(data[:148])
                struct.pack_into('<II', header, 12, h, w)
                struct.pack_into('<I', header, 20, size)
                struct.pack_into('<I', header, 28, 1)
                struct.pack_into('<II', header, 108, 0x1000, 0)
                struct.pack_into('<I', header, 136, 0)  # One 2D face for Pillow.
                with Image.open(io.BytesIO(header + data[offset:offset + size])) as image:
                    if image.size != (w, h) or image.mode != 'RGBA':
                        raise ValueError('Unexpected BC7 decoder output')
                    output.extend(image.tobytes())
            offset += size
    w, h = extents[drop]; remaining = count - drop
    header = bytearray(128); header[:4] = b'DDS '
    flags = 0x100F | (0x20000 if remaining > 1 else 0)
    struct.pack_into('<7I', header, 4, 124, flags, h, w, w * 4, 0, remaining)
    struct.pack_into('<8I', header, 76, 32, 0x41, 0, 32, 0xFF, 0xFF00, 0xFF0000, 0xFF000000)
    caps = 0x1000 | (8 if cube or remaining > 1 else 0) | (0x400000 if remaining > 1 else 0)
    struct.pack_into('<II', header, 108, caps, 0xFE00 if cube else 0)
    return bytes(header) + output, {'dimensions': [w, h], 'faces': faces, 'mips': remaining,
                                   'dropped_mips': drop, 'format': 'RGBA8_UNORM'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--max-size', type=int, default=512)
    parser.add_argument('--lzo-library', default=ctypes.util.find_library('lzo2'))
    args = parser.parse_args()
    if args.max_size < 64 or args.max_size > 4096 or args.max_size & (args.max_size - 1):
        raise SystemExit('--max-size must be a power of two from 64 to 4096')
    output = args.output_dir.resolve()
    if output.exists():
        raise SystemExit('Choose a new output directory; originals were left untouched')
    if not args.lzo_library:
        raise SystemExit('Install liblzo2 or provide --lzo-library')
    lzo = ctypes.CDLL(args.lzo_library)
    lzo.lzo1x_decompress_safe.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p,
                                       ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p]
    lzhuf, records = decoder(), {}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-bc7-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'; staging.mkdir()
        for path in sorted(args.input_root.resolve().rglob('*')):
            if not path.is_file() or path.is_symlink() or not re.search(r'\.db\d*$', path.name, re.I):
                continue
            archive = Archive(path, lzhuf, lzo)
            for name, meta in archive.entries.items():
                member = PurePosixPath(name)
                if not meta[1] or member.suffix.lower() != '.dds' or not name.startswith('textures/'):
                    continue
                if member.parts[1].lower() in {'ui', 'fonts'}:
                    continue
                original = archive.read(name)
                result = convert(original, args.max_size)
                if result is None:
                    continue
                data, record = result
                target = staging / 'gamedata' / member
                target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
                record.update({'sha256': hashlib.sha256(data).hexdigest(), 'source_sha256': hashlib.sha256(original).hexdigest()})
                records[name] = record
                print(f'Decoded {name}: {record["faces"]} faces, {record["mips"]} existing mips', flush=True)
        (staging / 'bc7-overlay.json').write_text(json.dumps({'max_size': args.max_size, 'files': records}, indent=2) + '\n')
        staging.rename(output)
    print(f'{len(records)} BC7 textures decoded offline; originals unchanged.')


if __name__ == '__main__':
    main()
