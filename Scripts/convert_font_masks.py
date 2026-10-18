"""Create single-channel font overrides from loose Enhanced Edition BC3 masks.

Input must contain extracted ui_font*.dds files. Originals are never changed.
This preserves the alpha mask exactly; it is a compatibility conversion, not
texture resizing or a general texture compressor. No game assets are bundled.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import tempfile


def convert(data):
    if len(data) < 128 or data[:4] != b'DDS ':
        raise ValueError('Not a DDS texture')
    if struct.unpack_from('<I', data, 4)[0] != 124 or struct.unpack_from('<I', data, 76)[0] != 32:
        raise ValueError('Invalid DDS header sizes')
    height, width = struct.unpack_from('<II', data, 12)
    if not width or not height or width > 16384 or height > 16384 or width * height > 64 * 1024 * 1024:
        raise ValueError('Invalid or oversized font atlas')
    if struct.unpack_from('<I', data, 24)[0] > 1 or struct.unpack_from('<I', data, 112)[0]:
        raise ValueError('Only plain 2D font textures are supported')
    if not struct.unpack_from('<I', data, 80)[0] & 4 or data[84:88] != b'DXT5':
        return None  # Existing classic A8 fonts and other formats stay intact.
    columns, rows = (width + 3) // 4, (height + 3) // 4
    if len(data) < 128 + columns * rows * 16:
        raise ValueError('Truncated BC3 base level')
    blocks = memoryview(data)[128:128 + columns * rows * 16]
    # Colorless masks only. Converting an ordinary colored font/texture would
    # discard information, so refuse that conversion rather than guess.
    if any(blocks[i + 8:i + 12] != b'\0\0\0\0' for i in range(0, len(blocks), 16)):
        return None
    mask = bytearray(width * height)
    palettes = {}
    for block in range(columns * rows):
        offset = block * 16
        a, b = blocks[offset], blocks[offset + 1]
        key = (a, b)
        if key not in palettes:
            if a > b:
                palette = [a, b] + [((7 - i) * a + i * b) // 7 for i in range(1, 7)]
            else:
                palette = [a, b] + [((5 - i) * a + i * b) // 5 for i in range(1, 5)] + [0, 255]
            palettes[key] = palette
        palette = palettes[key]
        indices = int.from_bytes(blocks[offset + 2:offset + 8], 'little')
        x0, y0 = (block % columns) * 4, (block // columns) * 4
        for pixel in range(16):
            x, y = x0 + pixel % 4, y0 + pixel // 4
            if x < width and y < height:
                mask[y * width + x] = palette[(indices >> (pixel * 3)) & 7]
    # DDSD_CAPS|HEIGHT|WIDTH|PITCH|PIXELFORMAT, DDPF_LUMINANCE,
    # DDSCAPS_TEXTURE. GLI maps legacy L8 DDS to GL_R8: the font shader
    # explicitly samples red. Alpha-only DDS can instead map red to zero.
    header = bytearray(128)
    header[:4] = b'DDS '
    struct.pack_into('<7I', header, 4, 124, 0x100F, height, width, width, 0, 0)
    struct.pack_into('<8I', header, 76, 32, 0x20000, 0, 8, 255, 0, 0, 0)
    struct.pack_into('<I', header, 108, 0x1000)
    return bytes(header + mask)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True,
                        help='New loose-texture directory, normally OVERLAY/gamedata/textures/ui')
    args = parser.parse_args()
    source, output = args.input_dir.resolve(), args.output_dir.resolve()
    if not source.is_dir():
        raise SystemExit('Input directory does not exist')
    if output.exists():
        raise SystemExit('Choose a new output directory; existing files were left untouched')
    output.parent.mkdir(parents=True, exist_ok=True)
    records, skipped = {}, 0
    with tempfile.TemporaryDirectory(prefix='zone-fonts-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'
        staging.mkdir()
        for path in sorted(source.glob('ui_font*.dds')):
            if path.is_symlink() or not path.is_file():
                continue
            original = path.read_bytes()
            result = convert(original)
            if result is None:
                skipped += 1
                continue
            (staging / path.name).write_bytes(result)
            records[path.name] = {'source_sha256': hashlib.sha256(original).hexdigest(),
                                  'output_sha256': hashlib.sha256(result).hexdigest()}
        if not records:
            raise SystemExit('No colorless BC3 font masks found; no output created')
        (staging / 'font-conversion.json').write_text(json.dumps({
            'format': 'L8', 'base_level_only': True, 'files': records,
        }, indent=2) + '\n')
        staging.rename(output)
    print(f'Converted {len(records)} font masks; skipped {skipped} other formats. Originals unchanged.')


if __name__ == '__main__':
    main()
