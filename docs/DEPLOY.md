# Deploying Slide

Three independent surfaces: **backend** (Fly.io + Supabase), **landing site**
(Vercel), **apps** (App Store / Play Store via fastlane).

## Current deployment status (2026-05-28)

| Surface | Status | Notes |
|---|---|---|
| **Landing site** | ✅ **LIVE** | https://web-viraatdas-projects.vercel.app (+ `/privacy`, `/terms`) |
| **Backend (API)** | ⚠️ **AWS plumbing ready; NOT live yet** | App Runner + the public `api-redis` image + the 0.25 vCPU service all work and the image pulls; the container fails its health check only because the Supabase `slide-prod` DB password is unknown here (`Tenant or user not found`). One step to go live — see "AWS deployment" below. |
| **iOS app** | ✅ builds (Simulator) | Submission gated on Apple Developer Program ($99/yr). |
| **Android app** | ✅ `assembleDebug` APK + screenshots | Submission gated on Google Play Console ($25). |
| **App Store / Play Store** | ⛔ gated | Paid accounts + human review (days). See `store/`. |

### Backend on AWS (see "AWS deployment" below)
The AWS App Runner deployment is fully wired and one credential away from live;
the only blocker is the Supabase `slide-prod` DB password. The Fly.io section
further below is an unused alternative path.

## AWS deployment (2026-05-28) — API NOT yet live; one blocker

**Honest status: NOT live.** The AWS plumbing is proven end-to-end EXCEPT the
database credential, which blocks the container from passing its health check.
Everything below is from real command output.

### What works (verified)
- **IAM / key:** `project-leo` (account `597088032164`, us-east-1) **can deploy
  compute.** Verified-allowed (all returned success): `apprunner:*`
  (create/describe/update/delete), `ecr:*` private (describe/login/push),
  `ecr-public:*`, `elasticache:CreateServerlessCache`/`Delete`,
  `ec2:DescribeVpcs`/`DescribeSubnets`, `iam:ListRoles`/`GetRole`.
- **Clock:** in sync with AWS server time; the plain `aws` CLI signs fine. (The
  earlier `deploy/aws/awsclock.py` / `finalize.py` assumed a phantom clock skew
  and a non-existent public ECR alias `o3v8s9k2`; both wrong — kept for reference
  only, NOT used.)
- **Images (both present in this account):**
  - `597088032164.dkr.ecr.us-east-1.amazonaws.com/slide:api` — ECR **private**,
    slide-api only (needs an external Redis).
  - `public.ecr.aws/exla/slide:api-redis` — ECR **public**, slide-api +
    redis-server co-located on loopback (App Runner pulls public images with NO
    IAM role).
- **App Runner pull:** the public image **pulls successfully** (log verbatim:
  `Successfully pulled your application image from ECR`). The earlier private
  attempt failed at pull with `Invalid Access Role` only because it named a
  non-existent role `AppRunnerECRAccessRole`; the REAL role is
  `arn:aws:iam::597088032164:role/AppRunnerECRAccessRole-slide` (exists, has
  `AWSAppRunnerServicePolicyForECRAccess`).
- **App Runner create (0.25 vCPU / 0.5 GB, health `/v1/health`):** the service is
  created and the container starts; redis comes up (`redis ready on
  127.0.0.1:6379`).

### The one blocker — Postgres credential
The container dies at boot with (App Runner application log, verbatim):

```
redis ready on 127.0.0.1:6379
Error: connecting to Postgres
Caused by:
    0: error returned from database: Tenant or user not found
    1: Tenant or user not found
```

App Runner then reports `Container exit code: 1` -> health check failed ->
`CREATE_FAILED`. slide-api runs `sqlx::migrate!` and opens the pool at boot
(`crates/slide-api/src/main.rs`, `.connect(&cfg.database_url)`), so it cannot go
healthy without a working DB.

Root cause: the only Supabase project available is **`slide-prod`**
(ref `zvszgzczlotvtqzchgbc`, org `mnsursgxxpajjocvmvwb`, us-east-1), but its
Postgres password is unknown here. The password previously stored in
`deploy/secrets/aws.env` belonged to a **different, now-deleted** project
(ref `ozkrlqhkkkpwabxhqxnr`) — its pooler returns "Tenant or user not found".
Recovery paths tried and failed:

- Reset `slide-prod`'s DB password via the Supabase Management API — the local
  Supabase CLI keychain token is **not** a valid management bearer (API returns
  `401 {"message":"JWT could not be decoded"}`).
- Create a fresh Supabase project — **blocked**: the org is at its free-project
  limit (`viraatdas (2 project limit)`).

### NEXT USER ACTION (single step to go live)
Put a working `slide-prod` **session-pooler** connection string in
`deploy/secrets/aws.env` as `DATABASE_URL`, then run the deploy script. Get it
from the Supabase dashboard -> project `slide-prod` -> Connect -> **Session
pooler** (port **5432**, NOT the 6543 transaction pooler — sqlx uses prepared
statements):

```
DATABASE_URL=postgres://postgres.zvszgzczlotvtqzchgbc:<DB_PASSWORD>@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require
```

(If the password is unknown, reset it in Settings -> Database -> Reset database
password — non-destructive to data.)

Then:

```bash
# (optional) let the app own a clean schema:
psql "$DATABASE_URL" -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'

# create/update the App Runner service from the public co-located-redis image,
# wait for RUNNING, print the live URL (reads deploy/secrets/aws.env):
./deploy/aws/deploy-apprunner.sh

# verify:
URL=$(aws --profile slide apprunner list-services --region us-east-1 \
  --query "ServiceSummaryList[?ServiceName=='slide-api'].ServiceUrl | [0]" --output text)
curl -fsS "https://$URL/v1/health"            # expect: ok
BASE="https://$URL/v1" PHONE_A=+14155559001 PHONE_B=+14155559002 ./scripts/smoke.sh
```

`deploy/aws/deploy-apprunner.sh` (added) is the working path: it deploys the
public `api-redis` image as `ECR_PUBLIC` (no access role), 0.25 vCPU / 0.5 GB,
health `/v1/health`, env from `deploy/secrets/aws.env` (`SMS_PROVIDER=console`,
secrets via `openssl rand -hex 32`). It auto-deletes a prior `CREATE_FAILED`
service before recreating.

### Cost (smallest, once live)
App Runner 0.25 vCPU / 0.5 GB ~ **$5-10/mo**; ECR Public **free**; Supabase
`slide-prod` free tier **$0** (Pro $25/mo for always-on); Redis **$0** (in-image).
**Total ~ $5-10/month.**

### SFU / media (UDP) — deferred
The control plane is what's being deployed. The `slide-sfu` media plane is
separate: App Runner has no inbound UDP (WebRTC media needs it). Deploy
`slide-sfu` on ECS Fargate / EC2 behind an NLB exposing the UDP media range, then
set `SFU_PUBLIC_URL`. Until then the API returns the `ws://localhost:9000`
placeholder.


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
