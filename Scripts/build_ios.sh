#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
if [[ "$(uname -s)" == Darwin ]] && command -v xcodebuild >/dev/null; then
    command -v xcodegen >/dev/null || { echo 'Install xcodegen: brew install xcodegen' >&2; exit 1; }
    xcodegen generate --spec project.yml
    xcodebuild -project ZonePort.xcodeproj -scheme ZonePort -configuration Release \
        -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath Build/Device \
        CODE_SIGNING_ALLOWED=NO build
    mkdir -p Build/Package/Payload
    rm -rf Build/Package/Payload/ZonePort.app
    ditto Build/Device/Build/Products/Release-iphoneos/ZonePort.app Build/Package/Payload/ZonePort.app
    rm -f Build/ZonePort.ipa
    (cd Build/Package && /usr/bin/zip -qry ../ZonePort.ipa Payload)
    python3 Scripts/verify_ipa.py Build/ZonePort.ipa
    echo "Built: $PWD/Build/ZonePort.ipa (unsigned)"
else
    command -v xtool >/dev/null || { echo 'xtool is required on Linux: https://xtool.sh/' >&2; exit 1; }
    status="$(xtool sdk status)"
    if [[ "$status" == *'Not installed'* ]]; then
        echo 'Darwin SDK missing. Run xtool sdk install --slim /path/to/Xcode.xip first.' >&2
        exit 1
    fi
    xtool dev build --configuration release --ipa
fi
