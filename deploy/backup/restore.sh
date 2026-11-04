#!/bin/bash
# Restores a database dump from the backups. Needs the age private key,
# mounted for that one run at /run/age/identity (bin/backup does this).
#
#   restore.sh drill [env]              newest dump of env (production) into a
#                                       scratch database, print row counts,
#                                       drop it. Proves the backups work.
#   restore.sh into <env> <db> [file]   a dump (default: the newest) into a
#                                       NEW database <db>; it must not exist.
#                                       Switch the app to it afterwards
#                                       (DEPLOYMENT.md, "Restoring").
#   restore.sh list [env]               the dumps there are
set -euo pipefail

remote="${BACKUP_REMOTE:-r2}:${BACKUP_BUCKET:-keepsakes-backups}"
identity=/run/age/identity

die() { echo "restore: $*" >&2; exit 1; }
log() { echo "restore: $*"; }

dumps() {
  local env="$1"
  # weekly/ and monthly/ don't exist until their first run (rclone exits 3)
  for kind in daily weekly monthly; do
    { rclone lsf --files-only --include "*.dump.age" "$remote/$env/$kind" 2>/dev/null || true; } |
      sed "s|^|$kind/|"
  done
}

newest() {
  dumps "$1" | awk -F/ '{print $2 " " $0}' | sort | tail -1 | cut -d' ' -f2
}

# Downloads and decrypts <env>/<path> into a local file; prints its path
fetch() {
  local env="$1" path="$2" out
  [ -f "$identity" ] || die "no age identity at $identity (bin/backup mounts it)"
  out="$(mktemp -d)/restore.dump"
  rclone cat "$remote/$env/$path" | age -d -i "$identity" >"$out"
  echo "$out"
}

db_exists() {
  psql -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$1'" | grep -q 1
}

restore_into() {
  local db="$1" file="$2"
  createdb "$db"
  # Objects end up owned by whoever restores; the app's login is given
  # ownership afterwards (DEPLOYMENT.md)
  pg_restore --no-owner --no-privileges --exit-on-error -d "$db" "$file"
}

case "${1:-}" in
  list)
    dumps "${2:-production}"
    ;;

  drill)
    env="${2:-production}"
    db=keepsakes_restore_drill
    path="$(newest "$env")"
    [ -n "$path" ] || die "no dumps for $env yet"

    log "drill: $env/$path"
    file="$(fetch "$env" "$path")"
    if db_exists "$db"; then dropdb "$db"; fi
    restore_into "$db" "$file"

    log "rows in the restored copy:"
    for table in users albums memories invoices payments; do
      printf '  %-10s %s\n' "$table" "$(psql -d "$db" -Atc "SELECT count(*) FROM $table")"
    done
    log "latest migration: $(psql -d "$db" -Atc 'SELECT max(version) FROM schema_migrations')"

    dropdb "$db"
    rm -f "$file"
    log "drill passed; scratch database dropped"
    ;;

  into)
    env="${2:-}"
    db="${3:-}"
    if [ -z "$env" ] || [ -z "$db" ]; then
      die "usage: restore.sh into <env> <new db> [file]"
    fi
    db_exists "$db" && die "$db already exists; pick a new name"
    path="${4:-$(newest "$env")}"
    [ -n "$path" ] || die "no dumps for $env"

    log "restoring $env/$path into $db"
    file="$(fetch "$env" "$path")"
    restore_into "$db" "$file"
    rm -f "$file"
    log "done. Next: DEPLOYMENT.md, \"Restoring\""
    ;;

  *)
    die "usage: restore.sh list|drill|into ..."
    ;;
esac
