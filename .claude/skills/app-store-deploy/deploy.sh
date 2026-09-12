#!/usr/bin/env bash
# app-store-deploy — ship Slide iOS to TestFlight / the App Store from the CLI.
# Usage: deploy.sh [build_sim|bootstrap|beta|release|tf_*]   (default: build_sim)
#        deploy.sh --help    show this + the GitHub Actions alternative
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # repo root
IOS="$ROOT/ios"
ENV_FILE="$IOS/fastlane/.asc.env"

say()  { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
die()  { printf "  \033[31m✗ %s\033[0m\n" "$*"; exit 1; }

show_help() {
  cat <<EOF
Usage: deploy.sh [LANE]   (default: build_sim)

Runs a fastlane lane from ios/fastlane/Fastfile, e.g.:
  build_sim   unsigned Simulator build (no account needed; sanity check)
  bootstrap   create the App Store Connect app record (idempotent)
  beta        archive + upload to TestFlight
  release     archive + upload + submit for review
  rename_app  set the App Info name/subtitle for the current release
  tf_beta_meta, tf_beta_submit, tf_public_link, tf_invite  external TestFlight setup

This machine works around a local Xcode 26.6 build-service deadlock by routing
CC/CPLUSPLUS through ios/tools/clang-probe-wrapper*.sh (see that script for why);
this deploy.sh exports the same wrappers before invoking fastlane.

── GitHub Actions alternative ─────────────────────────────────────────────────
If archiving locally ever hangs or the workaround stops working, the same
release ships from a clean macOS runner instead, no local workaround needed:

  gh workflow run ios-release.yml -f build_number=33

That workflow (.github/workflows/ios-release.yml) archives, signs and uploads
the .ipa using repo secrets (IOS_DIST_P12_B64, ASC_KEY_ID/ASC_ISSUER_ID/
ASC_KEY_P8_B64, APPLE_TEAM_ID, GOOGLE_SERVICE_INFO_PLIST_B64). After it
uploads, attach + submit from here with:

  cd ios && fastlane ios tf_build_state     # wait for processing=VALID
  cd ios && fastlane ios submit_review      # submit the uploaded build
────────────────────────────────────────────────────────────────────────────────
EOF
}

case "${1:-}" in
  -h|--help|help) show_help; exit 0 ;;
esac

LANE="${1:-build_sim}"

say "▶ app-store-deploy: lane=$LANE"

# ── 1. tooling ────────────────────────────────────────────────────────────────
command -v xcodegen >/dev/null 2>&1 || { say "Installing xcodegen…"; brew install xcodegen || die "xcodegen install failed"; }
ok "xcodegen $(xcodegen --version 2>/dev/null | awk '{print $2}')"

if ! command -v fastlane >/dev/null 2>&1; then
  say "Installing fastlane (brew)…"
  brew install fastlane || die "fastlane install failed (try: brew install fastlane)"
fi
ok "fastlane present"

# ── 2. auth (skip for build_sim) ─────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
  ok "loaded $ENV_FILE"
fi
export APP_IDENTIFIER="${APP_IDENTIFIER:-app.exla.slide}"

need_key() {
  cat <<EOF

  ─────────────────────────────────────────────────────────────────────────────
  An App Store Connect API key is required for '$LANE' and is not configured.

  Apple requires creating the FIRST key in the web UI (≈60 seconds, once):
    1. https://appstoreconnect.apple.com/access/integrations/api
    2. Generate API Key → role App Manager → name it slide-ci
    3. Copy the Key ID and the Issuer ID
    4. Download the .p8 (one-time) to:
         ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
    5. Create $ENV_FILE :
         ASC_KEY_ID=<KEYID>
         ASC_ISSUER_ID=<ISSUER-UUID>
         ASC_KEY_PATH=\$HOME/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
         APPLE_TEAM_ID=<10-char Team ID from developer.apple.com → Membership>
         APP_IDENTIFIER=app.exla.slide

  Then re-run:  .claude/skills/app-store-deploy/deploy.sh $LANE
  ─────────────────────────────────────────────────────────────────────────────
EOF
  exit 2
}

if [ "$LANE" != "build_sim" ]; then
  [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ] || need_key
  [ -f "${ASC_KEY_PATH:-/nonexistent}" ] || die "ASC_KEY_PATH not found: $ASC_KEY_PATH"
  [ -n "${APPLE_TEAM_ID:-}" ] || warn "APPLE_TEAM_ID unset — signing/archive may fail. Set it in $ENV_FILE."
  ok "ASC API key configured (key $ASC_KEY_ID)"
fi

# ── 3. project ───────────────────────────────────────────────────────────────
( cd "$IOS" && xcodegen generate >/dev/null ) && ok "Xcode project generated"

# ── 3b. clang-probe deadlock workaround ─────────────────────────────────────
# Xcode 26.6's build service hangs on the `clang -v -E -dM` capability probe on
# this Mac (see ios/tools/clang-probe-wrapper.sh). The Fastfile also pins these
# via xcargs for the lanes that invoke xcodebuild/gym directly, but exporting
# them here too covers any tool in the chain that reads CC/CPLUSPLUS from the
# environment instead.
export CC="$IOS/tools/clang-probe-wrapper.sh"
export CPLUSPLUS="$IOS/tools/clang-probe-wrapper++.sh"

# ── 4. ship ──────────────────────────────────────────────────────────────────
say "Running fastlane $LANE…"
cd "$IOS" || die "cd $IOS failed"
if fastlane "$LANE"; then
  say "✓ done: fastlane $LANE succeeded"
  case "$LANE" in
    beta)    echo "  → Build uploaded to TestFlight. Add testers in App Store Connect." ;;
    release) echo "  → Uploaded + submitted for review. Apple review ~1–2 days." ;;
    tf_beta_meta) echo "  → Beta metadata filled. Run tf_beta_submit after a build is uploaded." ;;
    tf_beta_submit) echo "  → Submitted latest build for TestFlight Beta App Review." ;;
    tf_public_link) echo "  → Public TestFlight link enabled or requested for the external group." ;;
    tf_invite) echo "  → External tester invites requested for TF_EMAILS." ;;
  esac
else
  die "fastlane $LANE failed — see output above."
fi
