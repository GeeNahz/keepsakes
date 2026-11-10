# Setting up and deploying Keepsake

Two parts:

1. **[Run it locally](#part-1-run-it-locally)**: the full stack in Docker
   (app, Postgres, the OpenResty edge, a local certificate authority).
2. **[Production](#part-2-production)**: one DigitalOcean droplet running
   production and staging, deployed by GitHub Actions. A start-to-finish
   runbook, then the everyday commands.

Background on how the edge works: `docs/learning/openresty/` (steps 1–7).
Third-party accounts (R2, Resend, Flutterwave, …): `docs/setup/accounts.md`.

---

## Part 1: run it locally

### What you need

- Docker with the compose plugin (`docker compose version`).
- For tests only: Erlang/Elixir from `.tool-versions` (asdf) and Postgres on
  `localhost:5432`. The app itself runs in Docker.

### First time

```sh
cp .env.example .env
```

Fill in what you need. Everything is optional locally except what a
feature needs to talk to the outside world:

| Variable | Needed for |
|---|---|
| `S3_*` | photos on R2. Empty = photos on local disk (`priv/uploads`) |
| `RESEND_API_KEY`, `MAIL_FROM_ADDRESS` | real email. Without `MAIL_DELIVERY=resend`, mail goes to `/dev/mailbox` |
| `FLW_*` | Flutterwave test-mode checkout |
| `TLS_ASK_TOKEN` | optional locally (see Part 2) |

`DB_*` in `.env` is for running Mix on your machine; compose overrides it
for the containers.

```sh
docker compose up -d --build                              # first build takes a while
docker compose exec app mix run priv/repo/seeds.exs       # dev account, sample album, test domain
```

The app container fetches deps and runs migrations every time it starts.

### Where things are

| URL | What |
|---|---|
| http://localhost:8088 | the site, through OpenResty (as in production) |
| http://admin.localhost:8088 | the admin portal |
| http://localhost:4100 | the app directly, skipping OpenResty |
| http://localhost:8088/dev/mailbox | emails sent in dev |
| https://photos.adaobi.test:8443 | a customer domain over HTTPS (see below) |

Sign in as `owner@keepsake.test` (password in `priv/repo/seeds.exs`). The
sample album's access code is `482917`. To make it staff:
`docker compose exec app mix keepsakes.staff.grant owner@keepsake.test --role super_admin`.

### Custom domains and HTTPS locally

The seeds add a verified customer domain, `photos.adaobi.test`. Its
certificate comes from **Pebble**, a local stand-in for Let's Encrypt,
the first time something connects:

```sh
docker compose exec -T openresty curl -sk https://pebble:15000/roots/0 > /tmp/pebble-root.pem
curl --resolve photos.adaobi.test:8443:127.0.0.1 --cacert /tmp/pebble-root.pem https://photos.adaobi.test:8443/
```

Pebble makes a new root each time it starts: fetch it again after a
restart. Browsers warn about Pebble certificates (correctly); use `curl`
for HTTPS, or the HTTP port in a browser. Names ending in `.localhost`
work in Chrome with no setup. Details: `docs/learning/openresty/04-*` and
`07-*`.

### Everyday commands

| Task | Command |
|---|---|
| status | `docker compose ps` |
| logs | `docker compose logs -f app openresty` |
| stop / start | `docker compose stop` / `docker compose up -d` |
| IEx with the app loaded | `docker compose exec app iex -S mix` *(a second copy of the app without the web server; fine for queries)* |
| a mix task | `docker compose exec app mix <task>` |
| psql | `docker compose exec db psql -U postgres keepsakes_dev` |
| check OpenResty config | `docker compose exec openresty openresty -t` |
| apply OpenResty config edits | `docker compose exec openresty openresty -s reload` |
| rebuild after Dockerfile changes | `docker compose up -d --build` |
| tests and checks (on your machine) | `mix precommit` |

Code edits reload on their own (your source is mounted into the app
container). Config files under `deploy/openresty/` are mounted too: reload
OpenResty after editing them. After changing a file under `config/`,
restart the app: `docker compose restart app`.

### Try the production image

```sh
docker compose exec db createdb -U postgres keepsakes_release   # once
docker compose --profile release up -d --build app_release
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4200/
docker compose --profile release stop app_release
```

It uses its own empty database, so your dev data is never touched.

### Resetting

| To reset | Do |
|---|---|
| the dev database | `docker compose exec app mix ecto.reset` (it re-runs the seeds) |
| certificates | `docker compose exec openresty sh -c 'rm -rf /var/lib/acme/certs/*'` then `docker compose restart pebble openresty` |
| everything (all data) | `docker compose down -v`, then "First time" again |

### When something's wrong

| Symptom | Look at |
|---|---|
| 502 from OpenResty | `docker compose logs app`: the app is still compiling or crashed |
| 500 "You must restart your server" | a file in `config/` changed: `docker compose restart app` |
| app restarts in a loop | `docker compose logs app`: usually a migration or a missing `.env` value |
| fallback certificate on a customer domain | `docker compose logs openresty \| grep "tls ask"`; is the domain `verified` in Admin › Domains? |
| "certificate is not yet valid" | the computer's clock was ahead when Pebble started: reset certificates (above) |
| ports 8088 / 8443 / 4100 already in use | another process holds them: `ss -ltnp \| grep <port>` |

More: `docs/learning/openresty/07-debugging-and-full-stack.md`.

---

## Part 2: production

### What runs on the server

```
                     ┌──────────────────── one droplet ───────────────────────┐
Internet ─► :80/:443 │ openresty ──► app-production (keepsakes_prod) ─┐       │
                     │  (edge)   └─► app-staging    (keepsakes_staging)┼─► postgres
                     │                                                 │       │
                     │ backup (nightly, encrypted) ────────────────────┘       │
                     │ [metrics profile, off by default:                       │
                     │  prometheus, grafana, uptime-kuma on 127.0.0.1]         │
                     └──────────────────────────────────────────────────────────┘
      photos: R2 (keepsakes-media, keepsakes-media-staging)
      backups: R2 (keepsakes-backups)   mail: Resend   payments: Flutterwave
```

- **Images** are built by GitHub Actions and pulled from GHCR, tagged
  with the commit (`ghcr.io/geenahz/keepsakes:<12-char sha>`, plus
  `keepsakes-edge` and `keepsakes-backup`).
- **Pushing `staging`** deploys staging. **Merging the `staging → master`
  PR** deploys production. Both run `mix precommit` first.
- **Deploys don't drop requests**: the new container starts next to the old
  one and takes over once it's healthy (`deploy/server/bin/deploy`). If it
  never gets healthy, it's removed and the old one carries on. (Rehearsed:
  0 of 851 requests dropped during a swap.) One caveat: the edge starts
  sending the new container a share of requests as soon as it accepts
  connections, before its health check passes. A version that starts but
  answers with errors therefore gets some traffic until it's removed,
  about 90 seconds at most. A version that crashes or won't start costs
  nothing, because the edge retries on the old one.
- **The files on the server** come from `deploy/server/` in the repo,
  copied there on every deploy. Secrets live only in the server's `.env`
  files.

| Where | What |
|---|---|
| `deploy/server/compose.infra.yaml` | edge, Postgres, backups, metrics profile (project `ks-infra`) |
| `deploy/server/compose.app.yaml` | one environment's app (projects `ks-production`, `ks-staging`) |
| `deploy/server/bin/` | `deploy`, `rollback`, `infra-up`, `backup`, `metrics`, `console` |
| `deploy/server/env/*.env.example` | the three `.env` files, with every value production needs |
| `deploy/openresty/`, `deploy/backup/` | the edge and backup images |
| `.github/workflows/ci.yml` | checks, images, deploys, image pruning |

### The runbook, in order

| # | Step | Where |
|---|---|---|
| 1 | [Create the droplet](#1-create-the-droplet) | DigitalOcean |
| 2 | [Harden it](#2-harden-it) | the droplet |
| 3 | [Install Docker](#3-install-docker) | the droplet |
| 4 | [DNS](#4-dns) | Namecheap |
| 5 | [Buckets and keys](#5-buckets-and-keys) | Cloudflare R2, your machine |
| 6 | [The settings files](#6-the-settings-files) | the droplet |
| 7 | [GitHub](#7-github) | GitHub |
| 8 | [First deploy: staging](#8-first-deploy-staging) | push `staging` |
| 9 | [Production, with test certificates first](#9-production-with-test-certificates-first) | PR `staging → master` |
| 10 | [Backups: check and drill](#10-backups-check-and-drill) | the droplet |
| 11 | [Monitoring](#11-monitoring) | UptimeRobot, healthchecks.io |
| 12 | [The checklist](#12-the-checklist) | |

#### 1. Create the droplet

- **Image:** Ubuntu 24.04 LTS. **Size:** 2 GB is the minimum for both
  environments; 4 GB if you'll use the metrics profile or expect heavy
  photo processing (libvips). Choose a region near your users.
- **Authentication:** your SSH key (add it under Settings › Security first),
  never a password.
- **Cloud Firewall** (Networking › Firewalls), attached to the droplet:
  inbound TCP 22, 80 and 443 only. Port 80 must stay open: Let's Encrypt
  checks every certificate over it, and the app redirects visitors to HTTPS.
- Turn on **Backups** in DigitalOcean too if you like (a whole-disk snapshot
  weekly, paid). The app's own backups (step 10) are what you restore from.

Note the droplet's public IPv4 (and IPv6, if enabled): they're the DNS
values and `EDGE_IPS`.

#### 2. Harden it

As root, once (`ssh root@<ip>`):

```sh
# A user for you and for deploys; root logins end after this step
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
passwd deploy        # for sudo only; SSH won't accept passwords

# SSH: keys only, no root
cat > /etc/ssh/sshd_config.d/10-keepsake.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
systemctl reload ssh

# Firewall (alongside the Cloud Firewall: either one alone would do)
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable

# Bans addresses that keep failing SSH logins; security updates on their own
apt-get update && apt-get install -y fail2ban unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
```

**Before closing the root session**, check from a new terminal that
`ssh deploy@<ip>` works and `sudo -v` accepts the password.

> Docker publishes ports by editing iptables itself, so ufw doesn't filter
> ports that containers publish. The compose files publish only 80 and 443
> publicly; everything else is on `127.0.0.1` or unpublished. The Cloud
> Firewall still blocks anything else at DigitalOcean's edge.

#### 3. Install Docker

As `deploy`:

```sh
curl -fsSL https://get.docker.com -o get-docker.sh
less get-docker.sh                      # read it first
sudo sh get-docker.sh
sudo usermod -aG docker deploy          # then log out and back in

# Containers' logs rotate (the compose files set this too; this covers anything else)
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "5" } }
EOF
sudo systemctl restart docker

sudo install -d -o deploy -g deploy /srv/keepsakes
docker compose version
```

#### 4. DNS

Namecheap › Domain List › Manage › **Advanced DNS**. Leave the existing
Resend records alone.

| Type | Host | Value |
|---|---|---|
| A | `@` | the droplet's IPv4 |
| A | `admin` | the droplet's IPv4 |
| A | `staging` | the droplet's IPv4 |
| A | `admin.staging` | the droplet's IPv4 (staging's admin portal) |
| A | `edge` | the droplet's IPv4 (customers' CNAME target) |
| AAAA | same hosts | the droplet's IPv6, only if it has one |

Customers later add `TXT _keepsake.<their domain>` and a CNAME to
`edge.<your domain>` (or A records to `EDGE_IPS` for a root domain); the
app shows them the exact values. Check with `dig +short admin.staging.<domain>`.

#### 5. Buckets and keys

**R2** (Cloudflare › R2; `docs/setup/accounts.md` has the walkthrough):

- Buckets: `keepsakes-media`, `keepsakes-media-staging`, `keepsakes-backups`.
- **The apps' tokens:** production's can read and write `keepsakes-media`;
  staging's can read and write `keepsakes-media-staging`.
- **The backup token:** read `keepsakes-media`, read and write
  `keepsakes-backups`.

**The backup key** (an [age](https://age-encryption.org) key pair), on
your own machine, not the server:

```sh
age-keygen -o keepsake-backups.key     # prints "Public key: age1..."
```

- The **public** key (`age1…`) goes in the server's `AGE_RECIPIENT`. It
  can encrypt backups, never read them.
- The **private** key file goes in your password manager, along with
  production's `CLOAK_KEY`. Without the private key the backups are
  unreadable. Without `CLOAK_KEY`, a restored database's access codes,
  two-step secrets and card tokens are unreadable. Neither stays on the
  server: a backup kept next to its key protects nothing.

#### 6. The settings files

On the droplet, as `deploy`. The templates arrive with the first deploy;
copy them by hand for now:

```sh
mkdir -p /srv/keepsakes/{infra,production,staging}
# from your machine, in the repo:
#   scp deploy/server/env/*.env.example deploy@<ip>:/srv/keepsakes/
cd /srv/keepsakes
cp infra.env.example infra/.env
cp production.env.example production/.env
cp staging.env.example staging/.env
chmod 600 */.env && rm *.env.example
```

Fill in every value; the comments say where each comes from. The ones to
get right:

| Value | Rule |
|---|---|
| `PRODUCTION_DB_PASSWORD`, `STAGING_DB_PASSWORD` (infra) | `openssl rand -hex 24`; copy each into that app's `DATABASE_URL` |
| `TLS_ASK_TOKEN` | one `openssl rand -hex 32`, the **same** in all three files |
| `SECRET_KEY_BASE`, `CLOAK_KEY` | **different** for production and staging (commands in `.env.example`) |
| `STAGING_HOSTS` (infra) | `staging.<domain> admin.staging.<domain>` |
| `ACME_DIRECTORY_URL` (infra) | Let's Encrypt **staging** at first (step 9) |
| `EDGE_IPS` | the droplet's IPs, comma-separated |
| `REQUIRE_STAFF_TWO_STEP` | `true` in both apps |
| `FLW_*` | live keys in production, test keys in staging |

#### 7. GitHub

**A deploy key** (only for Actions to log in as `deploy`), on your machine:

```sh
ssh-keygen -t ed25519 -N "" -C "github-actions-deploy" -f keepsake-deploy
ssh-copy-id -i keepsake-deploy.pub deploy@<ip>
ssh-keyscan -t ed25519 <ip>            # the host key line, for SSH_KNOWN_HOSTS
```

**Repository › Settings › Secrets and variables › Actions**, new secrets:

| Secret | Value |
|---|---|
| `SSH_HOST` | the droplet's IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | the contents of `keepsake-deploy` (the private half) |
| `SSH_KNOWN_HOSTS` | the `ssh-keyscan` line |

Then delete the private key file from your machine; it now lives only in
GitHub. Nothing else goes into GitHub: app settings stay on the server.

**Packages:** the first image push creates three private GHCR packages
(`keepsakes`, `keepsakes-edge`, `keepsakes-backup`). The deploy job logs
the server in with that job's own short-lived token, so the server never
stores a GitHub token.

**Limits on a free private repo:** 2,000 Actions minutes a month and
500 MB of package storage. The `prune` job keeps the newest ten versions
of each image. Branch protection needs GitHub Pro on a private repo, so
the production gate is the habit of merging `staging → master` only
through a PR whose checks passed. A public repo lifts all three limits.

#### 8. First deploy: staging

Push `staging`. Actions runs the checks, builds the images, copies
`deploy/server/` to `/srv/keepsakes/deploy/`, and runs
`bin/deploy staging <sha>`. That first run sees no shared services yet,
so it starts them too (`bin/infra-up`): the edge, Postgres (making
both databases and logins) and the backup job.

Then on the droplet:

```sh
cd /srv/keepsakes/deploy
docker compose -p ks-infra ls                 # or: docker ps
curl -s localhost/healthz -H "Host: staging.<domain>"     # ok (over HTTP; it redirects browsers to HTTPS)
bin/console staging logs                      # the app's log
```

Open `https://staging.<domain>`. With the Let's Encrypt staging CA the
browser warns about the certificate; that's expected for now. Sign up
with `SUPER_ADMIN_EMAIL`, then sign in at `https://admin.staging.<domain>`
and set up two-step login.

#### 9. Production, with test certificates first

1. Open a PR `staging → master`, wait for the checks, merge it. Actions
   runs `bin/infra-up` then `bin/deploy production`.
2. Check every name gets a certificate from the **staging** CA:

   ```sh
   for name in <domain> admin.<domain> staging.<domain> admin.staging.<domain>; do
     echo | openssl s_client -connect <ip>:443 -servername $name 2>/dev/null \
       | openssl x509 -noout -subject -issuer
   done
   ```

   The issuer should contain `(STAGING)`.
3. Switch to real certificates: on the droplet, empty `ACME_DIRECTORY_URL`
   in `infra/.env`, then

   ```sh
   cd /srv/keepsakes/deploy
   docker compose -p ks-infra exec openresty sh -c 'rm -rf /var/lib/acme/certs/* /var/lib/acme/account.key'
   bin/infra-up "$(cat ../infra/.deployed)"      # restarts the edge with the new setting
   ```

   Visit each name once and check the padlock. (The account key goes too:
   it was registered with the staging CA.)
4. Sign in to `https://admin.<domain>` and set up two-step login.

#### 10. Backups: check and drill

The `backup` service runs nightly at `BACKUP_AT` (02:30 UTC). It dumps
each database, archives the edge's certificates (and local-disk photos, if
any), encrypts everything to `AGE_RECIPIENT`, and uploads it to
`keepsakes-backups/<env>/daily/`. On Sundays it also writes `weekly/`, and
on the 1st `monthly/`. It keeps 7 daily, 4 weekly and 6 monthly. It also
copies new photos from `MEDIA_BUCKETS` into `keepsakes-backups/<env>/media/`.
That copy never deletes, so photos removed by mistake can still be found.

Right after the first deploy, and then **once a month**:

```sh
cd /srv/keepsakes/deploy
bin/backup now                                  # a backup right away
bin/backup list                                 # it's there
scp keepsake-backups.key deploy@<ip>:/tmp/      # from your machine: the PRIVATE key, briefly
bin/backup drill /tmp/keepsake-backups.key      # restore into a scratch DB, count rows, drop it
shred -u /tmp/keepsake-backups.key
```

The drill prints the row counts for users, albums, memories, invoices and
payments, and the latest migration. Compare them with Admin › Dashboard.

#### 11. Monitoring

| What | How | Cost |
|---|---|---|
| Is the site up? | **UptimeRobot**: HTTP(S) monitors on `https://<domain>/healthz` and `https://staging.<domain>/healthz`, 5-minute checks, email alerts. They work even when the whole droplet is down | free |
| Did last night's backup run? | **healthchecks.io**: a check with a 1-day period and a 2-hour grace; its ping URL is `BACKUP_PING_URL` in `infra/.env`. A failed run also pings `/fail` | free |
| Errors in the app | **Admin › Errors** (recorded by ErrorTracker): every crash with its stack trace and request context, grouped by where it happened. `errors.view` to look, `errors.manage` to resolve or mute; Super Admin has both | built in |
| Charts (BEAM, Phoenix, LiveView, Ecto, Oban) | the **metrics profile**, below | free, ~400–600 MB RAM while on |

**The metrics profile** is off unless you switch it on:

```sh
cd /srv/keepsakes/deploy
bin/metrics on          # Prometheus, Grafana, Uptime Kuma; stays on across deploys
bin/metrics status
bin/metrics off         # stops them; their data is kept for next time
```

They listen on the droplet's `127.0.0.1` only. To look, from your machine:

```sh
ssh -N -L 3000:127.0.0.1:3000 -L 3001:127.0.0.1:3001 deploy@<ip>
```

Then open http://localhost:3000 for Grafana (user `admin`, password
`GRAFANA_ADMIN_PASSWORD`; dashboards are in the Keepsake folder, with a
`job` picker for production or staging), and http://localhost:3001 for
Uptime Kuma (it asks you to create its admin on the first visit). The
apps always collect metrics (`METRICS_ENABLED=true`, port 4021, never
public), so switching on shows data from that moment.

After upgrading PromEx, regenerate the dashboards from the repo root, once
per dashboard:
`mix prom_ex.dashboard.export -m Keepsakes.PromEx -d beam.json --stdout`
into `deploy/server/monitoring/grafana/dashboards/beam.json`.

#### 12. The checklist

- [ ] `https://<domain>`, `https://admin.<domain>`, `https://staging.<domain>` and `https://admin.staging.<domain>` load with real certificates
- [ ] Admin requires two-step login (`REQUIRE_STAFF_TWO_STEP=true`) in both environments
- [ ] Turn on the `custom_domains` flag for the customers who should have it (Admin › Flags)
- [ ] A test customer domain verifies and gets its certificate
- [ ] A test upload lands in the right R2 bucket; a test email arrives
- [ ] Flutterwave webhooks point at `https://<domain>/webhooks/flutterwave` (live) and `https://staging.<domain>/webhooks/flutterwave` (test)
- [ ] `bin/backup drill` passed; the age private key and production's `CLOAK_KEY` are in your password manager, not on the server
- [ ] UptimeRobot and healthchecks.io alert you (pause the app briefly to see one)
- [ ] `docker ps` shows nothing published except 80 and 443 (and `127.0.0.1` ports while metrics are on)

### Everyday operations

On the droplet, in `/srv/keepsakes/deploy`:

| Task | Command |
|---|---|
| deploy (normally Actions does this) | `bin/deploy <production\|staging> <tag>` |
| go back one version | `bin/rollback <production\|staging>` |
| what's running | `cat ../production/.deployed ../staging/.deployed`; `docker ps` |
| IEx in the live app | `bin/console production` *(the real app and data: careful)* |
| an app's logs | `bin/console production logs` |
| the edge's logs | `docker compose -p ks-infra logs -f openresty` (or `docker logs -f ks-infra-openresty-1`) |
| psql | `docker compose -p ks-infra exec postgres psql -U postgres keepsakes_prod` |
| a backup now / the list / a drill | `bin/backup now` / `bin/backup list` / `bin/backup drill <key file>` |
| metrics on / off | `bin/metrics on` / `bin/metrics off` |
| a new setting in an app's `.env` | edit it, then redeploy the same tag: `bin/deploy production "$(cat ../production/.deployed)"` |
| a new setting in `infra/.env` | edit it, then `bin/infra-up "$(cat ../infra/.deployed)"` (restarts only what changed) |
| a change only this server needs (an extra volume, a port) | put it in `../infra/compose.override.yaml` (a compose file; the scripts add it when it exists), then `bin/infra-up` as above |

**Rollbacks** only change the code; database changes the newer version
made stay. Any tag from the last ten deploys can be deployed directly.

### Changing the database

During a deploy the old and the new version run side by side for a few
seconds, and the **new one runs its migrations while the old one is still
serving**. So a migration must work with the code that's already live:

- **Adding** a table, a column with a default, or a nullable column: fine.
- **Renaming or removing** something: in two deploys. First the code stops
  using it, then a later deploy removes it.
- **A slow migration** (an index on a big table, backfilling rows): use
  `create index(..., concurrently: true)` (with `@disable_ddl_transaction`
  and `@disable_migration_lock`), or batch the backfill in an Oban job.

When a change can't be made safe this way, take a short planned downtime:

```sh
docker compose -p ks-production stop app      # the edge answers 502 meanwhile
bin/deploy production <tag>                   # nothing running = a plain start
```

### Restoring

**A database** (into a new database, never over the live one):

```sh
scp keepsake-backups.key deploy@<ip>:/tmp/            # from your machine
bin/backup list production                            # pick a dump, or leave it out for the newest
bin/backup restore /tmp/keepsake-backups.key production keepsakes_prod_restored [daily/<file>]
shred -u /tmp/keepsake-backups.key

# Hand it to the app's login, then point the app at it
docker compose -p ks-infra exec postgres psql -U postgres -c \
  "ALTER DATABASE keepsakes_prod_restored OWNER TO keepsakes_prod"
docker compose -p ks-infra exec postgres psql -U postgres -d keepsakes_prod_restored -c \
  "REASSIGN OWNED BY postgres TO keepsakes_prod"
# production/.env: DATABASE_URL=.../keepsakes_prod_restored, then redeploy the same tag
```

`CLOAK_KEY` must be the one production had when the dump was made.

**Certificates:** usually not worth restoring; the edge asks for new ones
on the first visit to each name. After losing the `certs` volume, many
customer domains at once could hit Let's Encrypt's limits, so restore
`keepsakes-backups/infra/daily/certs-*.tar.gz.age`: decrypt it with
`age -d -i keepsake-backups.key`, then untar it into the volume.

**Photos:** they're in R2. Ones deleted by mistake are in
`keepsakes-backups/<env>/media/` under the same keys; copy them back with
`rclone` or the Cloudflare dashboard.

### Moving staging to its own server

The files are built so this needs no code changes:

1. Set up the new droplet with steps 1–3, 6 and 7's deploy key. Its
   `infra/.env` is the same as now except:
   - `STAGING_DB_PASSWORD` set and `PRODUCTION_DB_PASSWORD` **empty** (only
     staging's database is made)
   - `APP_UPSTREAM=app-staging:4000` and `STAGING_HOSTS` **empty** (every
     name on this server is staging's)
   - `BACKUP_DATABASES=staging=keepsakes_staging`, `MEDIA_BUCKETS` empty
     or `staging=keepsakes-media-staging`

   Copy `staging/.env` over unchanged.
2. In `.github/workflows/ci.yml`, let the deploy job pick its host per
   environment. For example, add secrets `SSH_HOST_STAGING` and
   `SSH_KNOWN_HOSTS_STAGING`, and choose them when `ENVIRONMENT` is
   staging. Push `staging`: the first deploy there starts its shared
   services, as in step 8.
3. Move the data: `bin/backup now` on the old server, then
   `bin/backup restore <key> staging keepsakes_staging_restored` on the new
   one, and switch to it as in "Restoring". Or start staging empty.
4. Point the `staging` and `admin.staging` DNS records at the new droplet.
5. On the old server: empty `STAGING_HOSTS` and `STAGING_DB_PASSWORD`, take
   `staging=...` out of `BACKUP_DATABASES`, run `bin/infra-up`, then
   `docker compose -p ks-staging down`. (Dropping the old
   `keepsakes_staging` database is up to you.)

The restore in step 3 reads the backup bucket, so the new server's backup
token needs read access to `keepsakes-backups/staging/`.

### Settings reference

Every variable is explained in `.env.example`; the server templates are in
`deploy/server/env/`. What differs from the local stack:

- No `pebble` or `challtestsrv`, and no Pebble root mounted on the edge.
- The edge publishes `80:80` and `443:443` and routes by
  `APP_UPSTREAM` (`app-production:4000`), `STAGING_HOSTS` and
  `STAGING_UPSTREAM` (`app-staging:4000`). Locally it defaults to the dev
  server, `app:4100`.
- The apps are release images from GHCR, not builds.
- `ACME_RENEW_DAYS`, `ACME_RENEW_CHECK_SECONDS`, `ACME_NEW_PER_MINUTE`,
  `ACME_NEW_PER_HOUR` and `TLS_ASK_TIMEOUT_MS` stay unset: their defaults
  are meant for production.

### When something's wrong

| Symptom | Look at |
|---|---|
| a deploy failed in Actions | the job log shows the new container's last 80 log lines; the old version is still serving |
| 502 from the edge | `docker ps`: is `ks-<env>-app-1` running and healthy? `bin/console <env> logs` |
| `no infra tag yet` | the shared services were never started: `bin/infra-up <tag>` |
| an app restarts in a loop | `bin/console <env> logs`: a migration, a missing `.env` value, or the wrong `DATABASE_URL` password |
| the fallback certificate (browser warning on a real name) | `docker compose -p ks-infra logs openresty \| grep -i "tls ask\|acme"`; is DNS pointing here (`dig`)? Is port 80 open? |
| staging's pages show production (or the reverse) | `STAGING_HOSTS` in `infra/.env`, then `bin/infra-up` |
| GHCR "denied" on pull | the deploy job's login step; for a manual pull, `docker login ghcr.io` with a token that has `read:packages` |
| the disk fills up | `docker system df`; old images are pruned after each deploy (`docker image prune`) |
