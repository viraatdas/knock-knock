# Knock Knock

**Five-minute video dates, every night, 7 to 8 PM Pacific.** Doors open once
a day. You get paired on video with someone within 75 miles who matches what
you're looking for, you talk for five minutes, then you each privately say
keep talking or pass. Both say keep talking and a text chat opens up. Say
pass and nothing happens, you're just back in line for the next one. Sign in
with your phone number, nothing else to set up.

Knock Knock is **open source**. Found a bug or have an idea?
[File an issue](https://github.com/viraatdas/knock-knock/issues), PRs welcome.

- **Get it:** "Knock Knock - 5 Minute Dates" on the iOS App Store (TestFlight
  for the latest builds).
- **Clients:** native iOS (SwiftUI) only, for now. Android is frozen on the
  old calling product and hasn't been moved to speed dating yet.
- **Media:** WebRTC through a hosted LiveKit room, one per date.
- **Backend:** Rust (axum + sqlx + tokio), Postgres, Redis.
- **Scope today:** nightly lobby, 5-minute 1:1 video dates, mutual-yes
  matching, text-only chat, block/report.
- **History note:** the project was born as "Slide," then shipped as a
  knock-rhythm video caller called "Knock Knock." Internal crate names and
  the `app.exla.slide` bundle id still carry the old prefix.

## Repository layout

```
crates/
  slide-core/   shared models, JWT, OTP, phone E.164            (lib, tested)
  slide-api/    axum control plane: auth, profile, lobby,
                dates, matches, chat, safety, ws               (binary)
  slide-sfu/    legacy webrtc-rs SFU, untouched, still compiles (binary)
ios/            SwiftUI app                          (see ios/README.md)
android/        Jetpack Compose app, frozen on the old calling product
web/            Next.js marketing site               (see web/README.md)
deploy/fly/     Fly.io config for the API
scripts/        smoke.sh (API end-to-end), deploy-backend.sh
AGENTS.md       internal API contract, design tokens, deploy, release notes
migrations/     in crates/slide-api/migrations (embedded at build time)
```

## Run the backend locally

```bash
docker compose up -d              # Postgres, Redis
cp .env.example .env              # fill in the local values, see comments
livekit-server --dev --bind 0.0.0.0 # media, in another shell
cargo run -p slide-api            # http://localhost:8080  (runs migrations)
```

Install the local LiveKit server with `brew install livekit`, or follow the
official install instructions. Production sets `LIVEKIT_URL`,
`LIVEKIT_API_KEY`, and `LIVEKIT_API_SECRET` to one matching deployment; date
endpoints return `503` while any of those are unset.

Real doors only open 7 to 8 PM Pacific. For local testing, set
`SESSION_ALWAYS_OPEN=true` in `.env` so the lobby is always open, or use one
of the review phone numbers (see `AGENTS.md`).

Smoke-test the whole flow, login through a match and a chat message:

```bash
./scripts/smoke.sh
```

## Test

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cd web && npm run build
```

iOS has no unit test target; verification is `xcodegen generate` plus an
`xcodebuild` simulator build (see `AGENTS.md` for the exact command and a
build-service workaround this Mac needs).

## Deploy

Backend to Fly.io, landing site to Vercel, iOS to TestFlight/App Store via
fastlane (gated on a paid Apple Developer account). See `AGENTS.md` for
maintainer details, secrets, and release automation.

## Design

Warm eggshell backgrounds, espresso-brown type, a terracotta accent for
warmth and destructive actions, hairline dividers, no decorative shadows.
The same system is used across iOS and web; the exact tokens live in
`AGENTS.md`.
