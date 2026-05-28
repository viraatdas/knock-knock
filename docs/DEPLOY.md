# Deploying Slide

Three independent surfaces: **backend** (Fly.io + Supabase), **landing site**
(Vercel), **apps** (App Store / Play Store via fastlane).

## Current deployment status (2026-05-28)

| Surface | Status | Notes |
|---|---|---|
| **Landing site** | ✅ **LIVE** | https://web-viraatdas-projects.vercel.app (+ `/privacy`, `/terms`) |
| **Backend (API + SFU + TURN)** | ⛔ **BLOCKED — Fly billing** | Built, containerized, verified locally (smoke + SFU handshake green). `fly apps create` fails: the Fly account has **no payment method on file**. |
| **iOS app** | ✅ builds (Simulator) | Submission gated on Apple Developer Program ($99/yr). |
| **Android app** | ✅ `assembleDebug` APK + screenshots | Submission gated on Google Play Console ($25). |
| **App Store / Play Store** | ⛔ gated | Paid accounts + human review (days). See `store/`. |

### To unblock the backend deploy (one user action, then one command)
1. Add a payment method to the Fly account: `fly dashboard` → Billing (Fly
   requires a card on file before `fly apps create` / `fly deploy` will run).
2. Provision data stores + deploy everything: `./scripts/deploy-backend.sh`
   (creates the 3 apps, prints the secrets to set, deploys coturn → sfu → api,
   health-checks at the end).
3. Point the apps at it: set the API base URL in `ios` `Config.swift` and
   `android` `Config.kt` to `https://slide-api.fly.dev/v1`.

**Alternative (AWS):** the same multi-bin `Dockerfile` runs on AWS App Runner /
ECS Fargate behind an NLB (the SFU needs UDP for media; coturn handles relay).
Not done here because it can't be verified in this environment, and the pasted
AWS key must be rotated first.

## 1. Backend — Fly.io + Supabase

### Database (Supabase Postgres)
1. Create/reuse a project; grab the connection string → `DATABASE_URL`.
   sqlx uses prepared statements, so use the **session pooler (port 5432)** or a
   direct connection — NOT the transaction pooler (6543), which breaks prepared
   statements.
2. Migrations are embedded in `slide-api` (`sqlx::migrate!`) and run on boot.

### Redis
Upstash (`fly redis create`) or any managed Redis → `REDIS_URL`.

### coturn, SFU, API
```bash
./scripts/deploy-backend.sh   # creates apps, prints secrets to set, deploys all three
```
Generate the shared secrets once (api+sfu must share `SFU_JWT_SECRET`;
api+sfu+coturn must share `TURN_SHARED_SECRET`):
```bash
openssl rand -hex 32   # JWT_SECRET
openssl rand -hex 32   # SFU_JWT_SECRET
openssl rand -hex 32   # OTP_PEPPER
openssl rand -hex 32   # TURN_SHARED_SECRET
```

### SMS (Twilio)
Set `SMS_PROVIDER=twilio` + `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN`/
`TWILIO_FROM_NUMBER`. With `SMS_PROVIDER=console` the code is logged and returned
as `devCode` (dev only).

### Health
- `https://slide-api.fly.dev/v1/health` → `ok`
- `https://slide-sfu.fly.dev/health` → `ok`

## 2. Landing site — Vercel
```bash
cd web && vercel --prod --yes
```
Live: https://web-viraatdas-projects.vercel.app

## 3. Apps — stores (gated on paid accounts)
See `store/app-store-connect.md`, `store/play-console.md`, and
`store/submission-checklist.md`. Privacy + terms are served by the landing site
at `/privacy` and `/terms`.
