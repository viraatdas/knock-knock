# Deploying Slide

Three independent surfaces: **backend** (Fly.io + Supabase), **landing site**
(Vercel), **apps** (App Store / Play Store via fastlane).

## Current deployment status (2026-05-28)

| Surface | Status | Notes |
|---|---|---|
| **Landing site** | ✅ **LIVE** | https://web-viraatdas-projects.vercel.app (+ `/privacy`, `/terms`) |
| **Backend (API)** | ✅ **LIVE on AWS App Runner** | `slide-api` running on App Runner, public HTTPS, `/v1/health` → `ok`, full smoke test passes. Postgres = Supabase, Redis = co-located in-container (IAM can't provision managed Redis). SFU/TURN media plane deferred. See "Live AWS deployment" below. (Fly path blocked — no payment method.) |
| **iOS app** | ✅ builds (Simulator) | Submission gated on Apple Developer Program ($99/yr). |
| **Android app** | ✅ `assembleDebug` APK + screenshots | Submission gated on Google Play Console ($25). |
| **App Store / Play Store** | ⛔ gated | Paid accounts + human review (days). See `store/`. |

### Backend is live on AWS (see "Live AWS deployment" below)
The API control plane is deployed on AWS App Runner and verified. The Fly path
below is an unused alternative (blocked on a Fly payment method).

**Alternative (AWS):** the same multi-bin `Dockerfile` runs on AWS App Runner /
ECS Fargate behind an NLB (the SFU needs UDP for media; coturn handles relay).
Not done here because it can't be verified in this environment, and the pasted
AWS key must be rotated first.

## Live AWS deployment (2026-05-28)

**Status: LIVE and verified.** `slide-api` runs on AWS App Runner with a public
HTTPS URL; `/v1/health` returns `ok` and the full end-to-end smoke test
(`scripts/smoke.sh`) passes against the live URL.

- **Live API base:** `https://p2x8mnq9vh.us-east-1.awsapprunner.com/v1`
- **Health:** `https://p2x8mnq9vh.us-east-1.awsapprunner.com/v1/health` -> `ok`

| Piece | Value |
|-------|-------|
| Compute | AWS App Runner service `slide-api`, **0.25 vCPU / 0.5 GB** (smallest) |
| Service ARN | `arn:aws:apprunner:us-east-1:597088032164:service/slide-api/3d8f1b2c9a7e44d6b1f0c5e8d2a4b6f9` |
| Region / account | `us-east-1` / `597088032164` (IAM user `project-leo`) |
| Image | `public.ecr.aws/exla/slide:api-redis` (ECR **Public**, `ImageRepositoryType: ECR_PUBLIC`) |
| Database | Supabase `slide-prod` (ref `zvszgzczlotvtqzchgbc`), **session pooler** `aws-0-us-east-1.pooler.supabase.com:5432` (port 5432, prepared-statement safe). Schema created by the app's own `sqlx::migrate!` on first boot (`crates/slide-api/migrations/0001_init.sql`, via `crates/slide-core/src/db.rs`). |
| Redis | **co-located inside the image** (redis-server on loopback). slide-api opens a Redis `ConnectionManager` at boot and exits if Redis is unreachable, so it ships in-image. |
| SMS | `SMS_PROVIDER=console` (dev OTP returned as `devCode`) |
| Secrets | `deploy/secrets/aws.env` (gitignored): `JWT_SECRET`, `SFU_JWT_SECRET`, `OTP_PEPPER`, `TURN_SHARED_SECRET` (each `openssl rand -hex 32`) |

### Why ECR Public (and how to switch to the private image)
App Runner pulls **ECR Public** images with **no IAM access role**, the simplest
reliable path. The clean slide-api-only binary also lives in the **private** repo
as `597088032164.dkr.ecr.us-east-1.amazonaws.com/slide:api`; to deploy that,
set `ImageRepositoryType: ECR` + `AuthenticationConfiguration.AccessRoleArn` to
the real role `arn:aws:iam::597088032164:role/AppRunnerECRAccessRole-slide` (it
exists, with `AWSAppRunnerServicePolicyForECRAccess`) **and** supply a reachable
external `REDIS_URL` (the private image has no co-located Redis). An earlier
attempt failed with `Invalid Access Role` because it used a non-existent role
name `AppRunnerECRAccessRole` (missing the `-slide` suffix).

### IAM scope of `project-leo` (probed 2026-05-28 — all WORKING)
| Action | Result |
|--------|--------|
| `sts:GetCallerIdentity` | allowed |
| `apprunner:*` (create/describe/update/delete) | allowed |
| `ecr:*` private (describe / get-login / push) | allowed |
| `ecr-public:*` (describe / push) | allowed |
| `elasticache:CreateServerlessCache` / `Delete` | allowed (tested + cleaned up) |
| `ec2:DescribeVpcs` / `DescribeSubnets` | allowed (default VPC `vpc-0e16007307831426b`) |
| `iam:ListRoles` / `GetRole` | allowed |

This key **can** deploy compute. The system clock is in sync with AWS server
time, so the plain `aws` CLI signs correctly — no clock-correction shim is
needed. `deploy/aws/awsclock.py` / `finalize.py` from an earlier attempt assumed
a phantom clock skew and a non-existent public ECR alias; both were wrong and
those files are kept only for reference (NOT used by the working path).

### Cost (us-east-1, smallest config)
- App Runner 0.25 vCPU / 0.5 GB: ~$5/mo memory floor + active-vCPU only while
  serving; light traffic ~**$5-10/mo**.
- ECR Public storage: **free**.
- Supabase `slide-prod`: free tier (**$0**; pauses after ~7 days idle; Pro is
  $25/mo for always-on).
- Redis: **$0** (in-image).

**Total AWS ~ $5-10/month.**

### Reproduce / redeploy (exact commands)
```bash
# 0. Identity (clock is in sync; CLI signs fine)
aws --profile slide sts get-caller-identity

# 1. Create/update the App Runner service from the public image, wait for
#    RUNNING, print the live URL (reads deploy/secrets/aws.env):
./deploy/aws/deploy-apprunner.sh

# Get the live URL any time:
aws --profile slide apprunner list-services --region us-east-1   --query "ServiceSummaryList[?ServiceName=='slide-api'].ServiceUrl | [0]" --output text

# 2. Verify:
curl -fsS https://p2x8mnq9vh.us-east-1.awsapprunner.com/v1/health   # -> ok
BASE=https://p2x8mnq9vh.us-east-1.awsapprunner.com/v1   PHONE_A=+14155559001 PHONE_B=+14155559002 ./scripts/smoke.sh
```

The DB schema is owned by the app's `sqlx::migrate!` on boot. If you ever need to
re-apply from scratch, wipe the schema first:
`psql "$DATABASE_URL" -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'`.

### Smoke test result (live)
```
== health ==                          ok
== user A login == / == user B login ==   (OTP via console devCode)
== A sets name ==                     Alice
== A registers device ==             ok
== A syncs contacts (knows B) ==     True
== A starts a 1:1 call to B ==       (call created; sfuUrl=ws://localhost:9000 placeholder)
== B accepts ==                      active
== B leaves ==                       200
== A call history ==                 ended
== refresh + logout A ==            logout=204
✅ smoke test passed
```

### Point the apps at the live API
Set the API base URL to `https://p2x8mnq9vh.us-east-1.awsapprunner.com/v1` in iOS
`Config.swift` and Android `Config.kt`.

### SFU / media (UDP) — deferred
The control plane (auth / contacts / call signaling) is fully live. The
`slide-sfu` media plane is separate and not deployed: App Runner has no inbound
UDP, which WebRTC media needs. Deploy `slide-sfu` on ECS Fargate / EC2 with a
public IP behind an NLB exposing the UDP media range, then set `SFU_PUBLIC_URL`
on the service. Until then the API returns the `ws://localhost:9000` placeholder.

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
