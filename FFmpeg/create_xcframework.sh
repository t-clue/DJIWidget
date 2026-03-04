#!/bin/bash
################################################################################
#
# FFmpeg.xcframework 생성 스크립트
#
# FFmpeg.framework (fat binary: x86_64 + arm64) 로부터
# 시뮬레이터(x86_64)와 디바이스(arm64)를 분리하여 XCFramework를 생성합니다.
#
# Usage:
#   cd DJIWidget/FFmpeg
#   ./create_xcframework.sh
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_FRAMEWORK="$SCRIPT_DIR/FFmpeg.framework"
OUTPUT_XCFRAMEWORK="$SCRIPT_DIR/FFmpeg.xcframework"
WORK_DIR=$(mktemp -d)

trap "rm -rf $WORK_DIR" EXIT

# Validate source framework
if [ ! -f "$SOURCE_FRAMEWORK/FFmpeg" ]; then
    echo "Error: FFmpeg.framework not found at $SOURCE_FRAMEWORK"
    exit 1
fi

echo "=== Creating FFmpeg.xcframework ==="

# Simulator framework (x86_64)
echo "[1/3] Extracting x86_64 (simulator)..."
mkdir -p "$WORK_DIR/simulator"
cp -R "$SOURCE_FRAMEWORK" "$WORK_DIR/simulator/FFmpeg.framework"
xcrun lipo -extract x86_64 "$WORK_DIR/simulator/FFmpeg.framework/FFmpeg" -o "$WORK_DIR/simulator/FFmpeg.framework/FFmpeg"

# Device framework (arm64)
echo "[2/3] Extracting arm64 (device)..."
mkdir -p "$WORK_DIR/device"
cp -R "$SOURCE_FRAMEWORK" "$WORK_DIR/device/FFmpeg.framework"
xcrun lipo -extract arm64 "$WORK_DIR/device/FFmpeg.framework/FFmpeg" -o "$WORK_DIR/device/FFmpeg.framework/FFmpeg"

# Create XCFramework
echo "[3/3] Creating XCFramework..."
rm -rf "$OUTPUT_XCFRAMEWORK"
xcodebuild -create-xcframework \
    -framework "$WORK_DIR/simulator/FFmpeg.framework" \
    -framework "$WORK_DIR/device/FFmpeg.framework" \
    -output "$OUTPUT_XCFRAMEWORK"

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_XCFRAMEWORK"
echo ""
echo "Simulator: $(lipo -info "$OUTPUT_XCFRAMEWORK/ios-x86_64-simulator/FFmpeg.framework/FFmpeg")"
echo "Device:    $(lipo -info "$OUTPUT_XCFRAMEWORK/ios-arm64/FFmpeg.framework/FFmpeg")"
