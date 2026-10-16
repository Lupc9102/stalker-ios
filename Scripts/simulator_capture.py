"""Capture the real UIKit launcher on a GitHub-hosted Mac, after it compiles."""
import json
from pathlib import Path
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True)


def main():
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phones = [device for runtime, group in devices.items() if '.iOS-' in runtime
              for device in group if device['name'].startswith('iPhone')]
    if not phones:
        raise SystemExit('No available iPhone simulator runtime on this runner.')
    device = phones[0]
    if device['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', device['udid'])
    run('xcrun', 'simctl', 'bootstatus', device['udid'], '-b')
    app = Path('Build/Simulator/Build/Products/Debug-iphonesimulator/ZonePort.app').resolve()
    run('xcrun', 'simctl', 'install', device['udid'], str(app))
    for name, arguments in [('launcher', []), ('controls-editor', ['--controls-editor']),
                            ('controls-practice', ['--controls-practice'])]:
        subprocess.run(['xcrun', 'simctl', 'terminate', device['udid'], 'io.github.lupc9102.zoneport'],
                       check=False, capture_output=True)
        run('xcrun', 'simctl', 'launch', device['udid'], 'io.github.lupc9102.zoneport', *arguments)
        time.sleep(3)
        run('xcrun', 'simctl', 'io', device['udid'], 'screenshot', str(Path(f'Build/{name}.png').resolve()))


if __name__ == '__main__':
    main()
