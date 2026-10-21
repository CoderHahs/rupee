# Deploying Rupee

Rupee runs on one small VM (2 vCPUs, 4 GB) on your tailnet (design §3.1,
option A). Members reach the whole app over Tailscale. The internet reaches
only Plaid's webhook, through Tailscale Funnel.

```text
tailnet ── tailscale serve  :443  ─┐
                                   ├─ Caddy 127.0.0.1:8080  the whole app ──┐
internet ─ tailscale funnel :8443 ─┘   Caddy 127.0.0.1:8081  RUPEE_PUBLIC_PATHS, else 404
                                                                            │
                         web, worker ── Postgres (Unix socket only), Redis ─┘
                         backup ─────── restic → bucket
```

Tailscale terminates TLS on the VM itself, so traffic is encrypted until it
reaches the VM's loopback interface. Rails keeps `force_ssl` and `assume_ssl`
on.

## Files

| File                | Purpose                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| `compose.yml`       | The stack. Nothing binds to a public interface                             |
| `Caddyfile`         | The tailnet listener and the public allowlist                              |
| `rupee.env.example` | Every variable the stack needs. Copy it to `rupee.env` (git-ignored)       |
| `backup.sh`         | restic backups, retention and checks (design §7.4)                         |
| `backup-cron.sh`    | Schedules `backup.sh` inside the `backup` service                          |
| `aws/`              | CloudFormation for the VM, encrypted volumes, KMS key and backup bucket    |

## First deploy

On AWS, first create the VM, its encrypted volumes and the backup bucket
with [`aws/`](aws/README.md).

1. Install Docker and Tailscale on the VM, then `sudo tailscale up`.
2. Copy this directory to the VM. Fill in `rupee.env` from
   `rupee.env.example` and `chmod 600 rupee.env`. Put the four keys marked
   `[password manager]` in your password manager too.
3. Initialize the backup repository once:
   `docker compose --env-file rupee.env run --rm --entrypoint sh backup -c "apk add --no-cache restic >/dev/null && sh /opt/rupee/backup.sh init"`
4. Start the stack: `docker compose --env-file rupee.env up -d`.
5. Publish the two listeners:
   - `sudo tailscale serve --bg --https=443 http://127.0.0.1:8080` (tailnet only)
   - `sudo tailscale funnel --bg --https=8443 http://127.0.0.1:8081` (public)
6. Check the allowlist from outside the tailnet:
   `curl -s -o /dev/null -w "%{http_code}" https://<APP_DOMAIN>:8443/accounts` should print 404.
7. Point Plaid's webhook at `https://<APP_DOMAIN>:8443/webhooks/plaid`.

## Backups

The `backup` service runs `backup.sh backup` at 03:30 UTC every night,
`check` on Sundays and `check-data` on the first of each month. Each run
logs to `docker compose logs backup`.

- The database is dumped with `pg_dump --format=custom` straight into restic,
  so no unencrypted dump is written to disk, and a failed dump leaves no
  snapshot.
- Active Storage is snapshotted from its volume.
- Retention keeps 7 daily, 4 weekly and 12 monthly snapshots.
- Redis is not backed up. It holds queues and caches only.

### Restore

On a scratch host with the same `rupee.env`, and restic installed with the
`RESTIC_*` and `AWS_*` variables from it exported:

1. Start only the database: `docker compose --env-file rupee.env up -d db`.
2. Restore it:
   `restic dump latest --tag database /rupee_production.dump | docker compose --env-file rupee.env exec -T db pg_restore --no-owner -U rupee -d rupee_production`
3. Restore Active Storage with `restic restore latest --tag storage --target <dir>`
   and copy `<dir>/storage` into the `app-storage` volume.
4. Start the rest and confirm the drill's three checks (design §7.4): the app
   boots, a Plaid access token decrypts, and account and entry counts match
   the source. Record the date in `FORK.md`.
