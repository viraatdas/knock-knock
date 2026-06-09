# Knock Knock

**Video calls you'll actually want to make.** Don't ring people — *knock*.
Your taps travel in real time, the other phone feels your knocking rhythm,
and nobody knows who's at the door until they answer. Phone-number-only
signup, warm eggshell-and-espresso design, no ads, no tracking.

Knock Knock is **open source**. Found a bug or have an idea?
[File an issue](https://github.com/viraatdas/knock-knock/issues) — PRs welcome.

- **Get it:** "Knock Knock - Video Chat" on the iOS App Store (TestFlight for
  the latest builds).
- **Clients:** native iOS (SwiftUI) + Android (Kotlin/Compose), CallKit /
  ConnectionService, native WebRTC.
- **Media:** WebRTC through a self-hosted LiveKit SFU + coturn (STUN/TURN).
- **Backend:** Rust (axum + sqlx + tokio), Postgres, Redis.
- **Scope today:** 1:1 + group video/audio calls, knock-style ringing.
- **History note:** the project was born as "Slide" — internal crate names and
  the `app.exla.slide` bundle id keep that prefix.

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

Warm eggshell `#FAF6EF` backgrounds, espresso `#5A4632` actions, dark-brown
`#2A211B` thin text, taupe `#8A7C6D` secondary, hairline `#E6DCCB`, terracotta
`#D4694F` for end-call/destructive only. Same system on every surface.
