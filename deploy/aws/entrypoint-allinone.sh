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

echo "[entrypoint] launching slide-api (migrations run on boot)…"
exec /usr/local/bin/slide-api
