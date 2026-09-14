#!/usr/bin/env bash
# Capture real App Store screenshots from the running app in the simulator,
# using the in-app debug launch hooks (-scene <name>, see Config.useMockData
# and AppState's scene seeding). Produces authentic UI (warm theme) rather
# than mockups, then composites captions with compose_screenshots.py.
#
# Run from ios/:  ./tools/capture_screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="/opt/homebrew/bin:$PATH"

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same clang-probe-deadlock workaround the Fastfile applies to xcodebuild/gym
# (see clang-probe-wrapper.sh for why): export the wrappers as CC/CPLUSPLUS
# and also pass them on the xcodebuild command line, since the build service
# is a persistent daemon that may not pick up a freshly exported shell env.
CC_WRAPPER="$TOOLS_DIR/clang-probe-wrapper.sh"
CXX_WRAPPER="$TOOLS_DIR/clang-probe-wrapper++.sh"
export CC="$CC_WRAPPER"
export CPLUSPLUS="$CXX_WRAPPER"

SIM_NAME="iPhone 17 Pro Max"          # 6.9-inch class
BUNDLE="app.exla.slide"
RAW_DIR="/tmp/knock-shots/raw"
DERIVED="${DERIVED:-/tmp/knock-dd-shots}"   # override to reuse an existing build dir
SPM_CACHE="/tmp/knock-dd-skel/SourcePackages"
SCENES=(tonightClosed lobby date decision match chat)

mkdir -p "$RAW_DIR" "$SPM_CACHE"

echo "[1/5] build app for the simulator…"
xcodegen generate >/dev/null 2>&1
xcodebuild -project Slide.xcodeproj -scheme Slide -sdk iphonesimulator \
  -configuration Debug -derivedDataPath "$DERIVED" \
  -clonedSourcePackagesDirPath "$SPM_CACHE" \
  -destination "generic/platform=iOS Simulator" \
  -skipMacroValidation \
  build CODE_SIGNING_ALLOWED=NO "CC=$CC_WRAPPER" "CPLUSPLUS=$CXX_WRAPPER" \
  >/tmp/knock-shots-build.log 2>&1
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Slide.app"
echo "    app: $APP"

echo "[2/5] find or create the \"$SIM_NAME\" simulator…"
SIM_ID=$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
if [ -z "$SIM_ID" ]; then
  DEVICE_TYPE_ID=$(xcrun simctl list devicetypes | grep -F "$SIM_NAME (" | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9_.-]+' | head -1)
  [ -n "$DEVICE_TYPE_ID" ] || { echo "no device type found for \"$SIM_NAME\" (xcrun simctl list devicetypes)" >&2; exit 1; }
  # Newest installed iOS runtime (sort -V so "iOS 9" doesn't outrank "iOS 17").
  RUNTIME_LINE=$(xcrun simctl list runtimes | grep -E '^iOS ' | grep -vi unavailable | sort -V | tail -1)
  RUNTIME_ID=$(printf '%s' "$RUNTIME_LINE" | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9_.-]+')
  [ -n "$RUNTIME_ID" ] || { echo "no available iOS runtime found (xcrun simctl list runtimes)" >&2; exit 1; }
  echo "    creating \"$SIM_NAME\" ($DEVICE_TYPE_ID) on ${RUNTIME_ID}…"
  SIM_ID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
fi
echo "    sim: $SIM_ID"

echo "[3/5] boot simulator + set status bar…"
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || true
xcrun simctl status_bar "$SIM_ID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 \
  --dataNetwork wifi --wifiBars 3 2>/dev/null || true
# Mock dates need camera/mic (and location for the Tonight nag) already
# granted, or the Date scene shows a permission banner + "Connecting…".
for svc in camera microphone location; do
  xcrun simctl privacy "$SIM_ID" grant "$svc" "$BUNDLE" >/dev/null 2>&1 || true
done
xcrun simctl install "$SIM_ID" "$APP"

shot () {  # $1 = scene name -> $RAW_DIR/<scene>.png
  local scene="$1"
  xcrun simctl terminate "$SIM_ID" "$BUNDLE" 2>/dev/null || true
  # People scenes get realistic DEBUG-only faces (ios/tools/faces: real,
  # CC-BY-licensed photos, see ios/tools/faces/LICENSES.md).
  local extra=()
  case "$scene" in date|decision|match|matches|chat) extra=(-mockPhotosDir "$(cd "$(dirname "$0")/faces" && pwd)");; esac
  xcrun simctl launch "$SIM_ID" "$BUNDLE" -scene "$scene" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1 || true
  sleep 3.2
  xcrun simctl io "$SIM_ID" screenshot "$RAW_DIR/$scene.png" >/dev/null 2>&1
  echo "    shot: $scene"
}

echo "[4/5] capture scenes…"
for scene in "${SCENES[@]}"; do
  shot "$scene"
done

echo "[5/5] compose captioned App Store screenshots…"
python3 "$TOOLS_DIR/compose_screenshots.py" --raw-dir "$RAW_DIR"

xcrun simctl status_bar "$SIM_ID" clear 2>/dev/null || true
echo "done."
