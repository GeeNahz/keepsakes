# Step 4: certificates on demand

## Why "on demand"

Our own hosts (`keepsake.com`, `admin.keepsake.com`) are known in advance,
so their certificates could be fetched ahead of time. Customers' domains
aren't: anyone on Pro can add one at any moment. So we get each
certificate **the first time a browser connects to that name**, from inside
the TLS handshake. This is what Caddy calls "on-demand TLS", and it's why
we use OpenResty rather than plain nginx: plain nginx can only load
certificate files it was told about at startup.

## How a first visit goes

```
browser ── TLS hello, SNI "photos.adaobi.test" ──► OpenResty :443
                                                    │ ssl_certificate_by_lua
                                                    │ 1. certificate in storage? no
                                                    │ 2. ask the app ─► GET app:4100/internal/tls/ask?domain=…
                                                    │      200 = it's a verified customer domain
                                                    │ 3. ACME order with the CA (step 3's flow)
                                                    │      the CA fetches /.well-known/acme-challenge/…
                                                    │      on port 80, which Lua answers
                                                    │ 4. store the certificate
browser ◄── handshake finishes with the new certificate ┘
```

- **SNI** (Server Name Indication) is the hostname the browser puts in its
  first TLS message, before any HTTP. It's how one IP address can serve
  thousands of certificates.
- **`ssl_certificate_by_lua_block`** runs Lua at that moment, before nginx
  picks a certificate. It's one of the Lua *phases* from step 1.
