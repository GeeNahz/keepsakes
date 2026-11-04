#!/bin/bash
# Runs once, when the Postgres volume is first created: a database and a
# login of its own for each environment. Staging's login can't read
# production's database (and the reverse), though they share a server.
#
# The passwords come from infra/.env (PRODUCTION_DB_PASSWORD,
# STAGING_DB_PASSWORD); each app's DATABASE_URL uses its own. A database is
# made only when its password is set, so a server for one environment
# just leaves the other's empty.
set -euo pipefail

create() {
  local role="$1" db="$2" password="$3"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -v role="$role" -v db="$db" -v password="$password" <<'SQL'
CREATE ROLE :"role" LOGIN PASSWORD :'password';
CREATE DATABASE :"db" OWNER :"role";
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
SQL
  # The app's login owns the schema, so its migrations can create tables and
  # the citext extension (a "trusted" extension: no superuser needed)
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
    -v role="$role" <<'SQL'
ALTER SCHEMA public OWNER TO :"role";
SQL
}

if [ -n "${PRODUCTION_DB_PASSWORD:-}" ]; then
  create keepsakes_prod keepsakes_prod "$PRODUCTION_DB_PASSWORD"
fi

if [ -n "${STAGING_DB_PASSWORD:-}" ]; then
  create keepsakes_staging keepsakes_staging "$STAGING_DB_PASSWORD"
fi
