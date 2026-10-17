"""Run the real native engine in UIKit using external free benchmark test data."""
import json
from pathlib import Path
import shutil
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    groups = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phones = [d for runtime, devices in groups.items() if '.iOS-' in runtime for d in devices if d['name'].startswith('iPhone')]
    if not phones:
        raise SystemExit('No available iPhone simulator.')
    device = phones[0]; identifier = device['udid']; bundle = 'io.github.lupc9102.zoneport'
    print(f'Native engine simulator: {device["name"]} ({identifier})', flush=True)
    if device['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', identifier)
    run('xcrun', 'simctl', 'bootstatus', identifier, '-b')
    app = Path('Build/NativeSimulator/Build/Products/Debug-iphonesimulator/ZonePort.app').resolve()
    run('xcrun', 'simctl', 'install', identifier, str(app))
    container = Path(run('xcrun', 'simctl', 'get_app_container', identifier, bundle, 'data'))
    documents = container / 'Documents'; documents.mkdir(exist_ok=True)
    # Test data remains outside the app and the packaged IPA.
    shutil.copytree('Build/Benchmark/app', documents / 'Benchmark', dirs_exist_ok=True)
    report = documents / 'engine-smoke.json'
    report.unlink(missing_ok=True)
    diagnostics = Path('Build/NativeSimulatorDiagnostics'); diagnostics.mkdir(parents=True, exist_ok=True)
    run('xcrun', 'simctl', 'launch', identifier, bundle, '--engine-smoke-test')

    def wait_frames(minimum, seconds=180):
        deadline = time.monotonic() + seconds; last = None
        while time.monotonic() < deadline:
            try:
                state = json.loads(report.read_text())
                if state != last:
                    print('Engine state:', state, flush=True); last = state
                if state['phase'] >= 4:
                    raise RuntimeError('Native engine stopped: ' + state['status'])
                if state['phase'] == 2 and state['frames'] >= minimum:
                    return state
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.5)
        raise RuntimeError('Native engine frame timeout; last state: ' + str(last))

    try:
        state = wait_frames(60)
        run('xcrun', 'simctl', 'io', identifier, 'screenshot', str(Path('Build/native-ios-menu.png').resolve()))
        before = state['frames']
        run('xcrun', 'simctl', 'launch', identifier, 'com.apple.Preferences')
        time.sleep(2)
        run('xcrun', 'simctl', 'launch', identifier, bundle)
        state = wait_frames(before + 30, 60)
        run('xcrun', 'simctl', 'io', identifier, 'screenshot', str(Path('Build/native-ios-resumed.png').resolve()))
        print(f'Native UIKit engine rendered {state["frames"]} frame callbacks and resumed after backgrounding. This is simulator validation, not a physical-device or level test.')
    finally:
        if report.exists():
            shutil.copy2(report, diagnostics / 'engine-smoke.json')
        logs = documents / 'ZonePortData/_appdata_/logs'
        if logs.exists():
            shutil.copytree(logs, diagnostics / 'engine-logs', dirs_exist_ok=True)


if __name__ == '__main__':
    main()
