"""Check the device app links the real engine and bundles only source support data."""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
app = parser.parse_args().app
symbols = subprocess.check_output(['xcrun', 'nm', '-gU', str(app / 'ZonePort')], text=True)
for symbol in ('ZEngineStart', 'wasm2c_xray_instantiate', 'w2c_xray_fi'):
    if not re.search(r'\b_' + symbol + r'\s*$', symbols, re.M):
        raise SystemExit('Native app is missing its real engine symbol: ' + symbol)
for path in ('SupportData/fsgame.ltx', 'SupportData/support-manifest.json', 'Mobile/user.ltx'):
    if not (app / path).is_file():
        raise SystemExit('Missing bundled engine support file: ' + path)
if len(list((app / 'SupportData/gamedata').rglob('*.*'))) < 100:
    raise SystemExit('Bundled source shaders/scripts are incomplete')
for path in app.rglob('*'):
    if path.is_file() and (path.suffix.lower() in ('.wasm', '.js', '.exe') or re.search(r'\.db\d*$', path.name, re.I)):
        raise SystemExit('Unexpected executable/browser/retail asset in native app: ' + str(path))
print('Verified: native engine symbols, source support shaders/scripts, mobile profile; no WASM/JS or game archives bundled.')
