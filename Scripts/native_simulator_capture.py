"""Run the real native engine in UIKit using external free benchmark test data."""
import json
from pathlib import Path
import shutil
import subprocess
import time


def run(*args, timeout=120):
    print('Simulator command:', ' '.join(args), flush=True)
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def verify_engine_frame(path):
    # Check the engine's readback, excluding UIKit buttons and loading art.
    with path.open('rb') as source:
        if source.readline() != b'P6\n':
            raise RuntimeError('Missing native RGB framebuffer header')
        width, height = map(int, source.readline().split())
        if source.readline() != b'255\n' or not (1 <= width <= 4096 and 1 <= height <= 4096):
            raise RuntimeError('Invalid native RGB framebuffer dimensions')
        pixels = source.read()
    if len(pixels) != width * height * 3:
        raise RuntimeError('Incomplete native framebuffer readback')
    lit = sum(any(pixels[i:i+3]) for i in range(0, len(pixels), 3))
    colors = {pixels[i:i+3] for i in range(0, len(pixels), 3 * 31)}
    if lit < width * height // 100 or len(colors) < 16:
        raise RuntimeError(f'Native game framebuffer is blank: {lit} lit pixels, {len(colors)} sampled colors')
    print(f'Native framebuffer verified: {width}x{height}, {lit} lit pixels, {len(colors)} sampled colors.', flush=True)


def main():
    groups = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phones = [d for runtime, devices in groups.items() if '.iOS-' in runtime for d in devices if d['name'].startswith('iPhone')]
    if not phones:
        raise SystemExit('No available iPhone simulator.')
    device = phones[0]; identifier = device['udid']; bundle = 'io.github.lupc9102.zoneport'
    print(f'Native engine simulator: {device["name"]} ({identifier})', flush=True)
    if device['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', identifier)
    run('xcrun', 'simctl', 'bootstatus', identifier, '-b', timeout=180)
    app = Path('Build/NativeSimulator/Build/Products/Debug-iphonesimulator/ZonePort.app').resolve()
    run('xcrun', 'simctl', 'install', identifier, str(app))
    container = Path(run('xcrun', 'simctl', 'get_app_container', identifier, bundle, 'data'))
    documents = container / 'Documents'; documents.mkdir(exist_ok=True)
    # Test data remains outside the app and the packaged IPA.
    shutil.copytree('Build/Benchmark/app', documents / 'Benchmark', dirs_exist_ok=True)
    report = documents / 'engine-smoke.json'
    report.unlink(missing_ok=True)
    framebuffer = documents / 'engine-frame.ppm'
    framebuffer.unlink(missing_ok=True)
    drawable = documents / 'engine-drawable.ppm'
    drawable.unlink(missing_ok=True)
    diagnostics = Path('Build/NativeSimulatorDiagnostics'); diagnostics.mkdir(parents=True, exist_ok=True)

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
        run('xcrun', 'simctl', 'launch', identifier, bundle, '--engine-smoke-test', timeout=60)
        state = wait_frames(60)
        verify_engine_frame(framebuffer)
        verify_engine_frame(drawable)
        if state.get('surfaceHidden') or not state.get('loadingHidden'):
            raise RuntimeError('Engine view is hidden or still covered by the loading screen')
        run('xcrun', 'simctl', 'io', identifier, 'screenshot', str(Path('Build/native-ios-menu.png').resolve()))
        run('swift', 'Scripts/verify_simulator_screen.swift', 'Build/native-ios-menu.png')
        before = state['frames']
        run('xcrun', 'simctl', 'launch', identifier, 'com.apple.Preferences')
        time.sleep(2)
        run('xcrun', 'simctl', 'launch', identifier, bundle)
        state = wait_frames(before + 30, 60)
        run('xcrun', 'simctl', 'io', identifier, 'screenshot', str(Path('Build/native-ios-resumed.png').resolve()))
        run('swift', 'Scripts/verify_simulator_screen.swift', 'Build/native-ios-resumed.png')
        print(f'Native UIKit engine rendered {state["frames"]} frame callbacks and resumed after backgrounding. This is simulator validation, not a physical-device or level test.')
    finally:
        # A failed startup must still leave a visible app state for diagnosis.
        try:
            run('xcrun', 'simctl', 'io', identifier, 'screenshot', str((diagnostics / 'last-screen.png').resolve()), timeout=30)
        except (subprocess.SubprocessError, OSError) as error:
            print('Diagnostic screenshot unavailable:', error, flush=True)
        if report.exists():
            shutil.copy2(report, diagnostics / 'engine-smoke.json')
        for name in ('engine-native.log', 'engine-frame.ppm', 'engine-drawable.ppm'):
            if (documents / name).exists():
                shutil.copy2(documents / name, diagnostics / name)
        logs = documents / 'ZonePortData/_appdata_/logs'
        if logs.exists():
            shutil.copytree(logs, diagnostics / 'engine-logs', dirs_exist_ok=True)


if __name__ == '__main__':
    main()
