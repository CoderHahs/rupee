#!/bin/sh
# Rupee's encrypted backups (design §7.4). Runs in the compose `backup`
# service, which provides PGHOST, POSTGRES_*, RESTIC_REPOSITORY,
# RESTIC_PASSWORD and the bucket credentials.
#
#   backup.sh backup      dump the database, snapshot Active Storage, prune
#   backup.sh check       verify the repository's structure (weekly)
#   backup.sh check-data  also read back a sample of the data (monthly)
#   backup.sh init        create the repository, once
#
# Redis is not backed up: it holds queues and caches, and the fork's cron
# jobs are reloaded from config/fork_schedule.yml at boot.
set -eu

export PGPASSWORD="${POSTGRES_PASSWORD}"

log() { echo "[backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

case "${1:-}" in
  init)
    restic init
    ;;
  backup)
    log "dumping ${POSTGRES_DB}"
    # The dump streams into restic, so no unencrypted copy touches the disk,
    # and restic keeps no snapshot if pg_dump fails.
    restic backup --tag database --stdin-filename "${POSTGRES_DB}.dump" --stdin-from-command -- \
      pg_dump --format=custom --no-owner --dbname="${POSTGRES_DB}" --username="${POSTGRES_USER}"
    log "snapshotting Active Storage"
    restic backup --tag storage /storage
    log "applying retention"
    restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 12
    log "done"
    ;;
  check)
    restic check
    ;;
  check-data)
    restic check --read-data-subset=1/12
    ;;
  *)
    echo "usage: $0 init|backup|check|check-data" >&2
    exit 64
    ;;
esac
