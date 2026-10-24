# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `.env` loading via Dotenvy in `config/runtime.exs` (real env vars win); every variable is documented in the committed `.env.example`, and dev/test DB credentials come from `DB_USER`/`DB_PASS`/`DB_HOST`/`DB_PORT`.
- Project `.tool-versions` pinning Erlang 29.0, Elixir 1.19.5 and Node.js 26.12.1.
- Oban background jobs (`media`, `mailers`, `billing`, `domains` queues) with the `oban_jobs` migration.
- FunWithFlags feature flags persisted in Postgres (`fun_with_flags_toggles`, UUID key) with PubSub cache busting.
- Self-hosted ErrorTracker error tracking (`error_tracker_*` tables), disabled in test.
- `Keepsakes.Vault` (Cloak AES-GCM, key from `CLOAK_KEY`) and `Keepsakes.Encrypted.Binary` Ecto type for encrypting sensitive columns.
- `Keepsakes.RateLimit` ETS rate limiter (Hammer) for access-code and auth throttling.
- `Keepsakes.Schema` base module enforcing UUID (`:binary_id`) primary and foreign keys plus UTC timestamps on every schema.
- `Keepsakes.Settings` typed system configuration (`system_settings` table) with defaults for trial days (60), grace days (7), image long edge (2400 px), image quality, max upload size, signups, maintenance mode and default template, plus an ETS cache invalidated over PubSub.
- `Keepsakes.Storage` behaviour with `Local` (signed `/media/<token>` URLs) and `S3` (Cloudflare R2 / DigitalOcean Spaces via ReqS3, presigned URLs) adapters, selected by whether `S3_BUCKET` is set.
- `keepsake` and `keepsake-night` daisyUI themes and `ks-*` design tokens from the design canvas, with self-hosted font declarations for DM Sans, Bricolage Grotesque, DM Mono and Caveat.
- Self-hosted latin WOFF2 font files (DM Sans, Bricolage Grotesque, DM Mono 500, Caveat 600) in `priv/static/fonts`.
- Core components `logo`, `avatar`, `badge`, `meter` and `modal`, plus `primary`/`secondary`/`outline`/`ghost`/`danger` button variants.
- Dev-only component gallery at `/dev/components`.
- GitHub Actions CI workflow running `mix precommit` against Postgres 18 on every push and pull request.
- User accounts (`phx.gen.auth`, LiveView, bcrypt): `users` table with `first_name`, optional `last_name`, citext `email`, `avatar_key`, `hashed_password`, `confirmed_at`, plus `users_tokens`, all UUID-keyed.
- Registration at `/users/register` ported from the design's "Create your account" screen (first name, last name, email, password); new users are logged in immediately and emailed a confirmation link.
- Log in at `/users/log-in` with email + password ("Keep me logged in") or an emailed one-time sign-in link.
- "Forgot password?" at `/users/reset-password`, which emails a 15-minute link that signs the user in and opens the password section of settings.
- Confirm-email banner in the owner portal for unconfirmed accounts, with `POST /users/confirm/resend` to send a new link.
- Branded HTML + plain-text transactional emails (`Keepsakes.Mailer.build/1`, `Keepsakes.Mailer.Layout`) for confirmation, sign-in link, password reset and email change.
- Resend email delivery through Swoosh, enabled by `MAIL_DELIVERY=resend` (the default in prod) with `RESEND_API_KEY`, `MAIL_FROM_ADDRESS` and `MAIL_FROM_NAME`; dev keeps the local `/dev/mailbox` otherwise.
- Rate limits on password log in (20 per 15 min per IP, 8 per email), emailed links (10 per hour per IP, 3 per 15 min per email) and registration (10 per hour per IP) via `KeepsakesWeb.AuthThrottle`.
- Registration respects the `signups_open` system setting and shows a "sign-ups paused" notice when it is off.
- Owner portal shell: header with "My albums" and an avatar menu (settings, log out, theme), album sidebar with the storage meter, used by `/albums` and settings.
- `/albums` owner home showing the design's "Start your first album" empty state (album creation lands in Stage 2).
- Name section in account settings, and a "Set a password" prompt for accounts without one.
- `Keepsakes.Accounts.Scope` carries `user` plus `subscription` and `entitlements` slots for plans.
- `docs/setup/accounts.md`: Cloudflare R2 and Resend setup walkthroughs, what `MAIL_DELIVERY` does, and a per-stage production-readiness checklist of accounts and variables.
- `mix keepsakes.storage.check` (and `Keepsakes.Release.storage_check/0` for releases): writes, reads, signs a URL for, fetches and deletes a probe object to verify storage credentials.
- `albums` and `memories` tables with `Keepsakes.Albums` context scoped to the owner: per-owner album slugs, drafts, publishing, timeline ordering (year, month, then upload order; undated last), cover selection, people tags and storage usage, with live PubSub updates.
- Media pipeline (`Keepsakes.Media.ProcessMemory` Oban job on the `media` queue): reads EXIF date taken and GPS, auto-fills month/year and place without overwriting what the owner typed, rotates upright, stores 480/1200/2400 px WebP variants with all metadata stripped, then deletes the original. `Keepsakes.Media.Purge` removes files of deleted memories.
- Place names from photo GPS via OpenStreetMap Nominatim (`Keepsakes.Media.Geocoder`, rate limited to 1 request/second), switchable off with `GEOCODER=none`.
- `GET /media/:token` serves locally stored photos from signed, expiring tokens, with `LOCAL_X_ACCEL_PREFIX` handing the file off to OpenResty in production.
- Album page (`/albums/:slug`): AlbumNoPhotos empty state with drag-and-drop, and the Album grid with cover badge, "Needs name/date" badges and a "Sorted by date taken" summary.
- Upload screen (`/albums/:slug/upload`) for Upload one and Bulk upload: drag-and-drop, `UploadQueue` with progress and readiness, `MemoryForm` that saves as you type, people chips, Prev/Next with readiness dots, live "optimised" note, Save/Cancel. Unfinished drafts can be resumed later.
- Memory editor dialog (`/albums/:slug/memories/:id`) to edit details, set the album cover or delete a memory.
- New album dialog from the sidebar, and a working "Start your first album" form; `/albums` opens the newest album.
- Mobile album switcher row on the owner pages.
- Development seeds (`priv/repo/seeds.exs`): a confirmed local test account and sample photos in `tmp/sample-photos/`.

