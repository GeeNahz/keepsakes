# Setting up and deploying Keepsake

Two parts:

1. **[Run it locally](#part-1-run-it-locally)**: the full stack in Docker
   (app, Postgres, the OpenResty edge, a local certificate authority).
   Complete and working.
2. **[Production](#part-2-production)**: what goes on the server. The
   pieces built so far (the release image, the edge, the settings) are
   described here with exact values. Stage 11 adds the production compose
   file, CI/CD and backups, and finishes this part into a start-to-finish
   runbook.

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
OpenResty after editing them.

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
| app restarts in a loop | `docker compose logs app`: usually a migration or a missing `.env` value |
| fallback certificate on a customer domain | `docker compose logs openresty \| grep "tls ask"`; is the domain `verified` in Admin › Domains? |
| "certificate is not yet valid" | the computer's clock was ahead when Pebble started: reset certificates (above) |
| ports 8088 / 8443 / 4100 already in use | another process holds them: `ss -ltnp \| grep <port>` |

More: `docs/learning/openresty/07-debugging-and-full-stack.md`.

---

## Part 2: production

### What runs on the server

```
Internet ──► OpenResty :80/:443 ──► app (release, :4000) ──► Postgres
             (certificates from        │
              Let's Encrypt,           └──► R2 (photos), Resend (mail),
              stored in `certs`)            Flutterwave (payments)
```

One DigitalOcean droplet runs all of it with Docker compose. The app image
is built by CI from `Dockerfile` and pulled from GHCR (Stage 11).

### Status

| Piece | Ready? |
|---|---|
| Release image (`Dockerfile`, migrations on boot) | ✓ built and tested locally |
| Edge config (`deploy/openresty/`): proxy, WebSockets, on-demand certificates, rate limits | ✓ same files in production |
| App: custom domains, `/internal/tls/ask`, real client IPs | ✓ |
| Accounts (R2, Resend, Flutterwave, Namecheap DNS) | ✓ see `docs/setup/accounts.md` |
| Production compose file, the droplet runbook, GitHub Actions, GHCR | Stage 11 |
| Backups (database, photos, `certs` volume), monitoring | Stage 11 |

### DNS (Namecheap → Advanced DNS)

| Record | Host | Value |
|---|---|---|
| A | `@` | the droplet's IPv4 |
| A | `admin` | the droplet's IPv4 |
| A | `staging` | the droplet's IPv4 |
| A | `edge` | the droplet's IPv4 (customers' CNAME target) |

Leave the existing Resend records alone. Customers then add
`TXT _keepsake.<their domain>` plus a CNAME to `edge.<your domain>` (or A
records to `EDGE_IPS` for a root domain); the app shows them the exact
values.

### Firewall

Open 22, 80 and 443 only, in both ufw and the DigitalOcean Cloud Firewall.
Port 80 must stay open: Let's Encrypt validates every certificate over it.

### Settings: the server's `.env`

Kept at `chmod 600`, never committed. Every variable is documented in
`.env.example`.

**App:**

| Variable | Production value |
|---|---|
| `DATABASE_URL` | `ecto://USER:PASS@postgres/keepsakes_prod` |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` |
| `CLOAK_KEY` | 32 random bytes, base64 (command in `.env.example`). **Never change it once data exists.** Back it up somewhere safe: without it, encrypted columns are unreadable |
| `PHX_HOST` | your domain, e.g. `keepsake.com` |
| `ADMIN_HOST` | leave unset (= `admin.<PHX_HOST>`) |
| `REQUIRE_STAFF_TWO_STEP` | `true` |
| `SUPER_ADMIN_EMAIL` | your account's email |
| `EDGE_HOST` | leave unset (= `edge.<PHX_HOST>`) |
| `EDGE_IPS` | the droplet's public IPs, comma-separated |
| `TLS_ASK_TOKEN` | `openssl rand -hex 32` (the edge sends the same value) |
| `S3_*` | the production R2 bucket |
| `RESEND_API_KEY`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME`, `SUPPORT_INBOX` | Resend |
| `FLW_*` | Flutterwave **live** keys (test keys on staging) |

**Edge (the `openresty` service):**

| Variable | Production value |
|---|---|
| `ACME_DIRECTORY_URL` | first Let's Encrypt staging: `https://acme-staging-v02.api.letsencrypt.org/directory`; then unset |
| `ACME_EMAIL` | an address you read (expiry and policy notices) |
| `TLS_ASK_TOKEN` | the same value as the app's |
| `ACME_RENEW_DAYS`, `ACME_RENEW_CHECK_SECONDS`, `ACME_NEW_PER_MINUTE`, `ACME_NEW_PER_HOUR`, `TLS_ASK_TIMEOUT_MS` | leave unset (the defaults are meant for production) |

**What differs from the local compose file:**

- No `pebble` or `challtestsrv` services, and no Pebble root mount on
  `openresty`.
- OpenResty publishes `80:80` and `443:443`.
- The upstream in `conf.d/keepsake.conf` points at the release container
  (port 4000) instead of the dev server (4100).
- The app service uses the GHCR image, not a build.

### Going live with certificates

1. Deploy with `ACME_DIRECTORY_URL` set to Let's Encrypt **staging**.
2. Check the main domain, `admin.` and one test customer domain:
   `openssl s_client -connect <ip>:443 -servername <name> </dev/null | openssl x509 -noout -issuer`.
   The issuer should contain `(STAGING)`. Browsers warn; that's expected.
3. Unset `ACME_DIRECTORY_URL`, empty the `certs` volume (account key
   included), and restart `openresty`. Visit each name once.
4. Check the padlock in a browser.

### After deploying

- [ ] `https://<domain>` and `https://admin.<domain>` load with valid certificates
- [ ] Sign in to admin; two-step login is required
- [ ] Turn on the `custom_domains` flag for the customers who should have it (Admin › Flags)
- [ ] A test customer domain verifies and gets its certificate
- [ ] A test upload lands in R2; a test email arrives
- [ ] Flutterwave webhook URL points at `https://<domain>/webhooks/flutterwave`
- [ ] Backups of the database, the `certs` volume and `CLOAK_KEY` are in place (Stage 11)
