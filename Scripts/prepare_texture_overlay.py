"""Select existing BC texture mipmaps for private mobile compatibility tests.

This does not recompress pixels. Original archives remain unchanged; UI atlases,
cubemaps, volume textures and unsupported formats are left alone. Requires the
pinned decoder source and liblzo2 used by xray_archives.py.
"""
import argparse
import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tempfile
from xray_archives import Archive, decoder


def select_mips(data, maximum):
    if len(data) < 128 or data[:4] != b'DDS ':
        raise ValueError('Invalid DDS header')
    if struct.unpack_from('<I', data, 4)[0] != 124 or struct.unpack_from('<I', data, 76)[0] != 32:
        raise ValueError('Invalid DDS header sizes')
    height, width = struct.unpack_from('<II', data, 12)
    if not width or not height or width > 32768 or height > 32768:
        raise ValueError('Invalid DDS dimensions')
    if struct.unpack_from('<I', data, 24)[0] > 1 or struct.unpack_from('<I', data, 112)[0]:
        return None
    flags = struct.unpack_from('<I', data, 80)[0]
    block = {b'DXT1': 8, b'DXT3': 16, b'DXT5': 16}.get(data[84:88])
    if not flags & 4 or block is None:
        return None
    count = struct.unpack_from('<I', data, 28)[0] or 1
    if count > max(width, height).bit_length():
        raise ValueError('Invalid mipmap count')
    extents, sizes = [], []
    w, h = width, height
    for _ in range(count):
        extents.append((w, h))
        sizes.append(((w + 3) // 4) * ((h + 3) // 4) * block)
        w, h = max(1, w // 2), max(1, h // 2)
    if len(data) < 128 + sum(sizes):
        raise ValueError('Truncated DDS mip chain')
    drop = 0
    while drop < count - 1 and max(extents[drop]) > maximum:
        drop += 1
    if not drop:
        return None
    w, h = extents[drop]
    header = bytearray(data[:128])
    header_flags = struct.unpack_from('<I', header, 8)[0]
    header_flags = (header_flags | 0x80000) & ~8  # Linear compressed size, not row pitch.
    caps = struct.unpack_from('<I', header, 108)[0]
    if count - drop > 1:
        header_flags |= 0x20000
        caps |= 0x400008
    else:
        header_flags &= ~0x20000
        caps &= ~0x400008
    struct.pack_into('<I', header, 8, header_flags)
    struct.pack_into('<II', header, 12, h, w)
    struct.pack_into('<I', header, 20, sizes[drop])
    struct.pack_into('<I', header, 28, count - drop)
    struct.pack_into('<I', header, 108, caps)
    payload = data[128 + sum(sizes[:drop]):128 + sum(sizes)]
    return bytes(header) + payload, {
        'source_dimensions': [width, height], 'dimensions': [w, h], 'dropped_mips': drop,
        'source_rgba_bytes': sum(x * y * 4 for x, y in extents),
        'rgba_bytes': sum(x * y * 4 for x, y in extents[drop:]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True,
                        help='New overlay root, containing gamedata/textures and gamedata/levels')
    parser.add_argument('--max-size', type=int, default=512)
    parser.add_argument('--lzo-library', default=ctypes.util.find_library('lzo2'))
    args = parser.parse_args()
    if args.max_size < 64 or args.max_size > 4096 or args.max_size & (args.max_size - 1):
        raise SystemExit('--max-size must be a power of two from 64 to 4096')
    output = args.output_dir.resolve()
    if output.exists():
        raise SystemExit('Choose a new output directory; existing data was left untouched')
    if not args.lzo_library:
        raise SystemExit('Install liblzo2 or provide --lzo-library')
    archives = sorted(p for p in args.input_root.resolve().rglob('*')
                      if p.is_file() and not p.is_symlink() and re.search(r'\.db\d*$', p.name, re.I))
    if not archives:
        raise SystemExit('No X-Ray archives found')
    lzo = ctypes.CDLL(args.lzo_library)
    lzo.lzo1x_decompress_safe.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p,
                                       ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p]
    lzhuf, records = decoder(), {}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-textures-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'
        staging.mkdir()
        for path in archives:
            archive = Archive(path, lzhuf, lzo)
            changed = 0
            for name in archive.entries:
                member = PurePosixPath(name)
                if member.suffix.lower() != '.dds':
                    continue
                if path.parent.name.lower() == 'levels':
                    relative = member if member.parts[0].lower() == 'levels' else PurePosixPath('levels') / member
                elif member.parts[0].lower() == 'textures':
                    relative = member
                else:
                    continue
                if len(relative.parts) > 1 and relative.parts[1].lower() in {'ui', 'fonts'}:
                    continue
                original = archive.read(name)
                result = select_mips(original, args.max_size)
                if result is None:
                    continue
                data, record = result
                target = staging / 'gamedata' / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                record.update({'archive': path.name, 'source_sha256': hashlib.sha256(original).hexdigest(),
                               'sha256': hashlib.sha256(data).hexdigest()})
                records[relative.as_posix()] = record
                changed += 1
            print(f'{path.name}: {changed} mip-selected overrides', flush=True)
        before = sum(r['source_rgba_bytes'] for r in records.values())
        after = sum(r['rgba_bytes'] for r in records.values())
        (staging / 'texture-overlay.json').write_text(json.dumps({
            'max_size': args.max_size, 'estimated_original_rgba_bytes': before,
            'estimated_rgba_bytes': after, 'files': records,
        }, indent=2) + '\n')
        staging.rename(output)
    print(f'{len(records)} overrides; estimated decoded mip bytes {before:,} -> {after:,}. Originals unchanged.')


if __name__ == '__main__':
    main()
