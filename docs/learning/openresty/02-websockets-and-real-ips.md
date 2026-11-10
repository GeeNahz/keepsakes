# Step 2: WebSockets and the visitor's real address

## WebSockets through a proxy

LiveView pages keep a **WebSocket** open to the server. A browser opens one
by sending an ordinary HTTP request with two extra headers:

```
Connection: Upgrade
Upgrade: websocket
```

and the server answers `101 Switching Protocols`. After that the same TCP
connection carries WebSocket frames in both directions.

`Connection` and `Upgrade` are **hop-by-hop** headers: they describe *this*
connection, so a proxy must not pass them on blindly, and nginx drops them.
Without the lines below, the upgrade never reaches Phoenix and LiveView
quietly falls back to long-polling.

The fix is to forward them on purpose, over HTTP/1.1 (needed for upgrades):

```nginx
map $http_upgrade $connection_upgrade {
  default upgrade;   # the browser asked to upgrade
  ''      close;     # an ordinary request
}

location / {
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection $connection_upgrade;
  proxy_read_timeout 120s;
  ...
}
```

`map` turns "did the browser send `Upgrade`?" into the right `Connection`
value. `proxy_read_timeout` is how long nginx waits for the app to say
anything before closing; LiveView sockets go quiet between interactions, but
Phoenix pings every 30 seconds, so 120 seconds is plenty.

## Who's really connecting

Behind a proxy, **every connection reaches Phoenix from the proxy's
address**. Three parts of Keepsake care about the real one:

- **Rate limits** (sign-in, sign-up, access codes) count attempts per
  address. Through the proxy, everyone would share one bucket: one person's
  failed attempts would lock everyone out.
- **The audit log** records where staff changes came from.
- **`/internal/tls/ask`** (the certificate check from Stage 8a) only answers
  private-network callers. Through the proxy, *every* visitor looks like a
  private-network caller, so anyone on the internet could have used it.

### The edge says who it saw

```nginx
proxy_set_header X-Forwarded-For $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
```

`$remote_addr` is the address that connected to OpenResty: the visitor's.
Note that we **overwrite** `X-Forwarded-For`. The common recipe,
`$proxy_add_x_forwarded_for`, *appends* to whatever the visitor sent, and a
visitor could send `X-Forwarded-For: 127.0.0.1` to look local.
`X-Forwarded-Proto` says whether they came over `http` or `https` (from
step 4 on, HTTPS ends at OpenResty, and the app sees plain HTTP).

### The app believes it only from the proxy

`KeepsakesWeb.ClientIP` (a plug early in the endpoint) uses those headers
**only when the connection itself comes from a private-network address**,
i.e. from our proxy:

- It sets `conn.remote_ip` to the last `X-Forwarded-For` entry (the one our
  proxy wrote) and `conn.scheme` to `:https` when the proxy says so.
- Anyone on the internet sending the headers directly is ignored. In
  production the app's port is only reachable from the proxy anyway.
- LiveView sockets get the same treatment: the socket receives the proxy's
  headers (`connect_info: [:x_headers]`), and `ClientIP.from_socket/1`
  applies the same rule.

With the real address in `remote_ip`, the certificate check now refuses an
outside visitor who comes through the proxy, because they show up with
their public address. OpenResty also refuses `/internal/` at the edge, so
it's blocked twice.

## Try it

```sh
docker compose exec openresty openresty -s reload   # after editing conf.d (it's mounted)
```

- Open http://localhost:8088, sign in and use a live page: the browser's
  network tab shows the `websocket` request with status **101**.
- From a terminal:

  ```sh
  curl -i -H "Connection: Upgrade" -H "Upgrade: websocket" \
       -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
       "http://localhost:8088/live/websocket?vsn=2.0.0"      # 101 Switching Protocols
  curl -i "http://localhost:8088/internal/tls/ask?domain=localhost"   # 404 at the edge
  ```

### Config is mounted, not baked in (dev only)

`compose.yaml` mounts `deploy/openresty/nginx.conf` and `conf.d/` into the
container, so config changes only need `openresty -s reload` (instant)
rather than an image rebuild. The image still copies the same files in for
production.
