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
- `share_links` table and `Keepsakes.Sharing` context: one public link per album (`/a/<album-slug>-XXXX`), a 6-digit access code encrypted at rest (random or chosen by the owner, with obviously guessable codes like `123456` rejected), a code version that locks out old guests when the code changes, expiry, default guest view, captions/locations and download options, and open counts.
- Share page (`/albums/:slug/share`): set up sharing, copy the link, code and invite message, change the code (new random or your own), guest settings that save as you change them, activity ("Opened 14 times · last opened 2 hours ago") and Turn off sharing.
- Guest Access page (`/a/:slug`): six auto-advancing digit boxes with paste support, checked by `POST /a/:slug/access`, which is limited to 5 tries per 15 minutes per link and IP and remembers the unlock in the session. Unknown, turned-off and expired links show a "not available" page.
- Guest Timeline (`/a/:slug/timeline`): polaroids along a dashed trail (zig-zag on wide screens, alternating column on phones) with year markers and "To be continued…"; only complete, processed memories are shown.
- Auto-scroll on the timeline (`?auto=1` or the header toggle): slow/normal/fast, pause, replay from the top, pauses when the guest scrolls by hand.
- Guest Slideshow (`/a/:slug/slideshow`): tilted carousel over the trail, play/pause, previous/next, 3/5/8 second pacing, progress bar, jump-to stops, arrow keys, space and swipe.
- Guest photo downloads (`GET /a/:slug/photos/:id/download`) when the owner allows them.
- Owner preview of the guest views without a code (`/a/preview/:album_slug/timeline`), and a banner when the owner views their own shared album.
- Guest pages use a `guest_root` layout: always the night theme, `noindex`, same-origin referrer.
- Dev seeds also create a shared "Our Little One" sample album with six processed memories (code `482917`).
- Guest templates: a `templates` table (slug, name, description, renderer, theme, premium, active, position, optional owner `user_id` for future user-made templates), `albums.template_id` and `users.default_template_id`, seeded with "Trail" (the canvas design, system default) and "Daylight" (the same layout on warm paper with teal accents).
- `Keepsakes.Templates` context: templates available to a user (public plus their own), the system default from `Settings.default_template`, new albums get the owner's default template, and guest pages fall back from the album's template to the owner's default to the system default when a template is switched off.
- `Keepsakes.Templates.Theme`: validated colour and font slots that become CSS custom properties over the new `ks-guest-*` tokens; invalid values are never emitted.
- `KeepsakesWeb.Templates.Renderer` behaviour (`access/1`, `unavailable/1`, `timeline/1`, `slideshow/1`) with `KeepsakesWeb.Templates.Trail` as the first renderer.
- Template picker at `/albums/:slug/template` (Template button on the album page): cards drawn in each template's colours with the album's own photos, In use and Premium badges, Preview, Use this template, and a disabled "Create your own – Coming soon" card.
- Preview an album in a template before using it at `/a/preview/:album_slug/:template/timeline` (and `/slideshow`); the preview banner names the template and links back to the picker.
- "Template for new albums" setting on `/users/settings`.
- Plans and prices: `plans` (free/trial/paid, public flag, feature values as JSON) and `plan_prices` (NGN/USD, month/year, minor units), seeded with Free, Plus, Pro and a hidden Free trial plan (Pro features). Plus and Pro prices are [TBD] placeholders: ₦5,000/₦50,000 and $5/$50 for Plus, ₦12,000/₦120,000 and $12/$120 for Pro, per month/year.
- `Keepsakes.Billing.Features` feature catalogue (album, photo-per-album, storage, upload-size, collaborator and custom-domain limits; premium templates, guest downloads, remove branding, guest uploads, time capsule, reactions/guestbook and slideshow music switches) with validation for plan values.
- Subscriptions: `subscriptions` (one per user) and `subscription_events`. Registration starts a 60-day trial in the same transaction; existing accounts were given a trial starting from the migration.
- Trial lifecycle (`Billing.advance/1`, hourly `Billing.LifecycleWorker` cron on the `billing` queue): reminder email a week before the trial ends, then 7 days of grace with full access, then the Free plan, each with an email and an event, and safe against double runs.
- `Keepsakes.Entitlements`: plan values read fresh on each check, `check/4` under a per-user Postgres advisory lock, and friendly over-limit messages. Album creation, uploads (photo size, photos per album, storage) are refused over the plan's limits; nothing is ever deleted when an account is over its limits.
- `/billing` (Plans & billing, also in the account menu and the sidebar): current plan and status, usage meters for storage, albums and the largest album, and Free/Plus/Pro compared in NGN or USD, monthly or yearly. Paid plan buttons say payments are coming (Stage 5b).
- Over-limit banner across the owner portal, an upgrade notice in the New album dialog when the album limit is reached, and a dismissible notice when an upload is refused for a plan limit.
- `Keepsakes.Storage.list/1` (S3 ListObjectsV2 with pagination, local disk) and `mix keepsakes.storage.clear`, which empties the configured bucket for a fresh start (asks first, never in prod, refuses buckets not named staging/dev/test without `--any-bucket`).

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
- Upload queue rows show the Ready/Needs badge above the title, so long names keep the full width.
- The album page's Share album and Preview as guest buttons are live once the album has a photo.
- Copy buttons fall back to a classic copy when the Clipboard API is missing or refused, and ask for Ctrl+C if both fail.
- The guest access, timeline and slideshow pages are drawn by the album's template renderer and themed through `ks-guest-*` colour tokens (replacing `ks-night-card`/`-line`/`-field`/`-bar` and hard-coded white), with the theme applied on the guest root layout and `color-scheme` following the template.
- The dev seed album uses the real photos in the gitignored `test_imgs/` folder when present, instead of plain colour cards.
- `test_imgs/` (local photos for manual and visual testing) is gitignored.
- The sidebar storage meter uses the plan's storage limit instead of a fixed 1 GB and shows the plan status with a link to Plans & billing.
- The upload size limit comes from the plan (Free 10 MB, Plus and Pro 25 MB); the system-wide `max_upload_mb` ceiling setting now defaults to 25.
- Daylight is a premium template. Premium templates need Plus or Pro to choose (the picker offers "Upgrade to use", the settings list marks them), and albums or defaults set to one fall back to the system default when the plan no longer includes them.
- Guest downloads need a plan with guest downloads: the Share page switch is disabled with a link to plans, and downloads stop if the plan drops them.
- "Made with Keepsake" on the guest timeline is hidden on plans with remove branding.
- Every owner-portal page (upload screen, Share, Template, Plans & billing, settings) now shows the header and album sidebar; the `sidebar={false}` option on `Layouts.app` is gone.
- The owner header sticks to the top, and the album sidebar stays in view at viewport height while the page scrolls; a long album list scrolls inside the sidebar so New album and the storage meter stay visible.
- `Scope` no longer carries unused `subscription`/`entitlements` fields; `Keepsakes.Format.bytes/1` is shared by pages and messages.

### Fixed
- The owner sidebar no longer stretches past the screen on long pages, which pushed the storage meter out of view.
- Global `body` and heading font rules moved into the base CSS layer; they were overriding utilities such as `font-hand` on headings.
- Dark mode: the soft teal/amber surfaces and muted text now have night-theme values, so selected rows, notes and badges stay readable; text on white polaroids uses fixed ink colours in both themes.

### Security
- Opening an emailed link for an unconfirmed account from a browser that isn't logged in as that account confirms it, removes any password and expires every session. This blocks someone who pre-registered another person's email from keeping access.
