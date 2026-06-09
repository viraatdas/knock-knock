#!/usr/bin/env bash
# End-to-end smoke test of the Slide API against a running instance.
# Usage: BASE=http://localhost:8080/v1 ./scripts/smoke.sh
# Exercises the full phone-only auth + contacts + call-create flow using the dev
# OTP returned by /auth/request-otp when EXPOSE_DEV_OTP=true.
set -euo pipefail

BASE="${BASE:-http://localhost:8080/v1}"
PHONE_A="${PHONE_A:-+14155550101}"
PHONE_B="${PHONE_B:-+14155550102}"

jqr() { python3 -c "import sys,json;print(json.load(sys.stdin)$1)"; }

echo "== health =="
curl -fsS "$BASE/health" && echo

login() { # $1 = phone -> echoes "accessToken refreshToken userId"
  local phone="$1"
  local code
  code=$(curl -fsS -X POST "$BASE/auth/request-otp" \
    -H 'content-type: application/json' -d "{\"phone\":\"$phone\"}" |
    python3 -c 'import json,sys
data=json.load(sys.stdin)
code=data.get("devCode")
if not code:
    sys.stderr.write("request-otp did not return devCode; start the API with SMS_PROVIDER=console EXPOSE_DEV_OTP=true\n")
    sys.exit(1)
print(code)')
  local resp
  resp=$(curl -fsS -X POST "$BASE/auth/verify-otp" \
    -H 'content-type: application/json' -d "{\"phone\":\"$phone\",\"code\":\"$code\"}")
  echo "$(echo "$resp" | jqr "['accessToken']") $(echo "$resp" | jqr "['refreshToken']") $(echo "$resp" | jqr "['user']['id']")"
}

echo "== user A login =="
read -r A_ACCESS A_REFRESH A_ID < <(login "$PHONE_A")
echo "A id=$A_ID"

echo "== user B login =="
read -r B_ACCESS B_REFRESH B_ID < <(login "$PHONE_B")
echo "B id=$B_ID"

echo "== A sets name =="
curl -fsS -X PATCH "$BASE/me" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' -d '{"displayName":"Alice"}' | jqr "['displayName']"

echo "== A registers device =="
curl -fsS -X POST "$BASE/devices" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' \
  -d '{"pushToken":"tok-a","platform":"ios","appVersion":"1.0"}' >/dev/null && echo ok

echo "== A syncs contacts (knows B) =="
curl -fsS -X POST "$BASE/contacts/sync" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' \
  -d "{\"phones\":[\"$PHONE_B\"],\"names\":[\"Bob\"]}" | jqr "[0]['onSlide']"

echo "== A starts a 1:1 call to B =="
CALL=$(curl -fsS -X POST "$BASE/calls" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' \
  -d "{\"type\":\"one_to_one\",\"participantUserIds\":[\"$B_ID\"]}")
CALL_ID=$(echo "$CALL" | jqr "['call']['id']")
echo "callId=$CALL_ID sfuUrl=$(echo "$CALL" | jqr "['sfuUrl']")"
echo "joinToken present: $(echo "$CALL" | jqr "['joinToken'][:12]")..."

echo "== B accepts =="
curl -fsS -X POST "$BASE/calls/$CALL_ID/accept" -H "authorization: Bearer $B_ACCESS" \
  | jqr "['call']['status']"

echo "== B leaves =="
curl -fsS -o /dev/null -w "%{http_code}\n" -X POST "$BASE/calls/$CALL_ID/leave" \
  -H "authorization: Bearer $B_ACCESS"

echo "== A call history =="
curl -fsS "$BASE/calls" -H "authorization: Bearer $A_ACCESS" | jqr "['calls'][0]['status']"

echo "== refresh + logout A =="
NEW=$(curl -fsS -X POST "$BASE/auth/refresh" -H 'content-type: application/json' \
  -d "{\"refreshToken\":\"$A_REFRESH\"}")
A_REFRESH=$(echo "$NEW" | jqr "['refreshToken']")
curl -fsS -o /dev/null -w "logout=%{http_code}\n" -X POST "$BASE/auth/logout" \
  -H 'content-type: application/json' -d "{\"refreshToken\":\"$A_REFRESH\"}"

echo "✅ smoke test passed"
