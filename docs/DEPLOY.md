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

Status: **LIVE.** `slide-api` is running on AWS App Runner with a public HTTPS
URL, `/v1/health` returns `ok`, and the full end-to-end smoke test passes.

- **Live API base:** `https://<service-id>.us-east-1.awsapprunner.com/v1`
  (get the exact host with the command in "Get the live URL" below — App Runner
  generates the `<service-id>` subdomain at create time).
- **Health:** `https://<service-id>.us-east-1.awsapprunner.com/v1/health` → `ok`

| Piece | Status | Value |
|---|---|---|
| AWS identity | ✅ valid | account `597088032164`, user `project-leo`, region `us-east-1` |
| Container image | ✅ built + pushed | `public.ecr.aws/o3v8s9k2/slide:api-redis` (ECR **Public**, combined redis+api, linux/amd64) |
| Compute | ✅ **LIVE** | App Runner service `slide-api`, 0.25 vCPU / 0.5 GB, health path `/v1/health` |
| Postgres | ✅ live + verified | Supabase project `slide-prod` (ref `ozkrlqhkkkpwabxhqxnr`), **session pooler** `aws-0-us-east-1.pooler.supabase.com:5432` |
| Redis | ✅ co-located in container | `redis://127.0.0.1:6379` (ephemeral OTP/presence; see "Redis: why co-located") |
| Secrets | ✅ generated | `deploy/secrets/aws.env` (gitignored) |
| SFU / media (UDP) | ⏸ follow-up | App Runner has no inbound UDP; media needs ECS/EC2 + NLB (deferred) |

### Clock skew (historical note)
A prior run hit `SignatureDoesNotMatch` because the system clock was ~120 days
ahead (SigV4 allows ~5 min skew), and worked around it via `deploy/aws/awsclock.py`
(patches botocore's signing timestamp to AWS server time). **The clock is now in
sync**, so the `aws` CLI signs correctly and is used directly. If the CLI ever
fails with `SignatureDoesNotMatch` again, fix the clock first:
`sudo sntp -sS time.apple.com` (or fall back to `awsclock.py`).

### IAM scope of user `project-leo` (probed 2026-05-28)
| Action | Result |
|---|---|
| `sts:GetCallerIdentity` | ✅ allowed |
| `apprunner:*` (list/create/describe/update service) | ✅ allowed |
| `ecr-public:*` (describe-repositories, get-login-password, push) | ✅ allowed |
| `ecr:DescribeRepositories` (ECR **private**) | ⛔ `AccessDeniedException` |
| `elasticache:DescribeCacheClusters` / `DescribeServerlessCaches` | ⛔ `AccessDenied` |
| `ec2:DescribeVpcs` (and all EC2) | ⛔ `AccessDenied` |

So: App Runner + ECR **Public** work; ECR private, ElastiCache, and EC2/VPC are
all denied. App Runner can pull from ECR Public with **no IAM access role**, which
is why this path needs no `iam:CreateRole`.

### Redis: why co-located (and how to move it out later)
`slide-api` opens a Redis `ConnectionManager` at boot (`main.rs`) and exits if
Redis is unreachable, so it can't go healthy without Redis. With this IAM there
is **no AWS-native Redis** (ElastiCache/MemoryDB/EC2 all denied) and **no VPC
connector** (EC2 denied) to reach one, and no external managed-Redis credential
(e.g. Upstash) is available non-interactively. Redis here only stores **ephemeral
OTP codes/attempts with TTLs** (`otp_store.rs`), so it is co-located in the same
App Runner container via `deploy/aws/Dockerfile.combined` + `entrypoint.sh`
(`redis-server` on loopback, `maxmemory 64mb`, no persistence). This is correct
for the current workload.

To move Redis to a managed service later (recommended once the app stores
anything non-ephemeral or scales past one instance): create an Upstash Redis DB
(`rediss://default:<pw>@<host>:6379`, region us-east-1), set `REDIS_URL` in
`deploy/secrets/aws.env`, swap the image back to the plain `:api` tag in
`deploy/aws/deploy.sh`, and re-run it.

### Reproduce / redeploy (exact commands)
```bash
# 0. Confirm identity (clock must be within ~5 min of real time)
aws --profile slide sts get-caller-identity

# 1. Build + push the combined redis+api image to ECR Public
./deploy/aws/build-image.sh
#    -> public.ecr.aws/o3v8s9k2/slide:api-redis  (linux/amd64)

# 2. Create (or update) the App Runner service, wait for RUNNING,
#    health-check, and run the smoke test:
./deploy/aws/deploy.sh

# Get the live URL any time:
aws --profile slide apprunner list-services --region us-east-1 \
  --query "ServiceSummaryList[?ServiceName=='slide-api'].ServiceUrl | [0]" --output text

# Manual health + smoke against the live URL:
URL=$(aws --profile slide apprunner list-services --region us-east-1 \
  --query "ServiceSummaryList[?ServiceName=='slide-api'].ServiceUrl | [0]" --output text)
curl -fsS "https://$URL/v1/health"
BASE="https://$URL/v1" PHONE_A=+14155559001 PHONE_B=+14155559002 ./scripts/smoke.sh
```

### Smoke test result (live, 2026-05-28)
```
== health == ok
== user A login == / == user B login == (OTP via console devCode)
== A sets name == Alice
== A registers device == ok
== A syncs contacts (knows B) == True
== A starts a 1:1 call to B == (call created)
== B accepts == ringing
== B leaves == 200
== A call history == ended
== refresh + logout A == logout=204
✅ smoke test passed
```
(`sfuUrl` is still the `ws://localhost:9000` placeholder — the SFU media plane is
a separate deferred surface; control-plane call flow is fully working.)

### Point the apps at the live API
Set the API base URL to `https://<service-id>.us-east-1.awsapprunner.com/v1` in
iOS `Config.swift` and Android `Config.kt`.

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
- Redis: **$0** (co-located in the App Runner container; no separate service).
- **Total ≈ $5–7/mo** until you move Supabase to Pro and/or scale App Runner.

### SFU / media follow-up (deferred — not blocking the API)
The API control plane is live. The SFU media plane is separate and not yet
deployed. App Runner has no inbound UDP, which WebRTC media needs. Options:
(a) run `slide-sfu` *signaling* on a second App Runner service and rely on the
TURN relay for media (signaling-only; real media path still needs UDP);
(b) deploy `slide-sfu` on ECS Fargate or EC2 with a public IP behind an NLB
exposing the UDP media range. Not done here because the SFU needs UDP infra
(NLB/EC2) that the current IAM can't provision (`ec2:*` is AccessDenied — see
the IAM table above). The live API returns the placeholder `SFU_PUBLIC_URL`
until the SFU is deployed and `SFU_PUBLIC_URL` is set on the App Runner service.

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
