"""Merge private diagnostic overrides for copying beside resources/ and levels/.

This does not include original archives or change them. The resulting gamedata/
and zone-mobile-profile.json belong beside the player's existing archives.
Keep the output private; it contains game assets, not just source code.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tempfile
from xray_archives import ROOT


def relative_path(name):
    parts = name.split('/')
    if (len(parts) < 3 or parts[0] != 'gamedata'
            or parts[1] not in {'configs', 'scripts', 'textures', 'levels', 'shaders'}
            or any(not p or p.startswith('.') for p in parts) or any(c in name for c in '\\:\0')):
        raise ValueError('Unsafe mobile profile path')
    return PurePosixPath(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classic-overlay', type=Path, required=True)
    parser.add_argument('--texture-overlay', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.exists():
        raise SystemExit('Choose a new output directory; existing files were left untouched')
    classic = args.classic_overlay.resolve()
    textures = args.texture_overlay.resolve()
    c = json.loads((classic / 'classic-overlay.json').read_text())
    t = json.loads((textures / 'texture-overlay.json').read_text())
    support = ROOT / 'Engine/SupportData/support-manifest.json'
    s = json.loads(support.read_text())
    if c['support_commit'] != s['commit']:
        raise ValueError('Classic overlay does not match current engine support files')
    records = {}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-mobile-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'content'
        staging.mkdir()
        for root, files, prefix in [(classic, c['files'], ''), (textures, t['files'], 'gamedata/')]:
            for member, record in files.items():
                name = prefix + member
                if not name.startswith('gamedata/') or any(p.startswith('.') for p in name.split('/')):
                    continue
                relative = relative_path(name)
                path = root / relative
                if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
                    raise ValueError('Profile source is missing or outside its folder')
                if not 0 < path.stat().st_size <= 256 * 1024 * 1024:
                    raise ValueError('Profile source has an invalid size')
                data = path.read_bytes()
                digest = hashlib.sha256(data).hexdigest()
                if digest != record['sha256']:
                    raise ValueError(f'Profile source hash mismatch: {name}')
                target = staging / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                records[name] = {'bytes': len(data), 'sha256': digest}
        profile = {'version': 1, 'kind': 'cop-ee-classic-compat',
                   'supportManifestSHA256': hashlib.sha256(support.read_bytes()).hexdigest(),
                   'files': records}
        (staging / 'zone-mobile-profile.json').write_text(json.dumps(profile, indent=2) + '\n')
        staging.rename(output)
    print(f'Prepared {len(records)} private mobile overrides ({sum(x["bytes"] for x in records.values()):,} bytes).')
    print('Copy gamedata/ and zone-mobile-profile.json beside the player archives. Originals are unchanged.')


if __name__ == '__main__':
    main()
