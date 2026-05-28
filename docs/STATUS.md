# Slide — build status

_Living checklist toward the goal: a polished white/thin-black phone-only video
caller, deployed to the App Store and Google Play._

## Done
- [x] Cargo workspace: `slide-core`, `slide-api`, `slide-sfu`.
- [x] `slide-core`: models, JWT (access + SFU join), OTP hashing, phone E.164,
      TURN REST creds. Unit-tested.
- [x] Postgres schema (`crates/slide-api/migrations/0001_init.sql`).
- [x] `slide-api`: phone-OTP auth (request/verify/refresh/logout), `/me`,
      avatar, devices, contacts sync/list, full call control plane
      (create/accept/decline/leave/history), app-signaling WebSocket + presence,
      Redis OTP + rate limiting.
- [x] `slide-sfu`: join-token auth, JSON signaling, webrtc-rs selective
      forwarding (publish → fan-out → renegotiate).
- [x] Local infra: docker-compose (Postgres, Redis, coturn).
- [x] Contracts: `docs/API.md`, `docs/DESIGN.md`.
- [x] Deploy artifacts: Dockerfile, Fly configs (api/sfu/coturn), deploy +
      smoke scripts.

## In progress (parallel agents)
- [ ] iOS app (SwiftUI) — onboarding, tabs, calls, CallKit; build + screenshots.
- [ ] Android app (Compose) — toolchain install + parity app; `assembleDebug`.
- [ ] Landing site (Next.js) — deploy to Vercel, `/privacy` + `/terms`.

## Pending verification (blocked only on a tool-transport hiccup; code is on disk)
- [ ] `cargo build` / `cargo test` whole workspace green.
- [ ] Run `slide-api` + `slide-sfu` locally; `./scripts/smoke.sh` passes.
- [ ] Deploy backend to Fly + Supabase; health checks green.

## Gated on external accounts (cannot be automated here)
- [ ] Apple Developer Program → signing, TestFlight, App Store review.
- [ ] Google Play Console → keystore, AAB upload, review.
- [ ] Twilio (or other SMS) production credentials.
- [ ] **Rotate the AWS key that was pasted into chat.**

## Notes / risks
- The `slide-sfu` media engine is the most version-sensitive code (webrtc-rs
  0.12) and the hardest to verify without two real devices on real networks; it
  may need a compile pass + device smoke test.
- 1:1 calls route through the SFU in v1 for consistent metrics; P2P fast-path is
  a later optimization.
