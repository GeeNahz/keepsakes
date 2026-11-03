# Step 6: abuse protection at the edge

The app already limits the things people might abuse
(`KeepsakesWeb.AuthThrottle`, the access-code limiter): per email, per
account, per album and visitor. Those limits are precise but not free:
every attempt still reaches Phoenix, and a sign-in attempt costs a bcrypt
hash on purpose. The edge adds a **cheap, coarse layer in front**: a flood
is turned away by OpenResty before Phoenix does any work.

## Request limits (`limit_req`)

nginx's `limit_req` is a *leaky bucket* per key (here, per visitor
address):

- `rate=10r/m`: the bucket drains at 10 requests a minute (one every 6 s).
- `burst=10 nodelay`: it holds 10 more, served at once instead of queued.
- Anything beyond: **429 Too Many Requests**, and a warning in the log.

So one address can send about 11 at once, then one every 6 seconds.

```nginx
map $request_method $post_from {          # only POSTs carry a key;
  POST    $binary_remote_addr;            # an empty key isn't counted,
  default "";                             # so page loads are never limited
}
limit_req_zone $post_from zone=sign_in:10m      rate=10r/m;
limit_req_zone $post_from zone=access_codes:10m rate=10r/m;
```

| Zone | Applies to |
|---|---|
| `sign_in` | `POST /auth/log-in`, `/auth/two-step`, `/auth/restore` (main site) and `/log-in`, `/two-step…` (admin portal): one zone, so attacking one form doesn't give a fresh allowance on the other |
| `access_codes` | `POST /a/<slug>/access` (our site) and `POST /<album>/access` (customers' domains) |

`10m` is the memory for keys: about 160,000 addresses.

**Why so generous?** Many mobile users in Nigeria share one public address
behind their carrier (carrier-grade NAT), so a strict per-address limit
would lock out strangers who happen to share it. The edge only stops
floods; the app's per-email and per-album limits do the fine-grained work.

**What the edge can't see.** Sign-up and password reset are LiveView forms:
their events travel inside the WebSocket, not as separate HTTP requests.
Only the app's limits cover them (they do).

`X-Forwarded-For` doesn't matter here: OpenResty is the first hop, so
`$binary_remote_addr` is the visitor's real address.

### Location order

The limited locations are regexes, and nginx checks regexes before plain
prefix locations. That's why `/internal/` is now `location ^~ /internal/`:
`^~` means "if this prefix matches, stop looking". Otherwise
`/internal/x/access` would match the access-code regex and be proxied.

The proxy settings moved to `snippets/proxy-pass.conf` so every location
that proxies includes the same lines.

## A cap on new certificates

The ask gate (step 4) already refuses names that aren't ours. But even
legitimate names can come in a burst: many customers verifying at once, or
the `certs` volume being lost and every domain ordering again. Let's
Encrypt allows **300 new orders per account per 3 hours**; past that,
*every* new customer's certificate fails for a while.

`lua/keepsake/ask.lua` caps **brand-new** certificates:
`ACME_NEW_PER_MINUTE` (10) and `ACME_NEW_PER_HOUR` (90).

- Only names with no stored certificate count. **Renewals never count**
  (Let's Encrypt exempts them from the orders limit too).
- Each name counts once an hour, however many visitors arrive at once or
  however often its order is retried.
- A name over the cap gets the fallback certificate for that visit, with
  a `held back` warning in the log. It isn't counted as a failure (no
  backoff), so it gets its certificate on a visit after the window rolls
  over.

90 an hour stays well inside 300 per 3 hours, leaving room for retries.

## Blocking a domain

From step 4: the gate runs on every handshake, so a domain blocked in
Admin › Domains loses HTTPS within a minute (the answer cache), and the
app itself answers 404 for it over HTTP straight away. Nothing else is
needed at the edge.

## Try it

```sh
# 25 sign-in attempts at once: ~12 reach Phoenix (403 here, no CSRF
# token), the rest are 429 from OpenResty
for i in $(seq 25); do curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  http://localhost:8088/auth/log-in; done | sort | uniq -c

# Page loads are never limited
for i in $(seq 25); do curl -s -o /dev/null -w "%{http_code}\n" \
  http://localhost:8088/auth/log-in; done | sort | uniq -c

docker compose logs openresty | grep "limiting requests"
```

The bucket refills at one every 6 seconds, so after a minute you can
flood again.

To see the certificate cap, set it to 1 a minute
(`ACME_NEW_PER_MINUTE=1 docker compose up -d openresty`), and visit two
verified domains that don't have a certificate yet: the second gets the
fallback and the log says `held back`. A minute later it gets its
certificate. `docker compose up -d openresty` puts the default back.

Tested here with two temporary domains: `cap-one.test` got a certificate,
`cap-two.test` was held back with nothing stored against it, and got its
certificate 62 seconds later.

## Results from testing

| 25 POSTs at once | Reached Phoenix | 429 at the edge |
|---|---|---|
| main sign-in | 12 | 13 |
| access code | 13 | 12 |
| admin sign-in (right after the main flood, same zone) | 3 | 22 |
| sign-in page GETs | 25 | 0 |

## Settings (openresty service)

| Variable | Default | |
|---|---|---|
| `ACME_NEW_PER_MINUTE` | 10 | brand-new certificates per minute |
| `ACME_NEW_PER_HOUR` | 90 | brand-new certificates per hour |

The request limits themselves are in `conf.d/keepsake.conf` (`rate=`) and
`snippets/proxy.conf` (`burst=`): change them there and
`docker compose exec openresty openresty -s reload`.
