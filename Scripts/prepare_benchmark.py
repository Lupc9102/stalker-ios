"""Verify and extract GSC's free CoP benchmark for local engine diagnostics.

This never runs the Windows installer. Extracted game data must not be included
in app or diagnostic artifacts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def verify(path, lock):
    if not path.is_file() or path.stat().st_size != lock['bytes']:
        return False
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest() == lock['sha256']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installer', type=Path, default=ROOT / 'Engine/Benchmark/stkcop-bench-setup.exe')
    parser.add_argument('--output', type=Path, default=ROOT / 'Build/Benchmark')
    parser.add_argument('--extractor', default='innoextract')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'Engine/benchmark.lock.json').read_text())
    installer = args.installer.resolve()
    if installer.exists() and not verify(installer, lock):
        raise SystemExit('Existing installer does not match the pinned checksum; it was left untouched.')
    if not installer.exists():
        installer.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(lock['url'], headers={'User-Agent': 'Mozilla/5.0', 'Referer': lock['page']})
        with tempfile.TemporaryDirectory(prefix='zone-download-', dir=installer.parent) as temporary:
            downloaded = Path(temporary) / lock['filename']
            with urllib.request.urlopen(request, timeout=60) as response, downloaded.open('wb') as target:
                shutil.copyfileobj(response, target, 1024 * 1024)
            if not verify(downloaded, lock):
                raise SystemExit('Downloaded benchmark failed its size/SHA-256 check.')
            downloaded.rename(installer)
    print(f'Verified official benchmark: {lock["bytes"]:,} bytes, SHA-256 {lock["sha256"]}.', flush=True)
    if args.verify_only:
        return
    output = args.output.resolve()
    if output.exists():
        raise SystemExit(f'Output already exists; choose a fresh directory: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-benchmark-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'extracted'
        subprocess.run([args.extractor, '--extract', '--output-dir', str(staging), str(installer)], check=True)
        archives = {}
        for name in lock['archives']:
            archive = staging / 'app' / name
            if not archive.is_file() or archive.stat().st_size < 1024:
                raise SystemExit(f'Extracted benchmark is missing an archive: {name}')
            archives[name] = archive.stat().st_size
        (staging / 'benchmark-manifest.json').write_text(json.dumps({
            'installer_sha256': lock['sha256'], 'source': lock['page'], 'archive_bytes': archives
        }, indent=2) + '\n')
        staging.rename(output)
    print(f'Benchmark game root: {output / "app"}')
    print('Use a separate writable overlay with the pinned GL support shaders. Do not bundle benchmark data in the app.')


if __name__ == '__main__':
    main()
