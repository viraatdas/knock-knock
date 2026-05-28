# Slide — build status

_Goal: a polished white/thin-black phone-only video caller, deployed to the
App Store and Google Play._

## ✅ Done & verified (output seen directly)
- **slide-core**: models, JWT (access + SFU join, strict expiry), OTP hashing,
  phone E.164, TURN REST creds. Unit-tested.
- **slide-api** (axum) + **slide-sfu** (webrtc-rs): full control plane + selective
  forwarding. Backend gates GREEN: `cargo fmt --check`, `clippy -D warnings`
  (zero), 13/13 tests, build. `scripts/smoke.sh` (phone-auth → contacts → 1:1
  call → history) and `scripts/sfu-handshake.mjs` (join-token upgrade + ping/pong;
  bad token rejected) PASS against live Postgres + Redis + SFU.
- **iOS** (SwiftUI, bundle id `app.slide`): clean `xcodebuild` for the iOS
  Simulator → **BUILD SUCCEEDED**; app launches; 9 real screenshots in
  `ios/screenshots/` (Welcome shows the thin "Slide" wordmark on white +
  "Get started" + "No usernames. No passwords. Just your number.").
- **Android** (Kotlin/Compose, appId `app.slide`): `./gradlew assembleDebug` →
  real APK; real Welcome + Enter-phone screenshots.
- **Landing site** (Next.js): LIVE https://web-viraatdas-projects.vercel.app
  (+ `/privacy`, `/terms`).
- **App Store pipeline**: `ios/fastlane` (build_sim/bootstrap/archive/beta/release)
  + the **`/app-store-deploy` skill** — one CLI command ships to TestFlight/App
  Store once an API key exists.

## ⛔ Blocked on a user action (cannot be automated here)

### Backend cloud host — needs one of:
- **Fly.io**: blocked — *"account has overdue invoices."* Pay at
  fly.io/dashboard → Billing, then `./scripts/deploy-backend.sh`.
- **AWS** (preferred): the key (IAM user `project-leo`) is **S3-only** — denied
  on ECR/App Runner/ECS/EC2/RDS/Lightsail. Attach ECR + App Runner (or ECS/EC2)
  perms, or provide a capable key/role; then the image deploys to App Runner +
  Supabase Postgres. (See `docs/DEPLOY.md`.)
- Works locally now via `docker compose up -d` + `cargo run`.

### App Store upload — needs (you have the paid Apple account):
1. A **App Store Connect API key** (`.p8` + Key ID + Issuer ID) — create once at
   appstoreconnect.apple.com/access/integrations/api (Apple disallows API
   creation of the first key). The `/app-store-deploy` skill prints the exact
   step + deep link.
2. Your **Team ID** (developer.apple.com → Membership).
3. Then `.claude/skills/app-store-deploy/deploy.sh release`. Apple review ~1–2 days.

### Play Store — Google Play Console ($25) + upload keystore + review.
### Production SMS — Twilio (or similar) creds for real OTP delivery.
### Security — rotate the AWS access key that was pasted into chat.

## Media-path caveat
SFU signaling verified end-to-end (auth + SDP/ICE). Live audio/video between two
real devices over SFU/TURN not verifiable here (no two devices on real
networks); clients default to a mock CallService so all UI renders. Flip to the
real WebRTC service on-device.
