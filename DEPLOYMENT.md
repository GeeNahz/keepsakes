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
| 13 | [SSH: keys only](#13-ssh-keys-only) | the droplet |

Throughout, `<you>` is your user on the droplet (the one you sign in and
deploy as), `<ip>` its IPv4, and `<domain>` the name the app lives on. It
can be a subdomain: production on `keepsakes.example.com` puts the admin
portal on `admin.keepsakes.example.com`, staging on
`staging.keepsakes.example.com`, and so on. Everything follows `PHX_HOST`.

#### 1. Create the droplet

- **Image:** Ubuntu 24.04 LTS. **Size:** 2 GB is the minimum for both
  environments (1 GB doesn't fit both apps, Postgres and a deploy's
  overlap); 4 GB if you'll use the metrics profile or expect heavy photo
  processing (libvips). Choose a region near your users (London for
  Nigeria). Tick **IPv6** and the free **monitoring agent**.
- A droplet can be resized later: power it off, Resize › **CPU and RAM
  only** (keeps the disk, so you can size back down), power on. The IPs
  stay the same.
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

**Your user.** One user with sudo, for you and for deploys (CI signs in
as it with its own key, step 7). If you don't have one yet, as root:

```sh
adduser <you>                    # sets its password (used by sudo)
usermod -aG sudo <you>
install -d -m 700 -o <you> -g <you> /home/<you>/.ssh
cp /root/.ssh/authorized_keys /home/<you>/.ssh/ && chown <you>:<you> /home/<you>/.ssh/authorized_keys
```

Then, as `<you>` (`sudo -v && groups` should list `sudo`). Keep this
session open while you check from a second one:

```sh
# Firewall (alongside the Cloud Firewall: either one alone would do).
# SSH is allowed BEFORE enabling, so the session stays connected
sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw --force enable && sudo ufw status verbose

# Bans addresses that keep failing SSH logins; security updates on their own
sudo apt-get update && sudo apt-get -y upgrade
sudo apt-get install -y fail2ban unattended-upgrades
sudo dpkg-reconfigure -f noninteractive unattended-upgrades
sudo systemctl enable --now fail2ban && sudo fail2ban-client status sshd
```

If `apt-get upgrade` asks about a changed config file, keep the local
version. Updates never reboot by themselves: when a login says "System
restart required", `sudo reboot` at a quiet moment (the containers come
back on their own). Switching SSH to keys only is
[step 13](#13-ssh-keys-only), once everything works.

> Docker publishes ports by editing iptables itself, so ufw doesn't filter
> ports that containers publish. The compose files publish only 80 and 443
> publicly; everything else is on `127.0.0.1` or unpublished. The Cloud
> Firewall still blocks anything else at DigitalOcean's edge.

#### 3. Install Docker

As `<you>`:

```sh
curl -fsSL https://get.docker.com -o get-docker.sh
less get-docker.sh                      # read it first
sudo sh get-docker.sh && rm get-docker.sh
sudo usermod -aG docker $USER           # then log out and back in (the docker group is root-equivalent)

# Containers' logs rotate (the compose files set this too; this covers anything else)
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "5" } }
EOF
sudo systemctl restart docker

# /srv/keepsakes, owned by you, so deploys never need sudo
sudo install -d -o $USER -g $USER /srv/keepsakes
docker version --format '{{.Server.Version}}' && docker compose version
docker info --format '{{.LoggingDriver}}'    # json-file
```

#### 4. DNS

Namecheap › Domain List › Manage › **Advanced DNS**. Leave the existing
Resend records alone. Five names, all pointing at the same droplet: the
edge routes each by the name visitors asked for (`STAGING_HOSTS`).

| Type | Host (app on the root domain) | Host (app on `keepsakes.<root>`) | Value |
|---|---|---|---|
| A | `@` | `keepsakes` | the droplet's IPv4 |
| A | `admin` | `admin.keepsakes` | the droplet's IPv4 |
| A | `staging` | `staging.keepsakes` | the droplet's IPv4 |
| A | `admin.staging` | `admin.staging.keepsakes` | the droplet's IPv4 (staging's admin portal) |
| A | `edge` | `edge.keepsakes` | the droplet's IPv4 (customers' CNAME target) |
| AAAA | same hosts | same hosts | the droplet's IPv6, only if it has one |

No wildcard (`*`) record: names the app doesn't know would get
certificate errors. On the root domain, remove Namecheap's parking
records (`CNAME www` → parkingpage, a URL redirect on `@`); `www` isn't
served.

Customers later add `TXT _keepsake.<their domain>` and a CNAME to
`edge.<your domain>` (or A records to `EDGE_IPS` for a root domain); the
app shows them the exact values. Check with `dig +short admin.staging.<domain>`.

#### 5. Buckets and keys

