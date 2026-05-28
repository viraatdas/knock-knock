# Slide — build status

_Toward the goal: a polished white/thin-black phone-only video caller, deployed
to the App Store and Google Play._

## ✅ Done & verified (output seen directly)
- **slide-core**: models, JWT (access + SFU join, strict expiry), OTP hashing,
  phone E.164, TURN REST creds. Unit-tested.
- **slide-api** (axum) + **slide-sfu** (webrtc-rs): full control plane + selective
  forwarding. Backend gates GREEN: `cargo fmt --check`, `clippy -D warnings`
  (zero), 13/13 tests, build. `scripts/smoke.sh` (phone-auth → contacts → 1:1
  call → history) and `scripts/sfu-handshake.mjs` (join-token upgrade + ping/pong;
  bad token rejected) PASS against live Postgres + Redis + SFU.
- **iOS** (SwiftUI): `xcodebuild -scheme Slide -sdk iphonesimulator -destination
  'platform=iOS Simulator,name=iPhone 17 Pro' build` → **BUILD SUCCEEDED**.
  Slide.app launches in the Simulator; a **real** Welcome screenshot
  (`ios/screenshots/01-welcome.png`) shows the thin "Slide" wordmark on white +
  "Get started" + "No usernames. No passwords. Just your number." 9 screens
  captured. Onboarding/tabs/in-call/CallKit, APIClient + Keychain + silent
  refresh, app-signaling WS, CallService (WebRTC + mock default).
- **Android** (Kotlin/Compose): `./gradlew assembleDebug` → real APK; real
  Welcome + Enter-phone screenshots.
- **Landing site** (Next.js): LIVE https://web-viraatdas-projects.vercel.app
  (+ `/privacy`, `/terms`).

## 🔧 In progress (background agents)
- **App Store pipeline** (`ios/fastlane`) — build/beta/release lanes via App
  Store Connect API key. Needs the user's Team ID + ASC API key to archive+upload.
- **Backend → AWS** — ECR + App Runner (API) + Supabase Postgres; SFU media-UDP
  path noted. (User chose AWS over Fly; Fly was blocked on overdue billing.)

## ⛔ Gated on the user
- **App Store submission**: Apple account is paid (user has it). To archive +
  upload, the user must supply: **Team ID** + **App Store Connect API key**
  (`.p8` + key id + issuer id). Then `cd ios && fastlane release`. Review ~1–2 days.
- **Play Store**: Play Console ($25) + upload keystore + review.
- **Production SMS** (Twilio) for real OTP delivery.
- **Rotate the AWS access key that was pasted into chat.**

## Media-path caveat
SFU signaling verified end-to-end (auth + SDP/ICE). Live audio/video between two
real devices over SFU/TURN not verifiable here (no two devices on real
networks); clients default to a mock CallService so all UI renders. Flip to the
real WebRTC service on-device.
