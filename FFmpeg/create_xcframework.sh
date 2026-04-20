#!/bin/bash
################################################################################
#
# FFmpeg.xcframework 生成スクリプト（本リポジトリで再生成する）
#
# FFmpeg.framework（fat: x86_64 sim + arm64 device）から、vtool で arm64 を
# iOS Simulator 向けに再ラベルし、x86_64 と fat 化した上で XCFramework を生成します。
# Issue #4805: ios-arm64_x86_64-simulator スライスにより Apple Silicon シミュレータで Rosetta 不要。
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
WORK_DIR="$(mktemp -d)"

trap 'rm -rf "${WORK_DIR}"' EXIT

read_ios_min_sdk_from_binary() {
  local binary="$1"
  xcrun vtool -show "${binary}" | awk '
    $0 ~ /LC_VERSION_MIN_IPHONEOS/ { want=1; next }
    want && $1=="version" { min=$2; want=2; next }
    want==2 && $1=="sdk" { sdk=$2; print min " " sdk; exit }
  '
}

if [[ ! -f "${SOURCE_FRAMEWORK}/FFmpeg" ]]; then
  echo "Error: FFmpeg.framework not found at ${SOURCE_FRAMEWORK}"
  exit 1
fi

echo "=== Creating FFmpeg.xcframework ==="

echo "[1/4] Extracting x86_64 (simulator)..."
mkdir -p "${WORK_DIR}/simulator"
cp -R "${SOURCE_FRAMEWORK}" "${WORK_DIR}/simulator/FFmpeg.framework"
xcrun lipo -extract x86_64 "${WORK_DIR}/simulator/FFmpeg.framework/FFmpeg" -o "${WORK_DIR}/sim_x86_64"

echo "[2/4] Extracting arm64 (device) and relabeling for simulator..."
mkdir -p "${WORK_DIR}/device"
cp -R "${SOURCE_FRAMEWORK}" "${WORK_DIR}/device/FFmpeg.framework"
xcrun lipo -extract arm64 "${WORK_DIR}/device/FFmpeg.framework/FFmpeg" -o "${WORK_DIR}/dev_arm64"

min_sdk="$(read_ios_min_sdk_from_binary "${WORK_DIR}/sim_x86_64")"
ios_min="${min_sdk%% *}"
ios_sdk="${min_sdk##* }"
if [[ -z "${ios_min}" || -z "${ios_sdk}" ]]; then
  echo "error: could not parse LC_VERSION_MIN_IPHONEOS from FFmpeg sim x86_64 slice" >&2
  exit 1
fi

xcrun vtool -set-build-version iossim "${ios_min}" "${ios_sdk}" -replace \
  -output "${WORK_DIR}/sim_arm64" "${WORK_DIR}/dev_arm64"

echo "[3/4] Creating fat simulator FFmpeg.framework..."
xcrun lipo -create "${WORK_DIR}/sim_x86_64" "${WORK_DIR}/sim_arm64" -o "${WORK_DIR}/simulator/FFmpeg.framework/FFmpeg"
codesign --force --sign - "${WORK_DIR}/simulator/FFmpeg.framework"

echo "[4/4] Thinning device slice and creating XCFramework..."
xcrun lipo -extract arm64 "${WORK_DIR}/device/FFmpeg.framework/FFmpeg" -o "${WORK_DIR}/device/FFmpeg.framework/FFmpeg"
codesign --force --sign - "${WORK_DIR}/device/FFmpeg.framework"

rm -rf "${OUTPUT_XCFRAMEWORK}"
xcodebuild -create-xcframework \
  -framework "${WORK_DIR}/device/FFmpeg.framework" \
  -framework "${WORK_DIR}/simulator/FFmpeg.framework" \
  -output "${OUTPUT_XCFRAMEWORK}"

echo ""
echo "=== Done ==="
echo "Output: ${OUTPUT_XCFRAMEWORK}"
echo ""
echo "Simulator: $(xcrun lipo -info "${OUTPUT_XCFRAMEWORK}/ios-arm64_x86_64-simulator/FFmpeg.framework/FFmpeg")"
echo "Device:    $(xcrun lipo -info "${OUTPUT_XCFRAMEWORK}/ios-arm64/FFmpeg.framework/FFmpeg")"
