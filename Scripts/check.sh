#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build/Checks
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -pthread -I Native/include Native/ZoneHost.c Tests/input_test.c -lm -o Build/Checks/input-test
Build/Checks/input-test
python3 -m unittest discover -s Tests -p 'test_*.py'
if command -v swiftc >/dev/null; then
    swiftc -frontend -parse App/*.swift
    if [[ "$(uname -s)" == Darwin ]]; then
        swiftc -typecheck Scripts/verify_simulator_screen.swift
    fi
else
    echo 'Swift compiler unavailable: UIKit source syntax check skipped.'
fi
python3 - <<'PY'
import plistlib
from pathlib import Path
with Path('Resources/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['UIFileSharingEnabled'] is True
print('Info.plist is valid; file import enabled.')
PY
