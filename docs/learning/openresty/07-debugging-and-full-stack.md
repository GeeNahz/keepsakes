# Step 7: debugging, the release image, and going to production

## Debugging the edge

Three tools answer almost every question about the edge.

### Which certificate is served? `openssl s_client`

```sh
openssl s_client -connect 127.0.0.1:8443 -servername photos.adaobi.test </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

- `-servername` sets the SNI name. Leave it out and you're asking for "no
  name", which always gets the fallback.
- `-subject` is empty on Let's Encrypt and Pebble certificates; the name is
  in `subjectAltName`.
- `CN = keepsake-fallback` means OpenResty had no real certificate for the
  name: the app said no, the order failed, or the new-certificate cap held
  it back. The log says which.
- In production: `openssl s_client -connect <server-ip>:443 -servername <domain>`.

### Talk to the edge as if DNS pointed here: `curl --resolve`

```sh
curl --resolve photos.adaobi.test:8443:127.0.0.1 --cacert /tmp/pebble-root.pem \
     -sS -o /dev/null -w "%{http_code} verify=%{ssl_verify_result} %{time_total}s\n" \
     https://photos.adaobi.test:8443/
```

`--resolve name:port:ip` skips DNS for that one name, so the request carries
the right SNI and `Host` without editing `/etc/hosts`. In production it lets
you test a customer's domain before they change their DNS:
`curl --resolve their.domain:443:<server-ip> https://their.domain/`.
(Without `--cacert`, use `-k` to skip verification; the chain then isn't
checked at all.)

For HTTP only, a `Host` header is enough:
`curl -H "Host: photos.adaobi.test" http://localhost:8088/`.

### Read the logs

```sh
docker compose logs -f openresty                       # follow
docker compose logs --since 10m openresty | grep -E "\[(error|warn)\]"
```

The access log (every request) goes to stdout and errors/warnings to
stderr; both end up in `docker compose logs`. `nginx.conf` sets the level
to `warn`, so successful orders and renewals (logged at `info`) are quiet
and only problems show. To watch an order step by step, change
`error_log /dev/stderr warn;` to `info` and reload.

| Log line contains | Meaning |
|---|---|
| `tls ask for <domain> failed: timeout` (or `connection refused`) | OpenResty couldn't get an answer from the app's `/internal/tls/ask`: app down or slow |
| `tls ask for <domain> answered 403` (or 500) | the app refused the caller (wrong `TLS_ASK_TOKEN`) or crashed: check `docker compose logs app` |
| `held back: over the cap` | the new-certificate cap (step 6) |
| `limiting requests` | `limit_req` turned a flood away (step 6) |
| `error updating cert for <domain>` | the order failed: the CA couldn't validate (DNS doesn't point here, port 80 blocked) or a rate limit; the rest of the line says which |
| `failed to renew certificate for domain` | a renewal failed; the old certificate keeps being served until it expires |
| `error during acme init` / `acme login` | can't reach the CA, or the account key is unusable |
| `init_by_lua error` | a mistake in `nginx.conf`'s Lua; OpenResty won't start |
| `ignoring stale global SSL error` (talking to Pebble) | harmless noise from the TLS library; issuance still works |

After editing config: `docker compose exec openresty openresty -t` checks it,
`docker compose exec openresty openresty -s reload` applies it without
dropping connections.

### Symptom → where to look

| Symptom | First check |
|---|---|
| Browser shows the fallback certificate | `s_client` with `-servername`; `tls ask` lines; is the domain `verified` in Admin › Domains? |
| 502 Bad Gateway | the app container: `docker compose ps`, `docker compose logs app` |
| LiveView reconnects forever | WebSocket upgrade: `curl … -H "Upgrade: websocket"` should give 101 (step 2) |
| 429 for real users | `limit_req` too strict for a shared address; raise `rate`/`burst` (step 6) |
| "certificate not yet valid" locally | clock skew; reset Pebble (step 4, "When it goes wrong") |
| Every visit to a new domain is slow | the CA is slow or retrying; look for `acme` lines |

## The whole flow, checked in a browser

With the stack up and seeded, a temporary verified domain
`photos.adaobi.localhost` was added (Chrome resolves every `*.localhost`
name to this machine, so no DNS or flags are needed):

| Check | Result |
|---|---|
| First HTTPS request | certificate issued by Pebble, 200 |
| Chain against Pebble's root (`curl --cacert`) | verified (`ssl_verify_result=0`) |
| Code POST over HTTPS | 302 to `/our-little-one/timeline` |
| Timeline over HTTPS | 200 |
| LiveView WebSocket over HTTPS | 101 |
| Chrome, `http://photos.adaobi.localhost:8088` | the owner's site, code entry, the timeline with photos |

Chrome itself stops at HTTPS with a certificate warning: it rightly doesn't
trust Pebble's root. To see the padlock locally you'd have to import
`/tmp/pebble-root.pem` into a throwaway Chrome profile, and fetch it again
every time Pebble restarts. In production the certificates come from
Let's Encrypt, which browsers trust.