### Changed
- Migrations default to UUID primary keys, UUID foreign keys and `utc_datetime` timestamps via `migration_primary_key` / `migration_foreign_key` Repo config.
- AGENTS.md now prefers daisyUI components themed with the Keepsake themes instead of forbidding daisyUI.
- Interim app layout uses the Keepsake logo and theme toggle in place of the Phoenix scaffold header.
- `Layouts.app` takes a `shell` attribute (`:owner`, `:auth`, `:plain`); the auth pages use the split form + polaroid panel from the design.
- `/` shows an interim home with sign-up and log-in links and redirects logged-in users to `/albums`; the Phoenix scaffold page is gone.
- After logging in, users land on `/albums` instead of `/`.
- Signed storage URLs are rounded to a 15-minute window, so re-renders reuse the same image URL and the browser cache.
- The sidebar lists real albums with memory counts, and the storage meter shows actual usage (against a 1 GB placeholder until plans arrive).
- `modal` accepts `box_class` for wider dialogs.

### Fixed
- Dark mode: the soft teal/amber surfaces and muted text now have night-theme values, so selected rows, notes and badges stay readable; text on white polaroids uses fixed ink colours in both themes.

### Security
- Opening an emailed link for an unconfirmed account from a browser that isn't logged in as that account confirms it, removes any password and expires every session. This blocks someone who pre-registered another person's email from keeping access.
