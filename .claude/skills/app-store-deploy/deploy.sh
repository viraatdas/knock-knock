#!/usr/bin/env bash
# app-store-deploy — ship Slide iOS to TestFlight / the App Store from the CLI.
# Usage: deploy.sh [build_sim|bootstrap|beta|release]   (default: build_sim)
set -uo pipefail

LANE="${1:-build_sim}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # repo root
IOS="$ROOT/ios"
ENV_FILE="$IOS/fastlane/.asc.env"

say()  { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
die()  { printf "  \033[31m✗ %s\033[0m\n" "$*"; exit 1; }

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
  set -a; . "$ENV_FILE"; set +a
  ok "loaded $ENV_FILE"
fi
export APP_IDENTIFIER="${APP_IDENTIFIER:-app.slide}"

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
         APP_IDENTIFIER=app.slide

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

# ── 4. ship ──────────────────────────────────────────────────────────────────
say "Running fastlane $LANE…"
cd "$IOS"
if fastlane "$LANE"; then
  say "✓ done: fastlane $LANE succeeded"
  case "$LANE" in
    beta)    echo "  → Build uploaded to TestFlight. Add testers in App Store Connect." ;;
    release) echo "  → Uploaded + submitted for review. Apple review ~1–2 days." ;;
  esac
else
  die "fastlane $LANE failed — see output above."
fi