To repeat it, add the domain the same way the seeds add `photos.adaobi.test`
(`priv/repo/seeds.exs`), and delete it afterwards in Admin › Domains, plus
its certificate (see step 5 for the storage layout).

## The release image

`Dockerfile` (repo root) builds what production runs:

- **build stage:** Erlang 29 + Elixir 1.19.5 (the same as `.tool-versions`),
  deps fetched and compiled for `prod`, Tailwind and esbuild run with
  `mix assets.deploy`, then `mix release`.
- **run stage:** Debian slim with only the runtime libraries; no compilers,
  no Mix, no source. Runs as `nobody`. libvips comes precompiled inside the
  `vix` package, as in dev.
- **`rel/overlays/bin/server`** is the start command: it runs
  `bin/migrate` (`Keepsakes.Release.migrate/0`), then starts the app. So a
  deploy that brings new migrations applies them on boot.
- Photos on local disk (when `S3_BUCKET` is empty) live in the
  `/var/lib/keepsakes/uploads` volume.

Try it locally. It runs against its own empty database, so your dev data is
never touched:

```sh
docker compose exec db createdb -U postgres keepsakes_release   # once
docker compose --profile release up -d --build app_release
docker compose logs app_release        # migrations, then "Running KeepsakesWeb.Endpoint"
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4200/
docker compose --profile release stop app_release
```

It reads your `.env` (Resend, R2, Flutterwave test keys), with throwaway
`SECRET_KEY_BASE` and `CLOAK_KEY` values set in `compose.yaml`. Production
gets real ones from the server's `.env`. Production forces HTTPS for
every host except `localhost`, so `admin.localhost:4200` redirects to
`https://`. That's expected: behind OpenResty, the
`X-Forwarded-Proto: https` header tells the app the request was already
secure.

### What running the release caught

The dev server and the release don't behave the same, and running the
release found three problems that would only have shown up in production:

| Problem | Why dev didn't show it | Fix |
|---|---|---|
| `http://admin.<host>` redirected to `https://<host>/`, the main site (customers' domains too) | `force_ssl` is production-only, and Phoenix points its redirects at the main host by default | `force_ssl: [host: nil]`: redirect to the host that was asked for |
| `/internal/tls/ask` answered 301 to OpenResty, which reads as "no certificate": none would ever be issued | same: no `force_ssl` in dev | excluded from `force_ssl` (`paths: ["/internal/tls/ask"]`) |
| OpenResty's address `172.30.0.10` arrived as `::ffff:172.30.0.10`, not recognised as private: the ask refused (403) and forwarded headers ignored | the release listens on IPv6 `::` (dual-stack); the dev server on IPv4 | `ClientIP.private?/1` unwraps IPv4-mapped addresses |

The lesson: test the image you'll ship, not just the dev server.

## Going to production (Stage 11)

The edge needs no new code for production: the same `deploy/openresty/`
files, with different settings.

| Setting (openresty service) | Local | Production |
|---|---|---|
| `ACME_DIRECTORY_URL` | `https://pebble:14000/dir` | first `https://acme-staging-v02.api.letsencrypt.org/directory`, then unset (= Let's Encrypt production) |
| `ACME_EMAIL` | `dev@keepsake.test` | a real address you read |
| Pebble root mount (`extra-ca`) | yes | **remove**: Let's Encrypt is already trusted |
| `TLS_ASK_TIMEOUT_MS` | 10000 | unset (2000) |
| `TLS_ASK_TOKEN` | optional | set, the same value as the app's |
| ports | 8088 / 8443 | **80 / 443** (Let's Encrypt only validates on port 80) |
| upstream | `app:4100` (dev server) | the release container on port 4000 (`conf.d/keepsake.conf`) |

**Order of operations:**

1. **DNS at Namecheap:** A records for `@`, `admin`, `staging` and `edge`,
   pointing at the server's IP. Customers' domains CNAME to `edge.<domain>`;
   root domains use A records to `EDGE_IPS`.
2. **Firewall:** ports 80 and 443 open (both ufw and the DigitalOcean Cloud
   Firewall).
3. **Let's Encrypt staging first.** Browsers show a warning (staging's root
   isn't trusted), but its limits are about 10× higher, so mistakes don't
   lock you out. Check with `s_client` that the issuer is `(STAGING)`.
4. **Switch to production:** unset `ACME_DIRECTORY_URL`, then empty the
   `certs` volume, `account.key` included: the staging certificates would
   otherwise be served until renewal, and the key belongs to a staging
   account. The entrypoint makes a new key on the next start.
5. **Back up the `certs` volume** with the database backups. Losing it
   means re-ordering every certificate at once, which the new-certificate
   cap (step 6) spreads out but can't avoid.
6. **Watch expiry:** an uptime check on a customer domain's certificate
   (UptimeRobot can alert on expiry) catches broken renewals before
   visitors do.

Also at deploy: `REQUIRE_STAFF_TWO_STEP=true`, `EDGE_HOST`/`EDGE_IPS`, and
turning on the `custom_domains` flag for the customers who should have it.
The full checklist is in `DEPLOYMENT.md`.
