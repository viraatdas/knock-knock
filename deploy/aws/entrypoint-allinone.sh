#!/usr/bin/env bash
# Boot Postgres + Redis locally, then run slide-api. Self-contained container.
set -euo pipefail

PGDATA=/var/lib/postgresql/data
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | head -1)"

echo "[entrypoint] starting redis…"
redis-server --daemonize yes --save "" --appendonly no

echo "[entrypoint] initializing postgres…"
mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  gosu postgres "$PGBIN/initdb" -D "$PGDATA" >/dev/null
fi

# Listen only on localhost inside the container.
echo "host all all 127.0.0.1/32 trust" >> "$PGDATA/pg_hba.conf"
gosu postgres "$PGBIN/pg_ctl" -D "$PGDATA" -o "-c listen_addresses='127.0.0.1' -p 5432" -w start

echo "[entrypoint] creating role + db (idempotent)…"
gosu postgres psql -v ON_ERROR_STOP=0 <<'SQL' || true
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='slide') THEN
    CREATE ROLE slide LOGIN PASSWORD 'slide';
  END IF;
END $$;
SQL
gosu postgres createdb -O slide slide 2>/dev/null || true

# ── decoy-DB guard ────────────────────────────────────────────────────────────
# The postgres started above is a throwaway local instance; real data lives in
# AWS RDS, reached via DATABASE_URL. Refuse to launch the API if DATABASE_URL
# is unset or points at localhost, so a missing secret can never make prod
# silently write to the decoy DB. Set ALLOW_LOCAL_DB=1 to bypass for local dev.
if [ "${ALLOW_LOCAL_DB:-}" != "1" ]; then
  db_host=""
  if [ -n "${DATABASE_URL:-}" ]; then
    # postgres://user:pass@HOST:port/db → HOST
    db_host="$(printf '%s' "$DATABASE_URL" | sed -E 's|^[^/]*//([^@/]*@)?([^:/?#]+).*$|\2|')"
  fi
  if [ -z "${DATABASE_URL:-}" ] || [ "$db_host" = "localhost" ] || [ "$db_host" = "127.0.0.1" ]; then
    echo "" >&2
    echo "[entrypoint] ############################################################" >&2
    echo "[entrypoint] FATAL: DATABASE_URL is unset or points at the LOCAL decoy" >&2
    echo "[entrypoint] postgres (host='${db_host:-<empty>}'). Real data lives in AWS RDS." >&2
    echo "[entrypoint] Set DATABASE_URL to the RDS instance, or export" >&2
    echo "[entrypoint] ALLOW_LOCAL_DB=1 to intentionally use the local DB (dev only)." >&2
    echo "[entrypoint] Refusing to start slide-api." >&2
    echo "[entrypoint] ############################################################" >&2
    exit 1
  fi
fi

echo "[entrypoint] launching slide-api (migrations run on boot)…"
exec /usr/local/bin/slide-api
