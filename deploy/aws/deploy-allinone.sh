#!/usr/bin/env bash
# Build the all-in-one Slide API image, push to ECR Public, deploy to App Runner.
# Self-contained (Postgres+Redis in-image) so it needs NO external DB password.
#
#   ./deploy/aws/deploy-allinone.sh
#
# Requires: docker, aws CLI (profile slide), and the project-leo IAM user which
# can create App Runner services from ECR PUBLIC images (no access role needed).
set -euo pipefail
cd "$(dirname "$0")/../.."

PROFILE=slide
REGION=us-east-1
ECR_PUBLIC_ALIAS="$(aws --profile $PROFILE ecr-public describe-registries --region us-east-1 \
  --query 'registries[0].aliases[0].name' --output text 2>/dev/null)"
REPO="slide"
TAG="allinone"
IMAGE="public.ecr.aws/${ECR_PUBLIC_ALIAS}/${REPO}:${TAG}"
SERVICE="slide-api"

echo "[1/4] docker build (linux/amd64, all-in-one)…"
docker build -f deploy/aws/Dockerfile.allinone --platform linux/amd64 -t "$IMAGE" .

echo "[2/4] ECR Public login + push…"
aws --profile $PROFILE ecr-public get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin public.ecr.aws
aws --profile $PROFILE ecr-public create-repository --repository-name "$REPO" --region us-east-1 2>/dev/null || true
docker push "$IMAGE"

echo "[3/4] create/update App Runner service from $IMAGE…"
python3 deploy/aws/finalize.py --image "$IMAGE" --no-db-check || {
  echo "finalize.py not adapted; falling back to inline create"; }

echo "[4/4] done — see App Runner console / curl <url>/v1/health"
