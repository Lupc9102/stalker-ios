#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache_flags=()
if command -v ccache >/dev/null; then cache_flags+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache); fi
cmake -S Engine -B Engine/Build-Simulator \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Debug -DZONE_ENGINE_OPTIMIZATION=0 -DZONE_NATIVE_GLES=ON "${cache_flags[@]}"
if ! cmake --build Engine/Build-Simulator --target zone_native_host -j 3 >Build/native-engine-simulator.log 2>&1; then
    tail -n 90 Build/native-engine-simulator.log; exit 1
fi
if ! xcodebuild -project ZonePort.xcodeproj -scheme ZonePort -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath Build/NativeSimulator ZONE_ENGINE_BUILD_DIR="$PWD/Engine/Build-Simulator" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG ZONE_WITH_ENGINE' \
    CODE_SIGNING_ALLOWED=NO build >Build/native-simulator-build.log 2>&1; then
    tail -n 120 Build/native-simulator-build.log; exit 1
fi
