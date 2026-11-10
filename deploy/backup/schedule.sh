#!/bin/bash
# Runs backup.sh once a day at BACKUP_AT (HH:MM, UTC), forever. A failed
# backup is logged (and reported to BACKUP_PING_URL) and tried again the
# next day; the container keeps running.
set -uo pipefail

at="${BACKUP_AT:-02:30}"
[[ "$at" =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || { echo "BACKUP_AT must be HH:MM (got $at)" >&2; exit 1; }

echo "backups: daily at $at UTC"
while true; do
  now="$(date -u +%s)"
  next="$(date -u -d "today $at" +%s)"
  [ "$next" -gt "$now" ] || next="$(date -u -d "tomorrow $at" +%s)"
  echo "backups: next run $(date -u -d "@$next" '+%Y-%m-%d %H:%M') UTC"
  sleep "$((next - now))"

  if ! backup.sh; then
    echo "backups: FAILED, see above; trying again tomorrow" >&2
  fi
done
