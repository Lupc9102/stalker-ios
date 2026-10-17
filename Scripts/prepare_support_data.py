"""Prepare pinned engine support files without downloading retail archives."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'Tools/engine-support-source')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'Engine/support.lock.json').read_text())
    source = args.source.resolve()
    if not (source / '.git').exists():
        source.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'init', str(source)], check=True, stdout=subprocess.DEVNULL)
    command = ['git', '-C', str(source)]
    if subprocess.run(command + ['cat-file', '-e', lock['commit'] + '^{commit}'], capture_output=True).returncode:
        subprocess.run(command + ['fetch', '--depth', '1', lock['repository'], lock['commit']], check=True)
    archive = subprocess.check_output(command + ['archive', '--format=tar', lock['commit'], *lock['paths']])
    output = ROOT / 'Engine/SupportData'
    if output.exists() and not (output / 'support-manifest.json').is_file():
        raise SystemExit('Refusing to replace an unrecognized support directory')
    with tempfile.TemporaryDirectory(prefix='zone-support-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'; staging.mkdir(); files = {}
        with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
            for member in bundle:
                path = PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'res':
                    raise ValueError('Unsafe source support path')
                if member.isdir(): continue
                if not member.isfile(): raise ValueError('Non-regular source support file')
                relative = Path(*path.parts[1:]); data = bundle.extractfile(member).read()
                target = staging / relative; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
                files[relative.as_posix()] = hashlib.sha256(data).hexdigest()
        (staging / 'support-manifest.json').write_text(json.dumps({'repository': lock['repository'], 'commit': lock['commit'], 'files': files}, indent=2) + '\n')
        if output.exists(): shutil.rmtree(output)
        staging.rename(output)
    print(f'Prepared {len(files)} source support files at {output}. No retail data downloaded.')


if __name__ == '__main__': main()
