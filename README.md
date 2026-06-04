# Slide

**For the friends who never call.** The cleanest, fastest cross-platform video
caller — phone-number-only signup, white background, thin black type.

- **Clients:** native iOS (SwiftUI) + Android (Kotlin/Compose), CallKit /
  ConnectionService, native WebRTC.
- **Media:** raw WebRTC through our own SFU (`webrtc-rs`) + coturn (STUN/TURN).
- **Backend:** Rust (axum + sqlx + tokio), Postgres, Redis.
- **v1 scope:** 1:1 + group calls with screen share.

## Repository layout

```
crates/
  slide-core/   shared models, JWT, OTP, phone E.164, TURN creds   (lib, tested)
  slide-api/    axum control plane: auth, /me, contacts, calls, ws (binary)
  slide-sfu/    webrtc-rs SFU: signaling + selective forwarding     (binary)
ios/            SwiftUI app                          (see ios/README.md)
android/        Jetpack Compose app                  (see android/README.md)
web/            Next.js marketing site               (see web/README.md)
deploy/fly/     Fly.io configs (api, sfu, coturn)
scripts/        smoke.sh (API e2e), deploy-backend.sh
AGENTS.md       internal API, design, deploy, SFU, and release notes
migrations/     in crates/slide-api/migrations (embedded at build time)
```

## Run the backend locally

```bash
docker compose up -d              # Postgres, Redis, coturn
cp .env.example .env              # (a dev .env is already present)
cargo run -p slide-api            # http://localhost:8080  (runs migrations)
cargo run -p slide-sfu            # ws://localhost:9000     (in another shell)
```

Smoke-test the whole phone-auth + call flow (uses the dev OTP):

```bash
./scripts/smoke.sh
```

## Test

```bash
cargo test                        # slide-core unit tests (jwt, otp, phone, turn)
```

## Deploy

Backend -> Fly.io/AWS; landing site -> Vercel; apps -> App Store / Play Store
via fastlane (gated on paid developer accounts). See the per-platform READMEs;
maintainer details live in `AGENTS.md`.

## Design

Pure white `#FFFFFF`, near-black `#0A0A0A` thin text, gray `#6B7280`, hairline
`#ECECEC`, red `#E5484D` for destructive actions only. Same system on every
surface.
