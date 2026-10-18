"""Verify automatic Files-container discovery after same-process foregrounding.

The three tiny archives are presence fixtures, never passed to the engine.
This tests folder setup, launcher readiness and lifecycle callbacks, not gameplay.
"""
import json
from pathlib import Path
import shutil
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True, timeout=180).strip()


def main():
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phone = next(d for runtime, group in devices.items() if '.iOS-' in runtime
                 for d in group if d['name'].startswith('iPhone'))
    device = phone['udid']; bundle = 'io.github.lupc9102.zoneport'
    if phone['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', device)
    run('xcrun', 'simctl', 'bootstatus', device, '-b')
    app = Path('Build/NativeSimulator/Build/Products/Release-iphonesimulator/ZonePort.app').resolve()
    run('xcrun', 'simctl', 'install', device, str(app))
    data = Path(run('xcrun', 'simctl', 'get_app_container', device, bundle, 'data'))
    documents = data / 'Documents'
    report = documents / 'local-files-smoke.json'
    fixture = documents / 'GameFiles/CoP-Mobile-Complete/CoP-Mobile'
    report.unlink(missing_ok=True)

    def wait(ready, after=0):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                state = json.loads(report.read_text())
                if state['ready'] == ready and state['generation'] > after:
                    return state
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(.25)
        raise RuntimeError('Local game discovery timed out')

    try:
        process = run('xcrun', 'simctl', 'launch', device, bundle, '--files-smoke-test')
        empty = wait(False)
        assert (documents / 'GameFiles/START-HERE.txt').is_file()
        run('xcrun', 'simctl', 'launch', device, 'com.apple.Preferences')
        for name in ['resources', 'levels', 'localization']:
            folder = fixture / name; folder.mkdir(parents=True, exist_ok=True)
            (folder / (name + '.db0')).write_bytes(b'presence fixture only')
        resumed = run('xcrun', 'simctl', 'launch', device, bundle)
        assert resumed == process, (process, resumed)
        ready = wait(True, empty['generation'])
        assert ready['playEnabled'] and ready['archives'] == 3 and Path(ready['root']) == fixture
        run('xcrun', 'simctl', 'io', device, 'screenshot', str(Path('Build/local-files-detected.png').resolve()))
        print('Same-process foreground: nested local archives detected and campaign Play enabled. No picker used.')
    finally:
        if fixture.parent.exists(): shutil.rmtree(fixture.parent)
        subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], check=False)


if __name__ == '__main__':
    main()
