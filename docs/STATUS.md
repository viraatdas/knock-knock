# Slide — build status

_Toward the goal: a polished white/thin-black phone-only video caller, deployed
to the App Store and Google Play._

## ✅ Done & verified
- **slide-core**: models, JWT (access + SFU join, strict expiry), OTP hashing,
  phone E.164, TURN REST creds. Unit-tested.
- **slide-api** (axum): phone-OTP auth (request/verify/refresh/logout) with Redis
  OTP + per-phone rate limiting, `/me` + avatar + devices, contacts sync/list,
  call control plane (create/accept/decline/leave/history) with SFU room
  allocation + scoped join tokens + ephemeral TURN creds, app-signaling
  WebSocket + presence hub.
- **slide-sfu** (webrtc-rs): join-token auth gate, JSON SDP/ICE signaling,
  selective forwarding (publish → fan-out → renegotiate → RTP pump), 1:1 + group.
- **Backend gates GREEN**: `cargo fmt --check`, `clippy -D warnings` (zero),
  13/13 tests, release build. `scripts/smoke.sh` (full phone-auth → contacts →
  1:1 call → history) and `scripts/sfu-handshake.mjs` (join-token upgrade +
  ping/pong; bad token rejected) both pass against live Postgres + Redis + SFU.
- **iOS** (SwiftUI): `xcodebuild -sdk iphonesimulator build` → **BUILD SUCCEEDED**;
  Slide.app launches in the Simulator; Welcome screenshots captured
  (`ios/screenshots/`). Onboarding/tabs/in-call/CallKit, APIClient + Keychain +
  silent refresh, app-signaling WS, CallService (WebRTC + mock).
- **Android** (Kotlin/Compose): `./gradlew assembleDebug` → APK at
  `android/app/build/outputs/apk/debug/`; Welcome + Enter-phone screenshots
  captured. Parity app + Telecom + WebRTC (mock default).
- **Landing site** (Next.js): **LIVE** at
  https://web-viraatdas-projects.vercel.app (+ `/privacy`, `/terms`).
- **Infra/CI/store**: docker-compose, multi-bin Dockerfile, Fly configs,
  deploy/smoke/handshake scripts, GitHub Actions, `store/` submission package.

## ⛔ Blocked on the user (cannot be automated here)
- **Backend cloud deploy** — Fly.io refuses `apps create`: *"You must add a
  payment method to your account."* Add a card at fly.io/dashboard → Billing,
  then run `./scripts/deploy-backend.sh`. (Or deploy the same Docker image to
  AWS; rotate the pasted AWS key first.)
- **App Store** — needs Apple Developer Program ($99/yr) + signing + review.
- **Play Store** — needs Google Play Console ($25) + upload keystore + review.
- **Production SMS** — Twilio (or similar) credentials for real OTP delivery.
- **Rotate the AWS access key that was pasted into chat.**

## Media-path caveat
The SFU **signaling** path is verified end-to-end (auth + SDP/ICE plumbing). Live
audio/video between two real devices over the SFU/TURN was not verifiable in this
environment (no two devices on real networks); clients default to a mock
CallService so all UI renders. Flip to the real WebRTC service on-device.
