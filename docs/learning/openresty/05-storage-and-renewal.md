# Step 5: where certificates live, and renewing them

## What's in the `certs` volume

Everything OpenResty needs to keep across restarts is in one Docker
volume, mounted at `/var/lib/acme`:

```
/var/lib/acme/
  account.key            our ACME account (RSA 4096), made once by entrypoint.sh
  certs/                 lua-resty-acme's "file" storage, one file per entry
```

The file names in `certs/` are base64 of the entry's key. Decode them to
see what's there:

```sh
docker compose exec openresty sh -c \
  'cd /var/lib/acme/certs; for f in *; do echo "$(echo $f | base64 -d)"; done'
```

| Entry | What it is |
|---|---|
| `domain:ecc:<host>` | the certificate, its chain and its private key (JSON) |
| `failed_attempts:<host>` | how many orders for that name failed in a row (0 after a success) |
| `failure_lock:<host>` | "don't try that name again before …" after a failure |
| `update_lock:<host>` | "an order for that name is running" (stops two workers ordering at once) |
| `<token>#http-01` | the answer to a challenge while an order is running |

Each file holds `expiry::value` (0 = never expires). Expired entries are
ignored when read but stay on disk, so a failed order can leave a few
bytes behind. That's harmless.

### What survives what

| Event | Certificates | Notes |
|---|---|---|
| `openresty -s reload` | kept | config re-read; the same account key is loaded |
| `docker compose restart openresty` | kept | the in-memory caches start empty, so each worker's first handshake reads the file (and asks the app again) |
| image rebuild | kept | the volume isn't part of the image |
| `docker compose down` | kept | volumes are only removed with `down -v` |
| `docker compose down -v` / volume lost | **gone** | every name is ordered again on its next visit (see rate limits below) |

All tested locally: after a restart and after a rebuild, Pebble issued
nothing new.

**In production, back up this volume** with the database (Stage 11). Losing
it isn't fatal, but on a busy edge it means reissuing every certificate at
once, and Let's Encrypt allows **300 new orders per account per 3 hours**.

**One edge only.** File storage is local to the machine. With two or more
edge servers, they'd each order their own certificates; lua-resty-acme
also has Redis, Consul and Vault storage for sharing them. Not needed for
one VPS.

## Renewal

```
every ACME_RENEW_CHECK_SECONDS (6 h)           one worker per round, in turn
  for each stored certificate
    ask the app (the same gate as step 4)      no → skip it (don't renew, don't delete)
    less than ACME_RENEW_DAYS (30) left?       yes → order a new one, swap it in
```

- **The new certificate is used immediately**, with no restart: the
  handshake reads from storage when its cache misses, and the cache is
  updated as soon as the new certificate is stored.
- **Why 30 days.** Let's Encrypt advises renewing about two thirds of the
  way through a certificate's life. Today's certificates last 90 days (30
  days left = two thirds). They're getting shorter: **64 days from 10
  February 2027** and **45 days from 16 February 2028**. With 30 days left,
  a 45-day certificate is renewed after 15 days: earlier than needed, but
  never late. lua-resty-acme doesn't support ARI (the CA telling the client
  when to renew), so a fixed threshold is the way.
- **Domains the app stops approving** (removed, blocked, owner suspended)
  are skipped, not deleted, and quietly expire. Deleting is off on purpose:
  if the app were down during a renewal round, "delete what isn't
  approved" would delete everything.

### Watch a renewal happen

Renew anything with under 100 days left (so every 90-day certificate),
checking every 30 seconds:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername photos.adaobi.test </dev/null 2>/dev/null \
  | openssl x509 -noout -serial -startdate              # note the serial

ACME_RENEW_DAYS=100 ACME_RENEW_CHECK_SECONDS=30 docker compose up -d openresty
# wait a minute, run the openssl command again: new serial, new start date

docker compose up -d openresty                        # back to 30 days / 6 h
```

Leave it on for a while and you'll see why the check interval matters:
Pebble issues one certificate per round.

## When ordering fails

A customer's DNS might change after we verified it (they moved their site
away, or broke a record), so orders for their name start failing. Let's
Encrypt's limits that matter here:

| Limit | Value |
|---|---|
| Failed validations per name, per account | 5 per hour |
| Consecutive failures per name | 1,152, refilling 1 a day; past it the name is **paused** for a long time |
| New orders per account | 300 per 3 hours |
| Certificates per registered domain | 50 per 7 days (renewals of the same names don't count) |
| Duplicate certificates (exact same names) | 5 per 7 days |

lua-resty-acme's default is to retry every 5 minutes, which is 12 an hour.
Ours backs off (`failure_cooloff_callback` in `nginx.conf`): **15 minutes,
then 1 hour, then 6 hours, then once a day**. That's at most 2 failures
in the first hour, and never more than one a day after that, which is
exactly the pause limit's refill rate. A success resets the count.

Tested by stopping challtestsrv (so Pebble can't resolve anything) and
asking for `admin.localhost`: the first handshake's order failed,
`failed_attempts` became 1 with a lock for 899 seconds, and the next
handshake got the fallback without ordering.

Meanwhile the app re-checks DNS daily (Stage 8a) and marks a domain
`failed` after three bad checks, which closes the ask gate and stops the
attempts for good.

## Let's Encrypt staging vs production

| | Directory URL (`ACME_DIRECTORY_URL`) | Trusted by browsers | Limits |
|---|---|---|---|
| Pebble (local) | `https://pebble:14000/dir` | no | none |
| LE staging | `https://acme-staging-v02.api.letsencrypt.org/directory` | no | much higher |
| LE production | unset (lua-resty-acme's default) | yes | as above |

Use staging on the VPS first, until a customer domain gets a staging
certificate end to end; then switch to production and clear the staging
certificates (`rm -rf /var/lib/acme/certs/*`, keep `account.key`). The
same account key works for both; each CA simply registers it as its own
account.

## Two Pebble quirks (local only)

- **A new root every time Pebble starts**, and nothing remembered. After
  restarting Pebble, stored certificates no longer chain to its root: clear
  them (`rm -rf /var/lib/acme/certs/*` in the openresty container), restart
  OpenResty and fetch the root again.
- **A random profile for orders that don't name one.** lua-resty-acme
  never names one, and with Pebble's stock config some certificates came
  back 6-day `shortlived` ones, which a 30-day threshold renews every round.
  Our `deploy/pebble/pebble-config.json` keeps only a 90-day profile, so
  local behaves like Let's Encrypt (which uses its `classic` profile when
  none is named).

## Settings (openresty service)

| Variable | Default | |
|---|---|---|
| `ACME_RENEW_DAYS` | 30 | renew when fewer days than this are left |
| `ACME_RENEW_CHECK_SECONDS` | 21600 (6 h) | how often stored certificates are checked |
| `TLS_ASK_TIMEOUT_MS` | 2000 | how long to wait for the app's answer; compose sets 10000 locally, because the dev server checks your source for changes before every request (about 1–3 s on this machine). A release answers in milliseconds. |
