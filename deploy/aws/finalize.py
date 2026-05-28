#!/usr/bin/env python3
"""
Finalize the Slide API deployment on AWS App Runner.

Prereqs (already done by the initial deploy):
  - Image pushed to ECR Public: public.ecr.aws/o3v8s9k2/slide:api
  - Supabase Postgres (session pooler) reachable
  - deploy/secrets/aws.env populated with all secrets

The ONLY missing piece is REDIS_URL. Set it in deploy/secrets/aws.env (a public
TLS Redis URL, e.g. an Upstash rediss:// endpoint on port 6379), then run:

    python3 deploy/aws/finalize.py

This creates (or updates) the App Runner service `slide-api`, waits for it to
go healthy, prints the public URL, and runs the smoke test.

Why this script and not the AWS CLI: the local system clock is months ahead of
real time, which breaks SigV4 in the aws CLI (SignatureDoesNotMatch). awsclock
signs with corrected server time. The IAM user `project-leo` can create App
Runner services from ECR PUBLIC images (no IAM access role needed) but cannot
create IAM roles / EC2 / ElastiCache, which is why Redis must be external.
"""
import os
import sys
import time
import subprocess
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import awsclock  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SECRETS = REPO_ROOT / "deploy" / "secrets" / "aws.env"
IMAGE = "public.ecr.aws/o3v8s9k2/slide:api"
SERVICE_NAME = "slide-api"
PORT = "8080"


def load_env():
    env = {}
    for line in SECRETS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


def main():
    env = load_env()
    required = ["DATABASE_URL", "REDIS_URL", "JWT_SECRET", "OTP_PEPPER",
                "SFU_JWT_SECRET", "TURN_SHARED_SECRET"]
    missing = [k for k in required if not env.get(k)]
    if missing:
        print("ERROR: missing required values in deploy/secrets/aws.env:", missing)
        print("Most likely REDIS_URL is still empty. Provision a public TLS Redis")
        print("(e.g. Upstash) and set REDIS_URL, then re-run.")
        sys.exit(2)

    runtime_env = {
        "DATABASE_URL": env["DATABASE_URL"],
        "REDIS_URL": env["REDIS_URL"],
        "JWT_SECRET": env["JWT_SECRET"],
        "OTP_PEPPER": env["OTP_PEPPER"],
        "SFU_JWT_SECRET": env["SFU_JWT_SECRET"],
        "TURN_SHARED_SECRET": env["TURN_SHARED_SECRET"],
        "SMS_PROVIDER": env.get("SMS_PROVIDER", "console"),
        "API_BIND": "0.0.0.0:8080",
        "RUST_LOG": "info,slide_api=info",
    }

    s = awsclock.session()
    ar = s.client("apprunner")

    # Find existing service
    existing = None
    for svc in ar.list_services()["ServiceSummaryList"]:
        if svc["ServiceName"] == SERVICE_NAME:
            existing = svc["ServiceArn"]
            break

    source_config = {
        "ImageRepository": {
            "ImageIdentifier": IMAGE,
            "ImageRepositoryType": "ECR_PUBLIC",
            "ImageConfiguration": {
                "Port": PORT,
                "RuntimeEnvironmentVariables": runtime_env,
            },
        },
        "AutoDeploymentsEnabled": False,
    }
    health = {
        "Protocol": "HTTP",
        "Path": "/v1/health",
        "Interval": 10,
        "Timeout": 5,
        "HealthyThreshold": 1,
        "UnhealthyThreshold": 5,
    }
    instance = {"Cpu": "256", "Memory": "512"}  # 0.25 vCPU / 0.5 GB

    if existing:
        print("Updating existing service:", existing)
        ar.update_service(
            ServiceArn=existing,
            SourceConfiguration=source_config,
            HealthCheckConfiguration=health,
            InstanceConfiguration=instance,
        )
        arn = existing
    else:
        print("Creating App Runner service:", SERVICE_NAME)
        r = ar.create_service(
            ServiceName=SERVICE_NAME,
            SourceConfiguration=source_config,
            HealthCheckConfiguration=health,
            InstanceConfiguration=instance,
        )
        arn = r["Service"]["ServiceArn"]

    # Poll until RUNNING or failed
    url = None
    for _ in range(60):  # up to ~10 min
        d = ar.describe_service(ServiceArn=arn)["Service"]
        status = d["Status"]
        url = d.get("ServiceUrl")
        print("status:", status, "url:", url)
        if status in ("RUNNING",):
            break
        if status in ("CREATE_FAILED", "DELETE_FAILED"):
            print("Service failed. Check App Runner logs in CloudWatch.")
            sys.exit(1)
        time.sleep(10)

    if not url:
        print("No service URL yet; check console.")
        sys.exit(1)

    base = f"https://{url}"
    print("\nService URL:", base)

    # Health check
    health_url = f"{base}/v1/health"
    print("Curling", health_url)
    out = subprocess.run(["curl", "-fsS", health_url], capture_output=True, text=True)
    print("health ->", repr(out.stdout), "exit", out.returncode)

    # Smoke test
    smoke = REPO_ROOT / "scripts" / "smoke.sh"
    print("\nRunning smoke test...")
    sm = subprocess.run(
        ["bash", str(smoke)],
        env={**os.environ,
             "BASE": f"{base}/v1",
             "PHONE_A": "+14155559001",
             "PHONE_B": "+14155559002"},
        capture_output=True, text=True,
    )
    print(sm.stdout)
    print(sm.stderr)
    print("smoke exit:", sm.returncode)
    print("\nDONE. Live API:", base)


if __name__ == "__main__":
    main()
