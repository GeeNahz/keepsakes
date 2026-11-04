#!/bin/bash
# One backup run. Everything is encrypted with age before it leaves the
# server, to AGE_RECIPIENT (a public key: this server can write backups but
# never read them; the private key stays offline with you).
#
# Into <remote>:<bucket>/<env>/daily/ (and weekly/ on Sundays, monthly/ on
# the 1st), keeping 7 daily, 4 weekly and 6 monthly runs:
#   <db>-<stamp>.dump.age          pg_dump of each database (BACKUP_DATABASES)
#   uploads-<stamp>.tar.gz.age     local-disk photos, when an environment uses them
# and into <bucket>/infra/ (same schedule):
#   certs-<stamp>.tar.gz.age       the edge's certificates and ACME account key
#
# Photos in R2 (MEDIA_BUCKETS) are copied, not archived, into
# <bucket>/<env>/media/: only additions, so a photo deleted by mistake can
# still be found there.
#
# Settings (compose.infra.yaml): BACKUP_DATABASES ("env=db ..."),
# MEDIA_BUCKETS ("env=bucket ..."), BACKUP_BUCKET, BACKUP_REMOTE,
# AGE_RECIPIENT, BACKUP_PING_URL; Postgres via PGHOST/PGUSER/PGPASSWORD.
set -euo pipefail

: "${AGE_RECIPIENT:?AGE_RECIPIENT is required}"
remote="${BACKUP_REMOTE:-r2}:${BACKUP_BUCKET:-keepsakes-backups}"
stamp="$(date -u +%Y-%m-%dT%H%MZ)"
keep_daily=7
keep_weekly=4
keep_monthly=6

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ping() {
  [ -n "${BACKUP_PING_URL:-}" ] || return 0
  curl -fsS -m 10 --retry 3 -o /dev/null "${BACKUP_PING_URL}$1" || true
}
trap 'ping /fail' ERR

log() { echo "backup: $*"; }

encrypt() { age -r "$AGE_RECIPIENT"; }

# Uploads one file to daily/ (and weekly/ and monthly/ when it's their day)
store() {
  local file="$1" prefix="$2"
  rclone copyto --s3-no-check-bucket "$file" "$remote/$prefix/daily/$(basename "$file")"
  if [ "$(date -u +%u)" = 7 ]; then
    rclone copyto --s3-no-check-bucket "$file" "$remote/$prefix/weekly/$(basename "$file")"
  fi
  if [ "$(date -u +%d)" = 01 ]; then
    rclone copyto --s3-no-check-bucket "$file" "$remote/$prefix/monthly/$(basename "$file")"
  fi
}

# Deletes all but the newest <keep> runs in a folder (a run = one stamp)
prune() {
  local dir="$1" keep="$2" old
  old="$(rclone lsf --files-only "$dir" 2>/dev/null |
    grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z' | sort -u | head -n "-$keep" || true)"
  for s in $old; do
    rclone delete "$dir" --include "*-$s.*"
  done
}

prefixes=()

for pair in ${BACKUP_DATABASES:-}; do
  env="${pair%%=*}"
  db="${pair#*=}"
  prefixes+=("$env")

  if ! psql -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1; then
    log "$env: no database $db yet, skipped"
    continue
  fi

  mkdir -p "$work/$env"
  log "$env: dumping $db"
  pg_dump -Fc -d "$db" | encrypt >"$work/$env/$db-$stamp.dump.age"
  store "$work/$env/$db-$stamp.dump.age" "$env"

  uploads="/backup/uploads/$env"
  if [ -d "$uploads" ] && [ -n "$(ls -A "$uploads" 2>/dev/null)" ]; then
    log "$env: archiving local-disk photos"
    tar -C "$uploads" -czf - . | encrypt >"$work/$env/uploads-$stamp.tar.gz.age"
    store "$work/$env/uploads-$stamp.tar.gz.age" "$env"
  fi
done

if [ -d /backup/certs ]; then
  log "infra: archiving certificates"
  mkdir -p "$work/infra"
  tar -C /backup/certs -czf - . | encrypt >"$work/infra/certs-$stamp.tar.gz.age"
  store "$work/infra/certs-$stamp.tar.gz.age" infra
  prefixes+=(infra)
fi

for pair in ${MEDIA_BUCKETS:-}; do
  env="${pair%%=*}"
  bucket="${pair#*=}"
  log "$env: copying new photos from $bucket"
  rclone copy --s3-no-check-bucket --fast-list "${BACKUP_REMOTE:-r2}:$bucket" "$remote/$env/media"
done

for prefix in "${prefixes[@]}"; do
  prune "$remote/$prefix/daily" "$keep_daily"
  prune "$remote/$prefix/weekly" "$keep_weekly"
  prune "$remote/$prefix/monthly" "$keep_monthly"
done

ping ""
log "done ($stamp)"
