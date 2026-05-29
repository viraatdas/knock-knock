#!/usr/bin/env bash
# Deploy (create or update) the Slide API on AWS App Runner.
#
# Image: public.ecr.aws/exla/slide:api-redis  (ECR PUBLIC; runs redis-server on
# loopback + slide-api in one container). We use the PUBLIC image because:
#   1. slide-api opens a Redis ConnectionManager at boot and exits if Redis is
#      unreachable (crates/slide-api/src/main.rs), and also runs sqlx::migrate!
#      against Postgres on boot (crates/slide-core/src/db.rs). App Runner has no
#      managed Redis reachable without VPC plumbing, so Redis is co-located.
#   2. App Runner pulls ECR PUBLIC images with NO IAM access role, which avoids
#      the "Invalid Access Role" failure seen when pulling the private repo.
#
# To deploy the slide-api-ONLY private image instead
# (597088032164.dkr.ecr.us-east-1.amazonaws.com/slide:api), set
# ImageRepositoryType=ECR and AuthenticationConfiguration.AccessRoleArn to the
# REAL role arn:aws:iam::597088032164:role/AppRunnerECRAccessRole-slide, and
# provide a reachable external REDIS_URL.
#
# Secrets come from deploy/secrets/aws.env (gitignored). Usage:
#   ./deploy/aws/deploy-apprunner.sh
set -euo pipefail

PROFILE=slide
REGION=us-east-1
SERVICE=slide-api
IMAGE="public.ecr.aws/exla/slide:api-redis"
PORT=8080

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS="$ROOT/deploy/secrets/aws.env"
[ -f "$SECRETS" ] || { echo "missing $SECRETS"; exit 1; }
set -a; . "$SECRETS"; set +a
: "${DATABASE_URL:?}"; : "${JWT_SECRET:?}"; : "${SFU_JWT_SECRET:?}"
: "${OTP_PEPPER:?}"; : "${TURN_SHARED_SECRET:?}"
SMS_PROVIDER="${SMS_PROVIDER:-console}"

aws() { command aws --profile "$PROFILE" --region "$REGION" "$@"; }

ENVJSON=$(python3 - <<PY
import json,os
print(json.dumps({
  "DATABASE_URL": os.environ["DATABASE_URL"],
  "JWT_SECRET": os.environ["JWT_SECRET"],
  "SFU_JWT_SECRET": os.environ["SFU_JWT_SECRET"],
  "OTP_PEPPER": os.environ["OTP_PEPPER"],
  "TURN_SHARED_SECRET": os.environ["TURN_SHARED_SECRET"],
  "SMS_PROVIDER": os.environ["SMS_PROVIDER"],
  "API_BIND": "0.0.0.0:${PORT}",
  "RUST_LOG": "info,slide_api=info",
}))
PY
)
export ENVJSON IMAGE PORT
SRC=$(python3 - <<'PY'
import json,os
print(json.dumps({
  "ImageRepository": {
    "ImageIdentifier": os.environ["IMAGE"],
    "ImageRepositoryType": "ECR_PUBLIC",
    "ImageConfiguration": {
      "Port": os.environ["PORT"],
      "RuntimeEnvironmentVariables": json.loads(os.environ["ENVJSON"]),
    },
  },
  "AutoDeploymentsEnabled": False,
}))
PY
)

HEALTH='{"Protocol":"HTTP","Path":"/v1/health","Interval":10,"Timeout":5,"HealthyThreshold":1,"UnhealthyThreshold":5}'
INSTANCE='{"Cpu":"256","Memory":"512"}'  # 0.25 vCPU / 0.5 GB (smallest)

ARN=$(aws apprunner list-services \
  --query "ServiceSummaryList[?ServiceName=='${SERVICE}'].ServiceArn | [0]" --output text)

# If a prior CREATE_FAILED service exists, delete it first (can't update it).
if [ -n "$ARN" ] && [ "$ARN" != "None" ]; then
  STATUS=$(aws apprunner describe-service --service-arn "$ARN" --query 'Service.Status' --output text)
  if [ "$STATUS" = "CREATE_FAILED" ]; then
    echo "Deleting prior CREATE_FAILED service $ARN"
    aws apprunner delete-service --service-arn "$ARN" >/dev/null || true
    for i in $(seq 1 40); do
      s=$(aws apprunner describe-service --service-arn "$ARN" --query 'Service.Status' --output text 2>/dev/null || echo GONE)
      [ "$s" = "GONE" ] && break; sleep 6
    done
    ARN=""
  fi
fi

if [ -n "$ARN" ] && [ "$ARN" != "None" ]; then
  echo "Updating existing service: $ARN"
  aws apprunner update-service --service-arn "$ARN" \
    --source-configuration "$SRC" --health-check-configuration "$HEALTH" \
    --instance-configuration "$INSTANCE" >/dev/null
else
  echo "Creating App Runner service: $SERVICE"
  ARN=$(aws apprunner create-service --service-name "$SERVICE" \
    --source-configuration "$SRC" --health-check-configuration "$HEALTH" \
    --instance-configuration "$INSTANCE" \
    --query 'Service.ServiceArn' --output text)
fi
echo "ServiceArn: $ARN"

URL=""
for i in $(seq 1 70); do
  read -r STATUS URL < <(aws apprunner describe-service --service-arn "$ARN" \
    --query 'Service.[Status,ServiceUrl]' --output text)
  echo "status=$STATUS url=$URL"
  [ "$STATUS" = "RUNNING" ] && break
  case "$STATUS" in CREATE_FAILED|DELETE_FAILED) echo "FAILED"; exit 1;; esac
  sleep 10
done
echo "LIVE_URL=https://$URL"
