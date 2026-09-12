#!/usr/bin/env bash
# End-to-end smoke test of the Knock Knock Speed Date API against a running
# instance.
#
# Usage: BASE=http://localhost:8080/v1 ./scripts/smoke.sh
#
# Drives the full nightly flow: login two users via the dev OTP code, complete
# mutually-compatible profiles, set locations two kilometers apart in SF, join
# the lobby, wait for the matcher to pair them, run the date-end + decision
# flow to a match, exchange a chat message, unmatch (DELETE /matches/:id, per
# SPEC 1.12), then separately exercise block, refresh, logout, and delete.
#
# Requires the API to be running with SMS_PROVIDER=console and
# EXPOSE_DEV_OTP=true (so /auth/request-otp returns devCode) and with the
# nightly session forced open (SESSION_ALWAYS_OPEN=true), since real doors
# only open 7-8 PM America/Los_Angeles.
set -euo pipefail

BASE="${BASE:-http://localhost:8080/v1}"
PHONE_A="${PHONE_A:-+14155550101}"
PHONE_B="${PHONE_B:-+14155550102}"

# Every response is piped through this: `d` is the parsed JSON, `$1` is a
# Python expression over it, e.g. `jqr "d['status']"` or `jqr "len(d)"`.
jqr() { python3 -c "import sys,json
d=json.load(sys.stdin)
print($1)"; }

# Birthdate (ISO date) that makes someone exactly $1 years old today, so the
# test doesn't hardcode an age that drifts as the calendar moves.
birthdate_for_age() {
  python3 -c "import datetime,sys
years=int(sys.argv[1])
today=datetime.date.today()
try:
    bd=today.replace(year=today.year - years)
except ValueError:
    # Feb 29 birthday, non-leap target year.
    bd=today.replace(year=today.year - years, day=28)
print(bd.isoformat())" "$1"
}

expect_status() { # $1=expected $2=actual $3=what
  if [[ "$2" != "$1" ]]; then
    echo "FAIL: $3, expected HTTP $1, got $2" >&2
    exit 1
  fi
}

expect_eq() { # $1=expected $2=actual $3=what
  if [[ "$2" != "$1" ]]; then
    echo "FAIL: $3, expected '$1', got '$2'" >&2
    exit 1
  fi
}

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
  echo "$(echo "$resp" | jqr "d['accessToken']") $(echo "$resp" | jqr "d['refreshToken']") $(echo "$resp" | jqr "d['user']['id']")"
}

echo "== user A login (devCode) =="
read -r A_ACCESS A_REFRESH A_ID < <(login "$PHONE_A")
echo "A id=$A_ID"

echo "== user B login (devCode) =="
read -r B_ACCESS _ B_ID < <(login "$PHONE_B")
echo "B id=$B_ID"

# Ages 28 and 31, mutually in range, opposite genders each interested in the
# other. That's enough to satisfy the matcher's compatibility checks.
A_BIRTHDATE=$(birthdate_for_age 28)
B_BIRTHDATE=$(birthdate_for_age 31)

echo "== A completes profile (age 28) =="
curl -fsS -X PATCH "$BASE/me" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' \
  -d "{\"displayName\":\"Alice\",\"birthdate\":\"$A_BIRTHDATE\",\"gender\":\"woman\",\"interestedIn\":[\"man\"],\"ageMin\":25,\"ageMax\":40,\"bio\":\"Enjoys hiking and good coffee.\"}" \
  | jqr "d['displayName']"

echo "== B completes profile (age 31) =="
curl -fsS -X PATCH "$BASE/me" -H "authorization: Bearer $B_ACCESS" \
  -H 'content-type: application/json' \
  -d "{\"displayName\":\"Bob\",\"birthdate\":\"$B_BIRTHDATE\",\"gender\":\"man\",\"interestedIn\":[\"woman\"],\"ageMin\":24,\"ageMax\":35,\"bio\":\"Into books and bouldering.\"}" \
  | jqr "d['displayName']"

