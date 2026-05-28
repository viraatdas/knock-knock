# Deploying Slide

Three independent surfaces: **backend** (Fly.io + Supabase), **landing site**
(Vercel), **apps** (App Store / Play Store via fastlane).

## Current deployment status (2026-05-28)

| Surface | Status | Notes |
|---|---|---|
| **Landing site** | ✅ **LIVE** | https://web-viraatdas-projects.vercel.app (+ `/privacy`, `/terms`) |
| **Backend (API + SFU + TURN)** | 🟡 **AWS: image+DB live, one cmd from API live** | Built + verified locally. On AWS: slide-api image pushed to ECR Public, Supabase Postgres live, secrets generated. **Blocked only on Redis** (IAM can't provision it; supply a `REDIS_URL` then `python3 deploy/aws/finalize.py`). See "Live AWS deployment" below. (Fly path also blocked — no payment method.) |
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

## Live AWS deployment (2026-05-28)

Status: **API image + Postgres provisioned and verified; App Runner is one
command away from live; the ONLY blocker is Redis** (cannot be provisioned with
the current AWS IAM, and no external Redis credential is available — see below).

| Piece | Status | Value |
|---|---|---|
| AWS identity | ✅ valid | account `597088032164`, user `project-leo`, region `us-east-1` |
| Container image | ✅ built + pushed | `public.ecr.aws/o3v8s9k2/slide:api` (ECR **Public**, ~28 MB) |
| Postgres | ✅ live + connection verified | Supabase project `slide-prod` (ref `ozkrlqhkkkpwabxhqxnr`), **session pooler** `aws-0-us-east-1.pooler.supabase.com:5432` |
| Secrets | ✅ generated | `deploy/secrets/aws.env` (gitignored, mode 600) |
| Redis | ⛔ **BLOCKED** | not provisionable — see "Redis blocker" |
| App Runner (compute) | ⏸ pending Redis | create with `python3 deploy/aws/finalize.py` once `REDIS_URL` is set |
| SFU / media (UDP) | ⏸ follow-up | App Runner has no UDP; signaling can run on App Runner with TURN relay, media needs ECS/EC2 + NLB (deferred) |

### The clock-skew gotcha (why we drive AWS via Python, not the `aws` CLI)
This machine's system clock is ~120 days ahead of real time. AWS SigV4 allows
only ~5 min of skew, so **every `aws` CLI call fails with
`SignatureDoesNotMatch`** — the key itself is valid (proven by a hand-signed STS
GetCallerIdentity using AWS's server `Date`). All AWS automation here goes
through `deploy/aws/awsclock.py`, which patches botocore's signing timestamp to
AWS server time. To use the `aws` CLI directly you must first fix the system
clock (`sudo sntp -sS time.apple.com`).

### Redis blocker (the one user action that unblocks a live API)
The IAM user `project-leo` can create **ECR (public/private) repos** and **App
Runner services from ECR Public images** (no IAM access role required), but write
access to everything else is denied:
`iam:CreateRole`, `ec2:RunInstances`, `ec2:CreateSecurityGroup`,
`elasticache:CreateServerlessCache`, `memorydb:CreateCluster`,
`lightsail:CreateInstances`, `secretsmanager:CreateSecret` → **all AccessDenied.**
So no AWS-native Redis (ElastiCache/MemoryDB/EC2). The Upstash-via-Vercel path
also fails — it `requires interactive browser confirmation to select a plan and
authorize`. No Upstash/Redis-Cloud API token or `flyctl` exists on the machine.

`slide-api` connects to Redis at boot (`redis::aio::ConnectionManager::new(..).await?`
in `main.rs`) and exits if it's unreachable, so the API cannot go healthy without
a real Redis. **Provide a public TLS Redis URL and you're done:**

1. Create an Upstash Redis DB (https://console.upstash.com → Create Database,
   free tier, region us-east-1). Copy the `rediss://default:<pw>@<host>:6379` URL.
2. Put it in `deploy/secrets/aws.env` as `REDIS_URL=...`.
3. Run the finalizer (creates the App Runner service, waits for health, smoke-tests):
   ```bash
   python3 deploy/aws/finalize.py
   ```
   This prints the live `https://<id>.us-east-1.awsapprunner.com` URL.

### Exact commands used (reproducible)
```bash
# 0. AWS via clock-corrected boto3 (system clock is skewed; aws CLI won't sign)
python3 deploy/aws/awsclock.py                 # -> GetCallerIdentity OK

# 1. ECR Public repo (idempotent) — done
#    public.ecr.aws/o3v8s9k2/slide

# 2. Build + push slide-api (linux/amd64) — done
docker build --platform linux/amd64 --build-arg BIN=slide-api -t slide-api:latest .
PW=$(python3 - <<'PY'
import deploy.aws.awsclock as a, base64
t=a.session().client("ecr-public",region_name="us-east-1").get_authorization_token()["authorizationData"]["authorizationToken"]
print(base64.b64decode(t).decode().split(":",1)[1])
PY
)
echo "$PW" | docker login --username AWS --password-stdin public.ecr.aws
docker tag slide-api:latest public.ecr.aws/o3v8s9k2/slide:api
docker push public.ecr.aws/o3v8s9k2/slide:api

# 3. Postgres (Supabase, session pooler 5432) — done
supabase projects create slide-prod --org-id mnsursgxxpajjocvmvwb \
  --region us-east-1 --db-password "<generated>" -o json
# DATABASE_URL=postgres://postgres.ozkrlqhkkkpwabxhqxnr:<pw>@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require

# 4. Secrets — done (deploy/secrets/aws.env, gitignored)
openssl rand -hex 32   # JWT_SECRET, SFU_JWT_SECRET, OTP_PEPPER, TURN_SHARED_SECRET

# 5. Compute (App Runner) — RUN AFTER setting REDIS_URL:
python3 deploy/aws/finalize.py
```

### Rough monthly cost (smallest sizes)
- App Runner 0.25 vCPU / 0.5 GB, 1 instance always-on: **~$5–7/mo** compute +
  small request/egress. (App Runner bills provisioned memory ~$0.007/GB-hr +
  active vCPU; ~$5/mo floor at this size with light traffic.)
- ECR Public: **free** (public registry).
- Supabase Free tier: **$0** (free project; pauses after 7 days inactivity — bump
  to Pro $25/mo for always-on prod).
- Redis (Upstash free tier): **$0** (pay-per-request beyond free quota).
- **Total ≈ $5–7/mo** until you move Supabase to Pro and/or scale App Runner.

### SFU / media follow-up
App Runner has no inbound UDP, which WebRTC media needs. Options:
(a) run `slide-sfu` *signaling* on a second App Runner service and rely on the
TURN relay for media (note: this is signaling-only, real media path still needs
UDP); (b) deploy `slide-sfu` on ECS Fargate or EC2 with a public IP behind an NLB
exposing the UDP media range. Not done here: (a) Redis is the upstream blocker for
the whole stack, and (b) the SFU needs UDP infra (NLB/EC2) that the current IAM
also can't fully provision. Deploy the API first; tackle the SFU once Redis +
broader IAM are in place.

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
