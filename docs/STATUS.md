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
- **Backend — LIVE on AWS App Runner**: deployed via the all-in-one image
  (`deploy/aws/Dockerfile.allinone`: Postgres + Redis + slide-api in one
  container, no external DB). Public HTTPS, health check passing, full smoke
  test green against the live URL.
  - URL: `https://nck3w7ufbz.us-east-1.awsapprunner.com`
  - Health: `GET /v1/health` → `ok` (HTTP 200, verified 2026-05-28)
  - ARN: `arn:aws:apprunner:us-east-1:597088032164:service/slide-api/89ac9a687e7d4077b1a8173188329cdf`
  - Image: `public.ecr.aws/h1f5g0k2/slide:allinone`; 1 vCPU / 2 GB; `SMS_PROVIDER=console`
  - Rough cost ~$5–15/mo. NOTE: in-container DB is **ephemeral** (demo only — set
    external `DATABASE_URL`/`REDIS_URL` env for durable data). See `docs/DEPLOY.md`
    → "Live AWS deployment".

## ⛔ Blocked on a user action (cannot be automated here)

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

## iOS — UPLOADED to App Store Connect (2026-05-30)

- Signed IPA (`app.exla.slide`, v1.0.0) **uploaded via App Store Connect API key** — `altool --validate-app` clean, `altool --upload-app` RC=0 (accepted by Apple).
- App record: "Slide Video Calls", apple_id 1780017294.
- Status: Apple **processing** the build (async ~15-30 min); then submit for review → Apple human review (~1-2 days).
- Auth that worked: ASC API key `7BM5WGWC32` (issuer 69a6de93-…); creds in gitignored `ios/fastlane/.asc.env`.
