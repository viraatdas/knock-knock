#!/usr/bin/env bash
# play-store-deploy — ship Slide Android to Google Play from the CLI.
# Usage: deploy.sh [build_debug|keystore|internal|production]   (default: build_debug)
set -uo pipefail

LANE="${1:-build_debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AND="$ROOT/android"
KS="$AND/slide-upload.keystore"
KSP="$AND/keystore.properties"

say()  { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
die()  { printf "  \033[31m✗ %s\033[0m\n" "$*"; exit 1; }

say "▶ play-store-deploy: lane=$LANE"

# ── JDK / keytool ─────────────────────────────────────────────────────────────
if ! command -v keytool >/dev/null 2>&1; then
  for cand in /opt/homebrew/opt/openjdk@17/bin /usr/libexec/java_home; do :; done
  if [ -x /opt/homebrew/opt/openjdk@17/bin/keytool ]; then
    export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
  fi
fi

# ── keystore generation ───────────────────────────────────────────────────────
if [ "$LANE" = "keystore" ]; then
  command -v keytool >/dev/null 2>&1 || die "keytool not found (install a JDK: brew install openjdk@17)"
  if [ -f "$KS" ]; then ok "keystore already exists: $KS"; exit 0; fi
  PW="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  keytool -genkeypair -v -keystore "$KS" -alias slide \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$PW" -keypass "$PW" \
    -dname "CN=Slide, O=Slide, C=US" || die "keytool failed"
  cat > "$KSP" <<EOF
storeFile=slide-upload.keystore
storePassword=$PW
keyAlias=slide
keyPassword=$PW
EOF
  ok "generated $KS + $KSP (both gitignored)"
  echo "  ⚠ BACK UP $KS — losing it before Play App Signing is enabled is unrecoverable."
  exit 0
fi

# ── debug build (no account needed) ───────────────────────────────────────────
if [ "$LANE" = "build_debug" ]; then
  ( cd "$AND" && ./gradlew assembleDebug ) || die "assembleDebug failed"
  ok "APK: $AND/app/build/outputs/apk/debug/app-debug.apk"
  exit 0
fi

# ── release lanes need keystore + Play JSON ───────────────────────────────────
need_play() {
  cat <<EOF

  ─────────────────────────────────────────────────────────────────────────────
  '$LANE' needs a Google Play Console account + service-account JSON (one-time):

    1. Create a Play Console account (\$25): https://play.google.com/console/signup
       Create the app: name "Slide", package app.slide.
    2. Play Console -> Setup -> API access -> create a service account ->
       grant "Release" -> download the JSON to:
         android/fastlane/play-service-account.json   (gitignored)
    3. Generate the upload keystore (if not done):
         .claude/skills/play-store-deploy/deploy.sh keystore
    Then re-run:  .claude/skills/play-store-deploy/deploy.sh $LANE
  ─────────────────────────────────────────────────────────────────────────────
EOF
  exit 2
}

[ -f "$KSP" ] || { say "No keystore yet — generating…"; "$0" keystore || die "keystore gen failed"; }
PLAY_JSON="${PLAY_JSON_KEY:-$AND/fastlane/play-service-account.json}"
[ -f "$PLAY_JSON" ] || need_play
export PLAY_JSON_KEY="$PLAY_JSON"

command -v fastlane >/dev/null 2>&1 || { say "Installing fastlane…"; brew install fastlane || die "fastlane install failed"; }

say "Running fastlane $LANE…"
( cd "$AND" && fastlane "$LANE" ) || die "fastlane $LANE failed"
say "✓ done: fastlane $LANE"
case "$LANE" in
  internal)   echo "  → AAB uploaded to Internal testing (draft). Add testers in Play Console." ;;
  production) echo "  → Uploaded to production at 10% staged rollout. Review ~hours-days." ;;
esac
