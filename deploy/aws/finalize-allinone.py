#!/usr/bin/env python3
"""Create/update the Slide App Runner service from the all-in-one ECR Public image.

The all-in-one image bundles Postgres + Redis + slide-api in one container, so
there is NO external database/cache requirement (unlike finalize.py, which wires
Supabase + external Redis and refuses to run without those secrets).

Prefer the plain `aws apprunner create-service` CLI (see docs/DEPLOY.md). Use
this script only if the local clock is skewed and the CLI fails SigV4 signing
with SignatureDoesNotMatch: awsclock patches botocore to sign with corrected
server time.

    python3 deploy/aws/finalize-allinone.py
"""
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import awsclock  # noqa: E402  (patches botocore signing clock on import)

SERVICE_NAME = "slide-api"
IMAGE = "public.ecr.aws/h1f5g0k2/slide:allinone"
PORT = "8080"

SOURCE = {
    "ImageRepository": {
        "ImageIdentifier": IMAGE,
        "ImageRepositoryType": "ECR_PUBLIC",
        "ImageConfiguration": {
            "Port": PORT,
            "RuntimeEnvironmentVariables": {"SMS_PROVIDER": "console"},
        },
    },
    "AutoDeploymentsEnabled": False,
}
HEALTH = {
    "Protocol": "HTTP",
    "Path": "/v1/health",
    "Interval": 10,
    "Timeout": 5,
    "HealthyThreshold": 1,
    "UnhealthyThreshold": 5,
}
INSTANCE = {"Cpu": "1024", "Memory": "2048"}  # 1 vCPU / 2 GB (Postgres needs >0.5GB)


def main() -> int:
    ar = awsclock.session().client("apprunner")

    existing = None
    for svc in ar.list_services()["ServiceSummaryList"]:
        if svc["ServiceName"] == SERVICE_NAME:
            existing = svc["ServiceArn"]
            break

    if existing:
        print("Updating existing service:", existing)
        ar.update_service(
            ServiceArn=existing,
            SourceConfiguration=SOURCE,
            HealthCheckConfiguration=HEALTH,
            InstanceConfiguration=INSTANCE,
        )
        arn = existing
    else:
        print("Creating App Runner service:", SERVICE_NAME)
        r = ar.create_service(
            ServiceName=SERVICE_NAME,
            SourceConfiguration=SOURCE,
            HealthCheckConfiguration=HEALTH,
            InstanceConfiguration=INSTANCE,
        )
        arn = r["Service"]["ServiceArn"]

    url = None
    for _ in range(60):  # ~10 min
        d = ar.describe_service(ServiceArn=arn)["Service"]
        status = d["Status"]
        url = d.get("ServiceUrl")
        print("status:", status, "url:", url, flush=True)
        if status == "RUNNING":
            break
        if status in ("CREATE_FAILED", "DELETE_FAILED"):
            print("Service failed. Check App Runner logs in CloudWatch.")
            return 1
        time.sleep(15)

    print(json.dumps({"arn": arn, "url": url, "status": status}, indent=2))
    return 0 if status == "RUNNING" else 1


if __name__ == "__main__":
    sys.exit(main())
