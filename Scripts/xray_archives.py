"""Extract selected player-owned X-Ray data for private compatibility tests.

Uses the pinned OpenXRay LZHUF decoder and system LZO, never Windows binaries.
Run prepare_support_data.py first to obtain the pinned public decoder source.
Archive originals are read-only. Extracted assets must not be committed or
included in public build artifacts. See Licenses/OpenXRay.txt.
"""
import argparse
import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
MAX_TABLE = 64 * 1024 * 1024
MAX_FILE = 256 * 1024 * 1024


def decoder():
    lock = json.loads((ROOT / 'Engine/support.lock.json').read_text())
    source = subprocess.check_output(['git', '-C', str(ROOT / 'Tools/engine-support-source'),
                                     'show', lock['commit'] + ':src/xrCore/LzHuf.cpp']).decode()
    if source.count('#include "stdafx.h"') != 1:
        raise ValueError('Unexpected pinned LZHUF source')
    shim = '''#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
using u8 = uint8_t; using u32 = uint32_t;
#define IC inline
#define xr_malloc std::malloc
#define xr_realloc std::realloc
#define xr_free std::free
#define _read read
#define _write write
'''
    source = source.replace('#include "stdafx.h"', shim) + '''
extern "C" void* zone_decode(void* input, size_t size, size_t* length) {
    u8* output = nullptr;
    if (!_decompressLZ(&output, length, input, size, 64*1024*1024)) return nullptr;
    return output;
}
extern "C" void zone_release(void* output) { std::free(output); }
'''
    build = ROOT / 'Build/ArchiveDecoder'
    build.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(source.encode()).hexdigest()
    cpp, library = build / 'decoder.cpp', build / (digest + '.so')
    if not library.exists():
        cpp.write_text(source)
        subprocess.run(['c++', '-shared', '-fPIC', '-O2', str(cpp), '-o', str(library)], check=True)
    result = ctypes.CDLL(str(library))
    result.zone_decode.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
    result.zone_decode.restype = ctypes.c_void_p
    result.zone_release.argtypes = [ctypes.c_void_p]
    return result


class Archive:
    def __init__(self, path, lzhuf, lzo):
        self.path, self.lzo, self.entries = path, lzo, {}
        total = path.stat().st_size
        with path.open('rb') as source:
            while source.tell() < total:
                header = source.read(8)
                if len(header) != 8:
                    raise ValueError('Truncated archive chunk header')
                kind, size = struct.unpack('<II', header)
                if size > total - source.tell():
                    raise ValueError('Archive chunk exceeds file size')
                if kind & 0x7FFFFFFF != 1:
                    source.seek(size, 1)
                    continue
                if size > MAX_TABLE:
                    raise ValueError('Oversized archive index')
                table = source.read(size)
                if kind & 0x80000000:
                    if len(table) < 4 or not 0 < struct.unpack_from('<I', table)[0] <= MAX_TABLE:
                        raise ValueError('Invalid compressed index length')
                    length = ctypes.c_size_t()
                    pointer = lzhuf.zone_decode(table, len(table), ctypes.byref(length))
                    if not pointer:
                        raise ValueError('LZHUF index decompression failed')
                    try:
                        if length.value != struct.unpack_from('<I', table)[0]:
                            raise ValueError('Index decompression length mismatch')
                        table = ctypes.string_at(pointer, length.value)
                    finally:
                        lzhuf.zone_release(pointer)
                offset = 0
                while offset < len(table):
                    if len(table) - offset < 18:
                        raise ValueError('Truncated archive index record')
                    size, real, stored, crc = struct.unpack_from('<HIII', table, offset)
                    end = offset + size + 2
                    if size <= 16 or end > len(table):
                        raise ValueError('Invalid archive index record size')
                    name = table[offset + 14:offset + size - 2].decode('cp1251').replace('\\', '/')
                    normalized = PurePosixPath(name)
                    if normalized.is_absolute() or '..' in normalized.parts or ':' in name or '\0' in name:
                        raise ValueError('Unsafe archive member name')
                    position = struct.unpack_from('<I', table, end - 4)[0]
                    if position > total or stored > total - position:
                        raise ValueError('Archive member exceeds file size')
                    self.entries[normalized.as_posix()] = (position, real, stored, crc)
                    offset = end
                return
        raise ValueError('Archive has no file index')

    def read(self, name):
        position, real, stored, crc = self.entries[name]
        if real > MAX_FILE or stored > MAX_FILE:
            raise ValueError('Selected archive member is too large')
        with self.path.open('rb') as source:
            source.seek(position)
            data = source.read(stored)
        if len(data) != stored:
            raise ValueError('Truncated archive member')
        if real != stored:
            output, length = ctypes.create_string_buffer(real), ctypes.c_size_t(real)
            status = self.lzo.lzo1x_decompress_safe(data, stored, output, ctypes.byref(length), None)
            if status or length.value != real:
                raise ValueError('LZO member decompression failed')
            data = output.raw
        if zlib.crc32(data) != crc:
            raise ValueError('Archive member CRC mismatch')
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--kind', choices=['scripts', 'fonts'], required=True)
    parser.add_argument('--lzo-library', default=ctypes.util.find_library('lzo2'))
    args = parser.parse_args()
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
    lzhuf, manifest = decoder(), {}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-extract-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'
        staging.mkdir()
        for path in archives:
            archive = Archive(path, lzhuf, lzo)
            for name in archive.entries:
                member = PurePosixPath(name)
                selected = (member.suffix.lower() == '.script' if args.kind == 'scripts'
                            else member.name.lower().startswith('ui_font') and member.suffix.lower() == '.dds')
                if not selected:
                    continue
                data = archive.read(name)
                target = staging / member
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                manifest[name] = {'archive': path.name, 'sha256': hashlib.sha256(data).hexdigest()}
        if not manifest:
            raise SystemExit('No matching members found; no output created')
        (staging / 'extraction.json').write_text(json.dumps(manifest, indent=2) + '\n')
        staging.rename(output)
    print(f'Extracted {len(manifest)} {args.kind} with member CRC checks. Originals unchanged.')


if __name__ == '__main__':
    main()
