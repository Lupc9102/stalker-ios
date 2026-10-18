"""Validate the packaged app, including metadata that affects real UI layout."""
import argparse
from pathlib import Path
import plistlib
import struct
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt IPA archive')
        prefix = 'Payload/ZonePort.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        expected = {
            'CFBundleIdentifier': 'io.github.lupc9102.zoneport',
            'CFBundleDisplayName': 'ZonePort',
            'UIRequiresFullScreen': True,
            'UIFileSharingEnabled': True,
            'LSSupportsOpeningDocumentsInPlace': True,
        }
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f'Packaged {key} must be {value!r}')
        icons = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
        if icons.get('CFBundleIconName') != 'AppIcon' or not icons.get('CFBundleIconFiles'):
            raise ValueError('Missing compiled AppIcon metadata')
        if prefix + 'Assets.car' not in archive.namelist():
            raise ValueError('Missing compiled app asset catalog')
        landscape = {'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
        for key in ['UISupportedInterfaceOrientations', 'UISupportedInterfaceOrientations~ipad']:
            if set(info.get(key, [])) != landscape:
                raise ValueError(f'Packaged {key} must support both landscape orientations')
        if not isinstance(info.get('UILaunchScreen'), dict):
            raise ValueError('Missing launch-screen metadata; iOS can use a letterboxed legacy size')
        executable = archive.read(prefix + info['CFBundleExecutable'])
        magic, architecture, _, file_type = struct.unpack_from('<4I', executable)
        if (magic, architecture, file_type) != (0xfeedfacf, 0x100000c, 2):
            raise ValueError('Expected a native ARM64 Mach-O application')
        print(f"Verified {Path(path).name}: ARM64, landscape, full screen, Files access; "
              f"version {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    try:
        verify(args.ipa)
    except (ValueError, KeyError, struct.error, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from error
