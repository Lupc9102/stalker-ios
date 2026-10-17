#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
command -v xcodebuild >/dev/null || { echo 'This device build runs on the GitHub macOS runner.' >&2; exit 1; }
python3 Scripts/prepare_engine.py
python3 Scripts/prepare_support_data.py
python3 Scripts/native_host.py Engine/Generated Engine/Inputs/xr_3da.js --gles
cache_flags=()
if command -v ccache >/dev/null; then cache_flags+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache); fi
cmake -S Engine -B Engine/Build-iOS \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Debug -DZONE_ENGINE_OPTIMIZATION=0 -DZONE_NATIVE_GLES=ON "${cache_flags[@]}"
if ! cmake --build Engine/Build-iOS --target zone_native_host -j 3 >Build/native-engine-ios.log 2>&1; then
    tail -n 90 Build/native-engine-ios.log; exit 1
fi
xcodegen generate --spec project-engine.yml
if ! xcodebuild -project ZonePort.xcodeproj -scheme ZonePort -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath Build/NativeDevice \
    CODE_SIGNING_ALLOWED=NO build >Build/native-ios-build.log 2>&1; then
    tail -n 120 Build/native-ios-build.log; exit 1
fi
app=Build/NativeDevice/Build/Products/Release-iphoneos/ZonePort.app
python3 Scripts/verify_native_app.py "$app"
mkdir -p Build/NativePackage/Payload
rm -rf Build/NativePackage/Payload/ZonePort.app
ditto "$app" Build/NativePackage/Payload/ZonePort.app
rm -f Build/ZonePort-Native.ipa
(cd Build/NativePackage && /usr/bin/zip -qry ../ZonePort-Native.ipa Payload)
python3 Scripts/verify_ipa.py Build/ZonePort-Native.ipa
echo 'Built native engine IPA: Build/ZonePort-Native.ipa (unsigned)'
