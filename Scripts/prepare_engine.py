"""Reproduce the engine-only AOT experiment. No retail game data is downloaded.

This creates C and an import inventory, not a working game executable.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]


def run(*command): subprocess.run([str(x) for x in command], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--wabt', type=Path, help='Existing WABT checkout; must match pinned commit')
    parser.add_argument('--wasm', type=Path, help='Use a locally built engine instead of the pinned public engine snapshot')
    parser.add_argument('--javascript', type=Path)
    args = parser.parse_args()
    lock = json.loads((ROOT / 'Engine/sources.lock.json').read_text())
    wabt = (args.wabt or ROOT / 'Tools/wabt').resolve()
    if not wabt.exists():
        run('git', 'clone', '--depth', '1', '--branch', lock['wabt']['tag'], lock['wabt']['repository'], wabt)
    commit = subprocess.check_output(['git', '-C', str(wabt), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != lock['wabt']['commit']: raise SystemExit('WABT checkout does not match sources.lock.json')
    run('git', '-C', wabt, 'submodule', 'update', '--init', '--depth', '1', 'third_party/simde')
    run(sys.executable, ROOT / 'Scripts/patch_wasm2c.py', wabt / 'src/c-writer.cc')
    run('cmake', '-S', wabt, '-B', wabt / 'build', '-DBUILD_TESTS=OFF', '-DBUILD_LIBWASM=OFF', '-DCMAKE_BUILD_TYPE=Release')
    run('cmake', '--build', wabt / 'build', '--target', 'wasm2c', 'wat2wasm', '-j', '4')
    inputs = ROOT / 'Engine/Inputs'; inputs.mkdir(parents=True, exist_ok=True)
    if args.wasm:
        wasm, javascript = args.wasm.resolve(), args.javascript.resolve() if args.javascript else None
    else:
        files = {}
        for name, artifact in lock['engine_snapshot'].items():
            destination = inputs / ('xr_3da.wasm' if name == 'wasm' else 'xr_3da.js')
            if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != artifact['sha256']:
                temporary = destination.with_suffix(destination.suffix + '.part')
                origin = urllib.parse.urlsplit(artifact['url'])
                request = urllib.request.Request(artifact['url'], headers={
                    'User-Agent': 'Mozilla/5.0 ZonePort/0.1',
                    'Referer': f'{origin.scheme}://{origin.netloc}/',
                })
                with urllib.request.urlopen(request, timeout=90) as response, temporary.open('wb') as output:
                    shutil.copyfileobj(response, output)
                if hashlib.sha256(temporary.read_bytes()).hexdigest() != artifact['sha256']:
                    temporary.unlink(); raise SystemExit('Upstream engine changed. Review and repin sources.lock.json before proceeding.')
                temporary.replace(destination)
            files[name] = destination
        wasm, javascript = files['wasm'], files['javascript']
    generated = ROOT / 'Engine/Generated'; generated.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, ROOT / 'Scripts/inspect_wasm.py', wasm, '--out', generated / 'imports.json']
    if javascript: command += ['--javascript', javascript]
    run(*command)
    run(wabt / 'build/wasm2c', wasm, '--enable-threads', '--module-name=xray', '--num-outputs=64', '-o', generated / 'xray.c')
    run(sys.executable, ROOT / 'Scripts/patch_generated.py', generated)
    print('Engine C generated. Next: cmake -S Engine -B Engine/Build -DWABT_ROOT=' + str(wabt))


if __name__ == '__main__': main()
