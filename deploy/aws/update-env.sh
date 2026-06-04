#!/usr/bin/env bash
# Update the live slide-api App Runner env from deploy/secrets/aws.env, adding
# the security secrets (JWT_SECRET, OTP_PEPPER) that were missing and the
# Firebase project id. Triggers a rolling redeploy. Secrets are read from the
# gitignored aws.env — never hardcoded here.
#
#   AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... ./deploy/aws/update-env.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

REGION=us-east-1
IMAGE="public.ecr.aws/exla/slide:allinone"
FIREBASE_PROJECT_ID="slide-b4c50"

# Load secrets from aws.env (JWT_SECRET, OTP_PEPPER, etc.)
set -a; . deploy/secrets/aws.env; set +a

SVC_ARN=$(aws apprunner list-services --region "$REGION" \
  --query "ServiceSummaryList[?ServiceName=='slide-api'].ServiceArn" --output text)
echo "service: $SVC_ARN"

# Build the env map as JSON (keeps existing SFU/TURN values; adds secrets + firebase).
# DATABASE_URL/REDIS_URL intentionally omitted — the all-in-one image bundles them.
ENV_JSON=$(JWT_SECRET="$JWT_SECRET" OTP_PEPPER="$OTP_PEPPER" \
  SFU_JWT_SECRET="${SFU_JWT_SECRET:-}" TURN_SHARED_SECRET="${TURN_SHARED_SECRET:-}" \
  FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  python3 - <<'PY'
import json, os
env = {
    "JWT_SECRET": os.environ["JWT_SECRET"],
    "OTP_PEPPER": os.environ["OTP_PEPPER"],
    "FIREBASE_PROJECT_ID": os.environ["FIREBASE_PROJECT_ID"],
    # keep auth on Firebase; no dev-code leak, no SNS
    "SMS_PROVIDER": "console",
    "EXPOSE_DEV_OTP": "false",
}
# Preserve SFU/TURN if present in aws.env (harmless until SFU deployed).
for k in ("SFU_JWT_SECRET", "TURN_SHARED_SECRET"):
    v = os.environ.get(k, "")
    if v:
        env[k] = v
print(json.dumps(env))
PY
)

aws apprunner update-service --region "$REGION" --service-arn "$SVC_ARN" \
  --source-configuration "{\"ImageRepository\":{\"ImageIdentifier\":\"$IMAGE\",\"ImageRepositoryType\":\"ECR_PUBLIC\",\"ImageConfiguration\":{\"Port\":\"8080\",\"RuntimeEnvironmentVariables\":$ENV_JSON}},\"AutoDeploymentsEnabled\":false}" \
  --health-check-configuration '{"Protocol":"HTTP","Path":"/v1/health","Interval":10,"Timeout":5,"HealthyThreshold":1,"UnhealthyThreshold":5}' \
  --instance-configuration '{"Cpu":"1024","Memory":"2048"}' \
  >/dev/null
echo "update triggered — App Runner is redeploying (rolling)."