**R2** (Cloudflare › R2; `docs/setup/accounts.md` has the walkthrough):

- Buckets: `keepsakes-media`, `keepsakes-media-staging`, `keepsakes-backups`
  (location hint near the droplet, e.g. Western Europe; no jurisdiction;
  public access off).
- Three tokens (R2 › Manage API tokens), each **Object Read & Write**
  and limited to specific buckets. A token has one permission level for
  all its buckets.

  | Token | Buckets | Goes in |
  |---|---|---|
  | `keepsakes-production` | `keepsakes-media` | production `.env` |
  | `keepsakes-staging` | `keepsakes-media-staging` | staging `.env` |
  | `keepsakes-backup` | `keepsakes-media`, `keepsakes-backups` | infra `.env` |

  Never give an app's token the backup bucket, or use it for backups: a
  compromised app could then delete the backups meant to rescue it. Each
  token's Access Key ID (32 characters) and Secret (64) are shown once;
  check which pair is which before pasting.

**Email:** the from-address (`MAIL_FROM_ADDRESS`) must be on a domain
Resend has verified. Resend verifies each domain and subdomain on its own,
so an app on `keepsakes.<root>` either sends from `@<root>` (already
verified) or verifies `keepsakes.<root>` in Resend too.

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
- Run `age-keygen` **once**. Check the saved private key belongs to the
  public key you use: `age-keygen -y keepsake-backups.key` prints it.
  Then `shred -u keepsake-backups.key`.

#### 6. The settings files

On the droplet, as `<you>`. The templates arrive with the first deploy;
copy them by hand for now:

```sh
mkdir -p /srv/keepsakes/{infra,production,staging}
# from your machine, in the repo:
#   scp deploy/server/env/*.env.example <you>@<ip>:/srv/keepsakes/
cd /srv/keepsakes
cp infra.env.example infra/.env
cp production.env.example production/.env
cp staging.env.example staging/.env
chmod 600 */.env && rm *.env.example
```

Generate the secrets once, so the values that must match do (paste each
line into its file, then `clear`):

```sh
PROD_DB=$(openssl rand -hex 24); STG_DB=$(openssl rand -hex 24); ASK=$(openssl rand -hex 32)
echo "--- infra/.env"
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
echo "PRODUCTION_DB_PASSWORD=$PROD_DB"
echo "STAGING_DB_PASSWORD=$STG_DB"
echo "TLS_ASK_TOKEN=$ASK"
for env in production staging; do
  db=$([ $env = production ] && echo "keepsakes_prod:$PROD_DB@postgres/keepsakes_prod" \
                             || echo "keepsakes_staging:$STG_DB@postgres/keepsakes_staging")
  echo "--- $env/.env"
  echo "DATABASE_URL=ecto://$db"
  echo "SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')"
  echo "CLOAK_KEY=$(openssl rand -base64 32)"
  echo "TLS_ASK_TOKEN=$ASK"
done
```

Fill in every other value; the comments say where each comes from. Both
database passwords must be set **before the first deploy**: Postgres
creates both databases the first time it starts. The ones to get right:

| Value | Rule |
|---|---|
| `PRODUCTION_DB_PASSWORD`, `STAGING_DB_PASSWORD` (infra) | `openssl rand -hex 24`; copy each into that app's `DATABASE_URL` |
| `TLS_ASK_TOKEN` | one `openssl rand -hex 32`, the **same** in all three files |
| `SECRET_KEY_BASE`, `CLOAK_KEY` | **different** for production and staging (commands in `.env.example`) |
| `STAGING_HOSTS` (infra) | `staging.<domain> admin.staging.<domain>` |
| `ACME_DIRECTORY_URL` (infra) | Let's Encrypt **staging** at first (step 9) |
| `EDGE_IPS` | the droplet's IPs, comma-separated |
| `REQUIRE_STAFF_TWO_STEP` | `true` in both apps |
| `SUPER_ADMIN_EMAIL` | the email you'll sign up with; that account becomes Super Admin |
| `FLW_*` | live keys in production, test keys in staging; each its own `FLW_SECRET_HASH`, also set in Flutterwave's webhook settings for that mode |
| `PG_SHARED_BUFFERS` etc. (infra) | the defaults suit 2 GB; the comment has 4 GB values |

Check it, printing no secrets (names of empty settings, fingerprints of
values that must match, and verdicts):

