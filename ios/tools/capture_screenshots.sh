#!/usr/bin/env bash
# Capture real App Store screenshots from the running app in the simulator,
# using the in-app debug launch hooks. Produces authentic UI (warm theme) rather
# than PIL mockups. Run from ios/:  ./tools/capture_screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="/opt/homebrew/bin:$PATH"
SIM_NAME="iPhone 17 Pro Max"          # 6.9-inch class
BUNDLE="app.exla.slide"
OUT="fastlane/screenshots/en-US"
DERIVED="/tmp/slide-shots-dd"
mkdir -p "$OUT"

echo "[1/4] build app for the simulator…"
xcodegen generate >/dev/null 2>&1
xcodebuild -project Slide.xcodeproj -scheme Slide -sdk iphonesimulator \
  -configuration Debug -derivedDataPath "$DERIVED" \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  build CODE_SIGNING_ALLOWED=NO -skipMacroValidation >/tmp/shots_build.log 2>&1
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Slide.app"
echo "    app: $APP"

echo "[2/4] boot simulator…"
SIM_ID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || true
# Cosmetic: clean status bar (9:41, full battery/signal)
xcrun simctl status_bar "$SIM_ID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 \
  --dataNetwork wifi --wifiBars 3 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP"

shot () {  # $1 = launch args (space sep), $2 = output filename
  local args="$1" name="$2"
  xcrun simctl terminate "$SIM_ID" "$BUNDLE" 2>/dev/null || true
  # shellcheck disable=SC2086
  xcrun simctl launch "$SIM_ID" "$BUNDLE" $args >/dev/null 2>&1 || true
  sleep 3.2
  xcrun simctl io "$SIM_ID" screenshot "$OUT/$name" >/dev/null 2>&1
  echo "    shot: $name"
}

echo "[3/4] capture screens…"
shot "-home"                "01_APP_IPHONE_6_9_01-home.png"
shot "-incall"             "02_APP_IPHONE_6_9_02-incall-video.png"
shot "-incall -audio"      "03_APP_IPHONE_6_9_03-incall-audio.png"
shot "-incoming"           "04_APP_IPHONE_6_9_04-incoming.png"
shot "-group"              "05_APP_IPHONE_6_9_05-group.png"
shot "-startPhone"         "06_APP_IPHONE_6_9_06-phone.png"

echo "[4/4] make 6.5-inch variants (resize)…"
python3 - <<'PY'
from PIL import Image
import glob, os
OUT="fastlane/screenshots/en-US"
for f in glob.glob(f"{OUT}/*_APP_IPHONE_6_9_*.png"):
    im = Image.open(f).convert("RGB")
    b = os.path.basename(f)
    im.resize((1242, 2688), Image.LANCZOS).save(f"{OUT}/{b.replace('APP_IPHONE_6_9','APP_IPHONE_65')}")
print("variants written")
PY

xcrun simctl status_bar "$SIM_ID" clear 2>/dev/null || true
echo "done."