- **`blocking = true`** makes that first visitor wait while the certificate
  is fetched (about 7 seconds locally, mostly Pebble's three validation
  fetches; a few seconds with Let's Encrypt). Without it they'd get the
  fallback certificate (and a browser warning) and only a later visitor
  would get the real one.
- Later visits read the certificate from memory (an LRU cache per worker)
  or from storage, with no CA involved: the handshake takes ~10 ms.

Two keys are involved, and they're different things:

- The **account key** identifies *us* to the CA and signs every ACME
  request. One per edge, made once by `entrypoint.sh`, kept in the `certs`
  volume. lua-resty-acme only supports **RSA** account keys.
- Each certificate has its own **domain key**, the one browsers see.
  Ours are **EC P-256** (`domain_key_types = { "ecc" }`): smaller and
  faster than RSA, and supported by every current browser.

## The ask gate

Without a check, anyone could point a thousand made-up names at our IP and
make us order a thousand certificates. Let's Encrypt would rate-limit
*our* account, and real customers' certificates would stop being issued.

So before ordering, Lua asks the app (`lua/keepsake/ask.lua`):

- `GET http://app:4100/internal/tls/ask?domain=<name>` over the private
  compose network.
- **200** for our own hosts and customers' verified, non-blocked domains
  (`KeepsakesWeb.TlsAskController`); **404** for everything else.
- The answer is kept for **60 seconds** in a shared dict, so a busy domain
  costs one call a minute.
- If the app doesn't answer, the answer is "no", and it isn't remembered.
- The gate runs on every handshake, not only before ordering. So **blocking
  a domain in the admin portal takes it off HTTPS within a minute**, even
  though its certificate is still stored.
- When `TLS_ASK_TOKEN` is set, Lua sends it in `x-tls-ask-token` and the
  app requires it. It's extra protection; the private-network check does
  the main work.

## The pieces

| File | What it does |
|---|---|
| `deploy/openresty/Dockerfile` | installs lua-resty-acme 0.16.0 (+ lua-resty-openssl, lua-resty-http, luafilesystem), makes a throwaway fallback certificate |
| `deploy/openresty/nginx.conf` | `init_by_lua_block` configures autossl: CA URL, account key, the ask callback, file storage |
| `deploy/openresty/conf.d/keepsake.conf` | port 80 (challenges + the site), port 443 with `ssl_certificate_by_lua_block` |
| `deploy/openresty/snippets/proxy.conf` | the locations both servers share (from step 6, with the proxy lines themselves in `proxy-pass.conf`) |
| `deploy/openresty/lua/keepsake/ask.lua` | the ask gate with its one-minute cache |
| `deploy/openresty/entrypoint.sh` | makes the ACME account key once, builds the CA list Lua trusts |

Settings, on the `openresty` service:

| Variable | Locally | Production |
|---|---|---|
| `ACME_DIRECTORY_URL` | `https://pebble:14000/dir` | unset (= Let's Encrypt), or LE staging while testing |
| `ACME_EMAIL` | `dev@keepsake.test` | your real address, for expiry notices |
| `TLS_ASK_TOKEN` | from `.env` (optional) | from `.env`, same value as the app's |
| `TLS_ASK_TIMEOUT_MS` | 10000 (the dev server is slow, see step 5) | unset (2000) |

The **fallback certificate** exists because nginx refuses to start an
HTTPS server without one. It's used only when no real certificate can be
had: a name the app refuses, or a client that sends no SNI (e.g. visiting
the bare IP).

## Try it

The seeds add a verified customer domain, `photos.adaobi.test`, owned by
the dev account, with the sample album on its site:

```sh
docker compose up -d --build
docker compose exec app mix run priv/repo/seeds.exs
```

`photos.adaobi.test` isn't in any DNS your computer uses, so tell curl
where it lives with `--resolve`. To trust the certificate, fetch the root
Pebble is signing with. Pebble makes a **new root every time it starts**,
so fetch it again after restarting Pebble.

```sh
docker compose exec -T openresty curl -sk https://pebble:15000/roots/0 > /tmp/pebble-root.pem

curl --resolve photos.adaobi.test:8443:127.0.0.1 --cacert /tmp/pebble-root.pem \
     -sS -o /dev/null -w "%{http_code} in %{time_total}s\n" https://photos.adaobi.test:8443/
```

The first request takes several seconds (the certificate is being
issued); later ones don't. Watch it happen with
`docker compose logs -f pebble openresty` in another terminal. Look at what
was served:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername photos.adaobi.test </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

A name the app doesn't know gets the fallback, and no order is placed:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername stranger.test </dev/null 2>/dev/null \
  | openssl x509 -noout -subject          # CN = keepsake-fallback
```

To see it in a browser, map the name to your machine for the session.
Chrome (the command may be `google-chrome-stable` or `chromium`, depending
on how it was installed):

```sh
google-chrome --host-resolver-rules="MAP photos.adaobi.test 127.0.0.1" \
              --user-data-dir=/tmp/chrome-keepsake https://photos.adaobi.test:8443
```

Chrome will warn that it doesn't know the CA (Pebble's root isn't one it
trusts, rightly). The certificate details still show Pebble as the issuer.
`--user-data-dir` keeps this test window apart from your normal profile.

### Blocking a domain stops it at the edge

Block `photos.adaobi.test` in the admin portal (Domains). Within a minute
the `s_client` command above shows the fallback certificate, and the site
itself answers 404. Unblock it to bring it back, again within a minute
(the cached "no" has to run out too). Running the seeds again also resets
it. When this was tested, the edge stopped serving the certificate 31
seconds after the block and served it again 55 seconds after the unblock.

### When it goes wrong

- **curl: "certificate is not yet valid"**, with a Pebble root whose
  `notBefore` is in the future: the computer's clock was ahead when Pebble
  started (it happened here once, right after a reboot, before the clock
  synced and jumped back). Pebble keeps everything in memory, so reset it
  and the stored test certificates:

  ```sh
  docker compose restart pebble
  docker compose exec openresty sh -c 'rm -rf /var/lib/acme/certs/*'
  docker compose restart openresty
  ```

  then fetch the root again. The same reset applies any time you restart
  Pebble, since its root changes and old certificates no longer chain to it.
- **No certificate, fallback every time**: look for `tls ask` lines in
  `docker compose logs openresty` (the app isn't answering), and check the
  domain is `verified` in Admin › Domains.
- **OpenResty won't start, `init_by_lua error`**: the message is in
  `docker compose logs openresty`; it's usually a typo in `nginx.conf`'s Lua.

## What's still to come

- **Step 5:** where certificates are kept (`certs` volume), renewals, what
  restarts do, and Let's Encrypt's real rate limits.
- **Step 6:** `limit_req` and a cap on how many new certificates we order
  per minute.
