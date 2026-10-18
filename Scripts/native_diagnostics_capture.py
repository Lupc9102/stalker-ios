"""Verify persistent startup diagnostics after an intentional simulator trap.

This is a failure-path test. It neither reproduces nor claims to fix the
user's physical-device failure. No retail game data is used.
"""
import json
from pathlib import Path
import subprocess
import time
import shutil


def run(*args):
    return subprocess.check_output(args, text=True, timeout=180).strip()


def main():
    groups = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phone = next(d for runtime, devices in groups.items() if '.iOS-' in runtime
                 for d in devices if d['name'].startswith('iPhone'))
    device = phone['udid']; bundle = 'io.github.lupc9102.zoneport'
    data = Path(run('xcrun', 'simctl', 'get_app_container', device, bundle, 'data')) / 'Documents'
    (data / 'Benchmark').mkdir(exist_ok=True)
    failure = data / 'engine-failure.txt'; failure.unlink(missing_ok=True)
    try:
        run('xcrun', 'simctl', 'launch', device, bundle, '--engine-smoke-test', '--diagnostic-trap-test')
        deadline = time.monotonic() + 60
        while not failure.exists() and time.monotonic() < deadline: time.sleep(.25)
        assert failure.is_file(), 'Missing persistent early-failure report'
        assert 'Invalid call_indirect' in failure.read_text()
        log = data / 'engine-native.log'
        text = log.read_text()
        for required in ['Native logging enabled', 'diagnostic self-test', 'index=4294967295', 'out of bounds', 'Native backtrace']:
            assert required in text, required
        output = Path('Build/NativeDiagnosticsTest'); output.mkdir(parents=True, exist_ok=True)
        shutil.copy2(log, output / log.name); shutil.copy2(failure, output / failure.name)
        run('xcrun', 'simctl', 'io', device, 'screenshot', str((output / 'startup-failure.png').resolve()))
        print('Early native trap produced persistent top-level logs, call index/type details and a failure report.')
    finally:
        subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], check=False)


if __name__ == '__main__': main()
