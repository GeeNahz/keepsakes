# Step 1: OpenResty and a plain reverse proxy

## What OpenResty is

**nginx** is a fast web server and reverse proxy: it accepts connections from
browsers and passes requests on to an application (here, Phoenix). Its
behaviour is fixed by its configuration file.

**OpenResty** is nginx with **LuaJIT** built in, plus a set of Lua libraries.
That lets the proxy run small programs *during* a request, at specific
points nginx calls **phases**:

| Phase | Runs when | We'll use it for |
|---|---|---|
| `init_by_lua` | once, at startup | loading the ACME library (step 4) |
| `ssl_certificate_by_lua` | during the TLS handshake, before any HTTP | picking or issuing a certificate for the hostname (step 4) |
| `access_by_lua` | before a request is proxied | rate limits, blocking (step 6) |
| `content_by_lua` | to produce a response itself | the ACME challenge answers (step 3) |

Plain nginx needs every certificate listed in its config before it starts.
Customers add their own domains at any time, so we need the proxy to get a
certificate **the first time a new hostname connects**. That's the
`ssl_certificate_by_lua` phase, and the reason for OpenResty.

## How the local stack fits together

`compose.yaml` runs the same services production will:

```
browser ──> openresty :8088 ──> app :4100 (Phoenix) ──> db :5432 (Postgres)
```

- **`openresty`** is built from `deploy/openresty/Dockerfile`: the pinned
  `openresty/openresty:1.29.2.3-alpine-fat` image plus our config. "Fat"
  includes `opm`/`luarocks` for installing Lua packages later.
- **`app`** is built from `Dockerfile.dev`: Erlang 29.0 and Elixir 1.19.5
  (the same as `.tool-versions`), running `mix phx.server` with your source
  mounted, so code reloading works. `deps` and `_build` live in Docker
  volumes so they never mix with the ones on your machine. It runs as your
  user (uid 1000), so files it writes stay yours.
- **`db`** is Postgres 18.4 with its own volume, seeded from the old
  `postgres_db` container with `pg_dump`/`pg_restore`.

The containers reach each other by service name on the compose network
(`app:4100`, `db:5432`), so nothing crosses your machine's firewall.

## The config

`deploy/openresty/conf.d/keepsake.conf`:

```nginx
upstream phoenix {
  server app:4100;
}

server {
  listen 80 default_server;
  server_name _;

  location / {
    proxy_pass http://phoenix;
    proxy_set_header Host $host;
  }
}
```

- **`upstream phoenix`** names the app's address. `app` is looked up once,
  when OpenResty starts.
- **`listen 80 default_server`** with **`server_name _`**: one server block
  for *every* hostname (your domain, `admin.`, customers' domains).
- **`proxy_pass`** forwards each request to Phoenix.
- **`proxy_set_header Host $host`** passes on the hostname the browser asked
  for. Without it Phoenix would see `phoenix` as the host and couldn't tell
  the main site, the admin portal and customers' domains apart
  (`KeepsakesWeb.HostRouter`).

### A lesson from building it

The OpenResty image ships its own `/etc/nginx/conf.d/default.conf` with
`server_name localhost`. nginx picks a server block by **exact name first**
and only falls back to `default_server` when nothing matches. So
`http://localhost:8088` showed "Welcome to OpenResty!" until the Dockerfile
removed that file.

## Try it

```sh
docker compose up --build        # first time: builds images, compiles the app
```

Then:

| Open | You should see |
|---|---|
| http://localhost:8088 | the landing page, through OpenResty |
| http://admin.localhost:8088 | the staff sign-in (same proxy, the app routes by host) |
| http://localhost:4100 | the same app directly, skipping the proxy |

Watch requests arrive at the edge with `docker compose logs -f openresty`.

What isn't right yet: live (LiveView) pages want a WebSocket, and the
upgrade fails through the proxy (400; directly to the app it's 101). LiveView
quietly falls back to long-polling, so pages still work, just less
efficiently. Fixing that, with two headers, is step 2.
