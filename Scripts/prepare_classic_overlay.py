"""Prepare a private, experimental classic-script/UI overlay for EE diagnostics.

Requires player-owned data, prepare_benchmark.py's extracted official benchmark,
and prepare_support_data.py's pinned public support files. No game assets are
downloaded or distributed by this tool. Originals are read-only. This does not
establish campaign compatibility or install a playable iOS data pack.
"""
import argparse
import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import tempfile
from xray_archives import Archive, decoder

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def selected(name):
    return (name.startswith('scripts/') and name.endswith('.script')
            or name.startswith(('configs/ui/', 'textures/ui/'))
            or name in {'configs/fonts.ltx', 'configs/misc/achievements.ltx'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, required=True)
    parser.add_argument('--benchmark-root', type=Path, required=True, help='Extracted benchmark app/ directory')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--lzo-library', default=ctypes.util.find_library('lzo2'))
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.exists():
        raise SystemExit('Choose a new output directory; existing data was left untouched')
    if not args.lzo_library:
        raise SystemExit('Install liblzo2 or provide --lzo-library')
    lock = json.loads((ROOT / 'Engine/classic-compat.lock.json').read_text())
    benchmark = args.benchmark_root.resolve()
    for relative, record in lock['archives'].items():
        path = benchmark / relative
        if path.is_symlink() or not path.is_file() or path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
            raise SystemExit(f'Benchmark archive failed its pinned size/SHA-256 check: {relative}')
    support = ROOT / 'Engine/SupportData'
    manifest = json.loads((support / 'support-manifest.json').read_text())
    support_lock = json.loads((ROOT / 'Engine/support.lock.json').read_text())
    if manifest['commit'] != support_lock['commit']:
        raise SystemExit('Run prepare_support_data.py for the pinned support revision')
    lzo = ctypes.CDLL(args.lzo_library)
    lzo.lzo1x_decompress_safe.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p,
                                       ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p]
    lzhuf = decoder()
    records = {}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-classic-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'
        staging.mkdir()

        def put(relative, data, provenance):
            path = PurePosixPath(relative)
            if path.is_absolute() or '..' in path.parts or ':' in relative or '\0' in relative:
                raise ValueError('Unsafe overlay path')
            target = staging / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            records[relative] = {'source': provenance, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

        # Hash-check every pinned support file before copying it.
        for relative, expected in manifest['files'].items():
            path = support / relative
            if path.is_symlink() or digest(path) != expected:
                raise ValueError(f'Support file failed its manifest check: {relative}')
            put(relative, path.read_bytes(), 'support:' + manifest['commit'])
        # Preserve archive patch order: benchmark x_patch.db overrides base data.
        # Its matching classic UI also replaces the public port's UI variants.
        for relative in lock['archives']:
            archive = Archive(benchmark / relative, lzhuf, lzo)
            for name, meta in archive.entries.items():
                if meta[1] and selected(name):
                    put('gamedata/' + name, archive.read(name), 'benchmark:' + relative)
        # Keep the public port's script changes, including its Lua JIT guard.
        for relative in manifest['files']:
            if relative.startswith('gamedata/scripts/') and relative.endswith('.script'):
                put(relative, (support / relative).read_bytes(), 'support:' + manifest['commit'])
        # The benchmark disables level-changer registration. The player's EE
        # registry restores it; the retail world otherwise fails object creation.
        registrator = 'scripts/class_registrator.script'
        found = False
        for path in sorted(args.input_root.resolve().rglob('*')):
            if not path.is_file() or path.is_symlink() or not re.search(r'\.db\d*$', path.name, re.I):
                continue
            archive = Archive(path, lzhuf, lzo)
            if registrator in archive.entries:
                put('gamedata/' + registrator, archive.read(registrator), 'player:' + path.name)
                found = True
        if not found:
            raise ValueError('Player archives contain no class_registrator.script')
        (staging / 'classic-overlay.json').write_text(json.dumps({
            'experimental': True, 'campaign_verified': False,
            'benchmark_installer_sha256': lock['benchmark_installer_sha256'],
            'support_commit': manifest['commit'], 'files': records,
        }, indent=2) + '\n')
        staging.rename(output)
    print(f'Prepared {len(records)} private diagnostic overrides. Campaign compatibility remains unverified.')


if __name__ == '__main__':
    main()
