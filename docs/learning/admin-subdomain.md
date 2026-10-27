# The admin portal on its own subdomain

The staff portal lives at `admin.<your host>` (for example
`admin.keepsake.com`). It's part of the same app, the same release and the
same container as the main site. Nothing is deployed separately. This page
explains how one app can answer two hostnames and keep their sessions apart.

## 1. One endpoint, two hostnames

The main site and the admin portal both point at the same Phoenix
endpoint. DNS sends both names to the same server, and the proxy (OpenResty,
in Stage 11) sends both to the same app:

```
keepsake.com        ─┐
admin.keepsake.com  ─┴─> OpenResty ──> the Keepsake app (one Endpoint)
```

Every request carries a `Host` header, and Phoenix puts it in `conn.host`.
That's all the app needs to tell the two sides apart.

## 2. The router matches the admin routes by host

In `lib/keepsakes_web/router.ex` the admin routes sit in scopes with
`host: "admin."`:

```elixir
scope "/", KeepsakesWeb.Admin, host: "admin." do
  pipe_through [:admin_browser, :require_staff]
  live "/", DashboardLive, :index
end
```

`host: "admin."` matches any host that starts with `admin.`. These scopes
come before the main site's routes, so on the admin host `/` is the
dashboard, not the landing page. On the main host the admin scopes never
match, so `keepsake.com/staff` is a plain 404.

The prefix is compiled into the router, so `ADMIN_HOST` must also start
with `admin.`. `config/runtime.exs` refuses to boot otherwise.

## 3. Each side refuses the other's host

Matching by prefix isn't strict enough on its own, and without more checks
the main site's routes would answer on the admin host as well (try
`admin.keepsake.com/app/albums`). `KeepsakesWeb.Hosts` adds two plugs:

- `only_main_host` is in the main `:browser` pipeline. It returns a 404 on
  the admin host.
- `only_admin_host` is in the `:admin_browser` pipeline. It returns a 404
  on any host other than the configured one, exactly.

## 4. Cookies keep the sessions apart

The session cookie (`_keepsakes_key`) is set without a `Domain` attribute,
so the browser makes it a host-only cookie. A cookie set by
`admin.keepsake.com` is only ever sent back to `admin.keepsake.com`, and
one set by `keepsake.com` only to `keepsake.com`. The two never meet.

So a customer who is logged in on the main site arrives at the admin
portal with an empty session and has to sign in. Phoenix gives us this
for free, as long as nobody adds `domain: ".keepsake.com"` to the session
options. That one line would share the session across every subdomain.

## 5. Same accounts, separate admin session

Staff aren't a separate kind of user. A staff member is an ordinary
account with an active `staff_memberships` row and one or more roles.

Signing in to the admin portal uses the account's normal email and
password check and its normal two-step login (`Accounts.TwoStep`). If the
account has two-step login on, the portal asks for a code.

- **Two-step login can be required.** With `REQUIRE_STAFF_TWO_STEP=true`, a
  staff member who hasn't turned it on is asked to set it up before they
  get in. It's off for now, to keep development simple.
  **Before production: set `REQUIRE_STAFF_TWO_STEP=true`.** Staff can
  refund payments and change customers' plans, so a password alone
  shouldn't be enough.
- **The session is short.** The portal stores its own token in
  `users_tokens` under the context `"staff_session"`, and it lasts 12 hours.
  Main-site sessions last 14 days.

Every request checks the membership again. Removing someone's staff access
locks them out on their next page load, while their customer account
carries on as normal.

## 6. Permissions, checked twice

Each admin page names the permission it needs in its `live_session`:

```elixir
on_mount: [{KeepsakesWeb.Admin.Auth, :require_staff},
           {KeepsakesWeb.Admin.Auth, {:permission, "roles.manage"}}]
```

A staff member without that permission gets a 403, and the sidebar only
lists the sections they can open. The context functions (`Keepsakes.Staff`,
`Keepsakes.Audit`, `Keepsakes.Metrics`) also call `Staff.authorize!/2`
themselves. Hiding a button is never the only check.

Every change made in the portal is written to `audit_events` in the same
transaction as the change, along with who made it and from which IP.

## 6b. Customers' own domains use a second router

The admin portal can share the main router because every admin host
starts with `admin.`. Customers' domains (Stage 8) can be anything, like
`photos.adaobi.com`, and their `/` has to be *their* site, not our landing
page. A router can't match "any verified domain", so the endpoint picks
the router per request (`KeepsakesWeb.HostRouter`):

- **Main host or admin host:** `KeepsakesWeb.Router`, as before.
- **A customer's verified domain:** `KeepsakesWeb.SiteRouter`, a small
  router with just the public site and the guest pages. The domain sits in
  `conn.assigns.site` and in the LiveView session.
- **A customer's domain that isn't connected:** a plain 404.
- **Anything else** (internal calls by IP or container name): the main
  router.

LiveView remembers which router rendered a page, so live navigation works
on both. `check_origin` becomes an MFA (`KeepsakesWeb.Origin`), so sockets
from verified domains are accepted.

## 7. LiveView sockets on both hosts

A LiveView page opens a WebSocket back to its own host. In production
`check_origin` lists both hostnames, so sockets from either are accepted:

```elixir
check_origin: ["//#{host}", "//#{admin_host}"]
```

## 8. Trying it locally

Browsers resolve any `*.localhost` name to your own machine, so there's no
`/etc/hosts` file to edit:

- main site: `http://localhost:4000`
- admin portal: `http://admin.localhost:4000`

Use whichever port you run `mix phx.server` on. To make an account a Super
Admin, either set `SUPER_ADMIN_EMAIL` in `.env` and restart, or run:

```
mix keepsakes.staff.grant you@example.com --role super_admin
```

In a release:

```
bin/keepsakes eval 'Keepsakes.Release.grant_staff("you@example.com", "super_admin")'
```

## 9. In production (Stage 11)

- DNS: an `A` record for `admin` pointing at the server, next to `@`.
- OpenResty: one `server` block with `server_name keepsake.com
  admin.keepsake.com;`, proxying to the app. The certificate covers both
  names.
- Env: `PHX_HOST=keepsake.com`. `ADMIN_HOST` is only needed if the admin
  host isn't `admin.` followed by `PHX_HOST`.
- Env: `REQUIRE_STAFF_TWO_STEP=true` (see section 5).