echo "== A and B set locations ~2km apart in SF =="
curl -fsS -o /dev/null -w "A location=%{http_code}\n" -X PUT "$BASE/me/location" \
  -H "authorization: Bearer $A_ACCESS" -H 'content-type: application/json' \
  -d '{"lat":37.7749,"lng":-122.4194}'
curl -fsS -o /dev/null -w "B location=%{http_code}\n" -X PUT "$BASE/me/location" \
  -H "authorization: Bearer $B_ACCESS" -H 'content-type: application/json' \
  -d '{"lat":37.7929,"lng":-122.4194}'

echo "== GET /session =="
SESSION=$(curl -fsS "$BASE/session" -H "authorization: Bearer $A_ACCESS")
IS_OPEN=$(echo "$SESSION" | jqr "d['isOpen']")
echo "isOpen=$IS_OPEN"
if [[ "$IS_OPEN" != "True" ]]; then
  echo "FAIL: session is not open. Start the API with SESSION_ALWAYS_OPEN=true (or use a review phone) for this smoke test." >&2
  exit 1
fi

echo "== A and B join the lobby =="
A_LOBBY=$(curl -fsS -X POST "$BASE/lobby/join" -H "authorization: Bearer $A_ACCESS")
B_LOBBY=$(curl -fsS -X POST "$BASE/lobby/join" -H "authorization: Bearer $B_ACCESS")
A_STATUS=$(echo "$A_LOBBY" | jqr "d['status']")
B_STATUS=$(echo "$B_LOBBY" | jqr "d['status']")

echo "== polling /lobby/heartbeat until matched (up to 15s) =="
ELAPSED=0
while [[ "$A_STATUS" != "matched" || "$B_STATUS" != "matched" ]]; do
  if (( ELAPSED >= 15 )); then
    echo "FAIL: A and B did not match within 15s (A=$A_STATUS B=$B_STATUS)" >&2
    exit 1
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
  A_LOBBY=$(curl -fsS -X POST "$BASE/lobby/heartbeat" -H "authorization: Bearer $A_ACCESS")
  B_LOBBY=$(curl -fsS -X POST "$BASE/lobby/heartbeat" -H "authorization: Bearer $B_ACCESS")
  A_STATUS=$(echo "$A_LOBBY" | jqr "d['status']")
  B_STATUS=$(echo "$B_LOBBY" | jqr "d['status']")
done
echo "matched after ${ELAPSED}s"

A_DATE_ID=$(echo "$A_LOBBY" | jqr "d['date']['id']")
B_DATE_ID=$(echo "$B_LOBBY" | jqr "d['date']['id']")
expect_eq "$A_DATE_ID" "$B_DATE_ID" "A and B's DateSession ids"
echo "dateId=$A_DATE_ID"

echo "== A leaves the date =="
CODE=$(curl -fsS -o /dev/null -w "%{http_code}" -X POST "$BASE/dates/$A_DATE_ID/leave" \
  -H "authorization: Bearer $A_ACCESS")
expect_status 204 "$CODE" "POST /dates/:id/leave"