```sh
cd /srv/keepsakes
for f in infra/.env production/.env staging/.env; do
  echo "== $f"; grep -nE '^[A-Z_]+=$|CHANGE_ME|ACCOUNT_ID|example\.com' "$f" | cut -d= -f1
done
for f in infra/.env production/.env staging/.env; do   # three equal fingerprints, not e3b0c442 (empty)
  printf '%-16s ask-token %s\n' "$f" "$(grep '^TLS_ASK_TOKEN=' "$f" | cut -d= -f2- | sha256sum | cut -c1-8)"
done
p=$(grep '^PRODUCTION_DB_PASSWORD=' infra/.env | cut -d= -f2-); grep -q ":$p@" production/.env && echo "production db password: match"
s=$(grep '^STAGING_DB_PASSWORD=' infra/.env | cut -d= -f2-); grep -q ":$s@" staging/.env && echo "staging db password: match"
for k in SECRET_KEY_BASE CLOAK_KEY FLW_SECRET_HASH S3_ACCESS_KEY_ID; do
  a=$(grep "^$k=" production/.env | sha256sum)
  b=$(grep "^$k=" staging/.env | sha256sum)
  if [ "$a" != "$b" ]; then echo "$k: different (good)"; else echo "$k: SAME, fix this"; fi
done
fp() { grep "^$2=" "$1" | cut -d= -f2- | sha256sum | cut -c1-8; }
[ "$(fp infra/.env BACKUP_S3_ACCESS_KEY_ID)" != "$(fp production/.env S3_ACCESS_KEY_ID)" ] \
  && echo "backup token: its own (good)" || echo "backup token: SAME as production's, fix this"
```

#### 7. GitHub

**A deploy key** (only for Actions to log in as `<you>`), on your machine:

```sh
ssh-keygen -t ed25519 -N "" -C "github-actions-deploy" -f keepsake-deploy
ssh-copy-id -i keepsake-deploy.pub <you>@<ip>
ssh-keyscan -t ed25519 <ip>            # the host key line, for SSH_KNOWN_HOSTS
```

To be sure the `ssh-keyscan` answer came from your droplet, compare
`ssh-keygen -lf <(ssh-keyscan -t ed25519 <ip> 2>/dev/null)` on your
machine with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the
droplet: the `SHA256:` fingerprints must match.

**Repository › Settings › Secrets and variables › Actions**, new secrets:

| Secret | Value |
|---|---|
| `SSH_HOST` | the droplet's IP |
| `SSH_USER` | `<you>` |
| `SSH_KEY` | the contents of `keepsake-deploy` (the private half, BEGIN/END lines included) |
| `SSH_KNOWN_HOSTS` | the `ssh-keyscan` line |

Then `shred -u keepsake-deploy`; the private key now lives only in
GitHub. If it's ever exposed, delete its line from the droplet's
`~/.ssh/authorized_keys` and make a new one. Nothing else goes into
GitHub: app settings stay on the server. (A run pushed before these
secrets existed fails at "Copy the server files" with `no argument after
keyword "hostname"`; once they're set, **Re-run failed jobs** on it.)

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
docker ps --format 'table {{.Names}}\t{{.Status}}'   # app and postgres (healthy)
curl -sk -o /dev/null -w '%{http_code}\n' \
  --resolve staging.<domain>:443:127.0.0.1 https://staging.<domain>/healthz   # 200
bin/console staging logs                      # the app's log
```

(`-k` accepts the Let's Encrypt **test** certificate, which browsers
don't trust; leave the browser until real certificates in step 9.)

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
   in `infra/.env` (empty means Let's Encrypt), then

   ```sh
   cd /srv/keepsakes/deploy
   docker exec ks-infra-openresty-1 sh -c 'rm -rf /var/lib/acme/certs/* /var/lib/acme/account.key'
   bin/infra-up "$(cat ../infra/.deployed)"      # restarts the edge with the new setting
   ```

   The account key goes too: it was registered with the staging CA, and
   the edge makes a new one on start. Then, from your machine (no `-k`: curl
   only succeeds with a trusted certificate; the first request for a name
   waits while it's issued):

   ```sh
   for name in <domain> admin.<domain> staging.<domain> admin.staging.<domain>; do
     for try in 1 2 3; do curl -s -o /dev/null https://$name/healthz && break; sleep 5; done
     printf '%-40s ' $name
     echo | openssl s_client -connect <ip>:443 -servername $name 2>/dev/null | openssl x509 -noout -issuer
   done
   ```

   Each issuer is `O=Let's Encrypt` without `(STAGING)`. `CN=keepsake-fallback`
   means issuance failed: `docker logs --since 5m ks-infra-openresty-1 2>&1 | grep -iE 'acme|error'`.
   A browser that showed you the test certificate earlier may keep saying
   "Not secure" until it's restarted.
4. Open `https://<domain>`, sign up with `SUPER_ADMIN_EMAIL`, confirm the
   email, then sign in at `https://admin.<domain>` and set up two-step
   login (keep the backup codes in your password manager). Same on
   staging, which is a separate database.

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
scp keepsake-backups.key <you>@<ip>:/tmp/       # from your machine: the PRIVATE key, briefly (then shred your copy)
bin/backup drill /tmp/keepsake-backups.key      # restore into a scratch DB, count rows, drop it
shred -u /tmp/keepsake-backups.key
```

When it goes wrong:

| Message | Meaning |
|---|---|
| `403 Forbidden` / `AccessDenied` from rclone | the backup token doesn't cover that bucket, or `infra/.env` holds another token's keys. Test: `docker exec ks-infra-backup-1 rclone lsf --max-depth 1 r2:keepsakes-backups` |
| `age: no identity matched any of the recipients` | the private key isn't the partner of `AGE_RECIPIENT` (`age-keygen -y` on it shows its public key). Make a new pair, update `AGE_RECIPIENT`, `bin/infra-up …`, `bin/backup now` |

After changing `infra/.env`, `bin/infra-up "$(cat ../infra/.deployed)"`
recreates the backup container so it reads the new values. **Never run
rclone with `-v`/`-vv` on the server**: it logs the keys it reads from the
environment.

The drill prints the row counts for users, albums, memories, invoices and
payments, and the latest migration. Compare them with Admin › Dashboard.

#### 11. Monitoring

| What | How | Cost |
|---|---|---|
| Is the site up? | **UptimeRobot**: HTTP(S) monitors on `https://<domain>/healthz` and `https://staging.<domain>/healthz`, 5-minute checks, email alerts. They work even when the whole droplet is down | free |
| Did last night's backup run? | **healthchecks.io**: a check on the cron schedule `30 2 * * *` (UTC, matching `BACKUP_AT`) with a 2-hour grace; its ping URL is `BACKUP_PING_URL` in `infra/.env` (then `bin/infra-up …` and `bin/backup now` for the first ping). A failed run also pings `/fail`. The free plan's 20 checks are monitored jobs, not pings; this uses one | free |
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
ssh -N -L 3000:127.0.0.1:3000 -L 3001:127.0.0.1:3001 <you>@<ip>
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
- [ ] `bin/backup now` shows no `ERROR` lines
- [ ] SSH accepts keys only (step 13)

#### 13. SSH: keys only

Last, once deploys and your own key logins work. On the droplet, with
one session kept open until the checks pass:

```sh
sudo tee /etc/ssh/sshd_config.d/10-keepsake.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication) '   # all "no"
```

SSH uses the **first** value it reads for a setting, in file-name order,
so `10-` comes before DigitalOcean's `50-cloud-init.conf` (which may turn
passwords on). `sshd -t` tests the file before the reload. From your
machine:

