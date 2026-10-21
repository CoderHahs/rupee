#!/bin/sh
# Entry point of the compose `backup` service: installs restic and the
# Postgres client, then runs backup.sh on the schedule in design §7.4.
set -eu

apk add --no-cache restic postgresql16-client >/dev/null

# crond starts jobs with an empty environment, so hand them the service's.
export -p | grep -E '^export (PG|POSTGRES_|RESTIC_|AWS_)' > /run/backup.env
chmod 600 /run/backup.env

run() { echo ". /run/backup.env && /bin/sh /opt/rupee/backup.sh $1 >> /proc/1/fd/1 2>&1"; }

cat > /etc/crontabs/root <<CRON
30 3 * * * $(run backup)
0 5 * * 0 $(run check)
0 6 1 * * $(run check-data)
CRON

exec crond -f -d 8