echo "== both decide 'keep talking' =="
A_DECISION=$(curl -fsS -X POST "$BASE/dates/$A_DATE_ID/decision" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' -d '{"explore":true}')
A_DECISION_STATUS=$(echo "$A_DECISION" | jqr "d['status']")
echo "A decision status=$A_DECISION_STATUS"
expect_eq "waiting" "$A_DECISION_STATUS" "A's decision status (decides first)"

B_DECISION=$(curl -fsS -X POST "$BASE/dates/$A_DATE_ID/decision" -H "authorization: Bearer $B_ACCESS" \
  -H 'content-type: application/json' -d '{"explore":true}')
B_DECISION_STATUS=$(echo "$B_DECISION" | jqr "d['status']")
echo "B decision status=$B_DECISION_STATUS"
expect_eq "matched" "$B_DECISION_STATUS" "B's decision status (decides second)"

MATCH_ID=$(echo "$B_DECISION" | jqr "d['match']['id']")
echo "matchId=$MATCH_ID"

echo "== GET /matches shows 1 for each =="
A_MATCH_COUNT=$(curl -fsS "$BASE/matches" -H "authorization: Bearer $A_ACCESS" | jqr "len(d)")
B_MATCH_COUNT=$(curl -fsS "$BASE/matches" -H "authorization: Bearer $B_ACCESS" | jqr "len(d)")
expect_eq "1" "$A_MATCH_COUNT" "A's /matches count"
expect_eq "1" "$B_MATCH_COUNT" "B's /matches count"

echo "== A posts a message =="
curl -fsS -X POST "$BASE/matches/$MATCH_ID/messages" -H "authorization: Bearer $A_ACCESS" \
  -H 'content-type: application/json' -d '{"body":"Hey! Good talking to you tonight."}' \
  | jqr "d['body']"

echo "== B lists messages and sees it =="
B_MESSAGES=$(curl -fsS "$BASE/matches/$MATCH_ID/messages" -H "authorization: Bearer $B_ACCESS")
B_MESSAGE_COUNT=$(echo "$B_MESSAGES" | jqr "len(d['messages'])")
expect_eq "1" "$B_MESSAGE_COUNT" "B's message count"

echo "== B's unreadCount is 1 before reading =="
B_UNREAD=$(curl -fsS "$BASE/matches" -H "authorization: Bearer $B_ACCESS" | jqr "d[0]['unreadCount']")
expect_eq "1" "$B_UNREAD" "B's unreadCount before marking read"

echo "== B marks the match read =="
CODE=$(curl -fsS -o /dev/null -w "%{http_code}" -X POST "$BASE/matches/$MATCH_ID/read" \
  -H "authorization: Bearer $B_ACCESS")
expect_status 204 "$CODE" "POST /matches/:id/read"

B_UNREAD=$(curl -fsS "$BASE/matches" -H "authorization: Bearer $B_ACCESS" | jqr "d[0]['unreadCount']")
expect_eq "0" "$B_UNREAD" "B's unreadCount after marking read"

echo "== A unmatches (DELETE /matches/:id), per SPEC 1.12's smoke flow =="
CODE=$(curl -fsS -o /dev/null -w "%{http_code}" -X DELETE "$BASE/matches/$MATCH_ID" \
  -H "authorization: Bearer $A_ACCESS")
expect_status 204 "$CODE" "DELETE /matches/:id"

A_MATCH_COUNT=$(curl -fsS "$BASE/matches" -H "authorization: Bearer $A_ACCESS" | jqr "len(d)")
B_MATCH_COUNT=$(curl -fsS "$BASE/matches" -H "authorization: Bearer $B_ACCESS" | jqr "len(d)")
expect_eq "0" "$A_MATCH_COUNT" "A's /matches count after unmatch"
expect_eq "0" "$B_MATCH_COUNT" "B's /matches count after unmatch"

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/matches/$MATCH_ID/messages" \
  -H "authorization: Bearer $A_ACCESS")
expect_status 404 "$CODE" "GET /matches/:id/messages after unmatch"

echo "== A blocks B (independent of the match, which is already gone) =="
CODE=$(curl -fsS -o /dev/null -w "%{http_code}" -X POST "$BASE/users/$B_ID/block" \
  -H "authorization: Bearer $A_ACCESS")
expect_status 204 "$CODE" "POST /users/:id/block"

echo "== A refreshes and logs out =="
NEW=$(curl -fsS -X POST "$BASE/auth/refresh" -H 'content-type: application/json' \
  -d "{\"refreshToken\":\"$A_REFRESH\"}")
A_REFRESH=$(echo "$NEW" | jqr "d['refreshToken']")
curl -fsS -o /dev/null -w "logout=%{http_code}\n" -X POST "$BASE/auth/logout" \
  -H 'content-type: application/json' -d "{\"refreshToken\":\"$A_REFRESH\"}"

echo "== A deletes their account =="
CODE=$(curl -fsS -o /dev/null -w "%{http_code}" -X DELETE "$BASE/me" -H "authorization: Bearer $A_ACCESS")
expect_status 204 "$CODE" "DELETE /me"

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/me" -H "authorization: Bearer $A_ACCESS")
expect_status 401 "$CODE" "GET /me after account deletion"

echo "✅ smoke test passed"