```sh
ssh <you>@<ip> 'echo ok'                                  # ok
ssh root@<ip> 'echo should-fail'                          # refused
ssh -o PubkeyAuthentication=no <you>@<ip> 'echo no'       # refused, no password prompt
```

If the first fails, use the open session:
`sudo rm /etc/ssh/sshd_config.d/10-keepsake.conf && sudo systemctl reload ssh`.
Your password still works for `sudo`. CI's deploy key is unaffected.

### Everyday operations

On the droplet, in `/srv/keepsakes/deploy`:

| Task | Command |
|---|---|
| deploy (normally Actions does this) | `bin/deploy <production\|staging> <tag>` |
| go back one version | `bin/rollback <production\|staging>` |
| what's running | `cat ../production/.deployed ../staging/.deployed`; `docker ps` |
| IEx in the live app | `bin/console production` *(the real app and data: careful)* |
| an app's logs | `bin/console production logs` |
| the edge's logs | `docker logs -f ks-infra-openresty-1` |
| psql | `docker exec -it ks-infra-postgres-1 psql -U postgres keepsakes_prod` |
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
scp keepsake-backups.key <you>@<ip>:/tmp/             # from your machine
bin/backup list production                            # pick a dump, or leave it out for the newest
bin/backup restore /tmp/keepsake-backups.key production keepsakes_prod_restored [daily/<file>]
shred -u /tmp/keepsake-backups.key

# Hand it to the app's login, then point the app at it
docker exec ks-infra-postgres-1 psql -U postgres -c \
  "ALTER DATABASE keepsakes_prod_restored OWNER TO keepsakes_prod"
docker exec ks-infra-postgres-1 psql -U postgres -d keepsakes_prod_restored -c \
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
| the fallback certificate (browser warning on a real name) | `docker logs ks-infra-openresty-1 2>&1 \| grep -i "tls ask\|acme"`; is DNS pointing here (`dig`)? Is port 80 open? (`bad uri:` in the log meant an empty `ACME_DIRECTORY_URL` before 0.1.0) |
| staging's pages show production (or the reverse) | `STAGING_HOSTS` in `infra/.env`, then `bin/infra-up` |
| GHCR "denied" on pull | the deploy job's login step; for a manual pull, `docker login ghcr.io` with a token that has `read:packages` |
| the disk fills up | `docker system df`; old images are pruned after each deploy (`docker image prune`) |
