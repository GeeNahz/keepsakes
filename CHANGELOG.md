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
- Card payments through Flutterwave v3 (`FLW_PUBLIC_KEY`, `FLW_SECRET_KEY`, `FLW_ENCRYPTION_KEY`, `FLW_SECRET_HASH` in `.env.example`): a `Keepsakes.Billing.Gateway` behaviour with `Gateways.Flutterwave` for hosted card checkout, transaction verification (by ID or reference), saved-card charges, refunds and webhook checks.
- `invoices` (sequential `KS-000001` numbers, subtotal, credit and amount, paid period), `payments` (one per collection attempt, unique `tx_ref`), `payment_methods` (one card per user, token encrypted with Cloak) and `payment_events` (webhooks stored once by gateway event ID); subscriptions gain `pending_price_id`, `retry_count` and `next_retry_at`.
- Choosing a plan on `/billing` shows what it means before paying: paying during the trial keeps the remaining trial days; upgrades (a higher plan, or monthly to yearly) start now with unused paid days credited in whole naira/dollars; downgrades and currency changes are booked for the next renewal and can be dropped ("Keep my current plan").
- `GET /billing/return` confirms the payment with Flutterwave before applying it (amount and currency checked, applied exactly once), saves the card and emails a receipt; a cancelled checkout voids its invoice.
- `POST /webhooks/flutterwave` checks `verif-hash`, stores the event once and confirms the payment in a background job (`Billing.WebhookWorker`).
- Renewals in the hourly billing run: the saved card is charged at the end of each period; a failed charge makes the plan `past_due` with full access and is retried 1, 3 and 5 days after the first failure (with emails), then 7 days of grace, then Free. Payments left pending are re-checked after 15 minutes and given up after a day. Cancelled plans move to Free when the paid period ends.
- Plans & billing shows price, renewal or end date, card on file, Cancel plan / Keep my plan, Pay now after a failed renewal, a booked change, and an invoice list; receipts at `/billing/invoices/:id` with Print.
- Emails: receipt, renewal payment failed, and plan about to end after failed retries.
- Discount codes: `discount_codes` (code, percent off, `once`/`repeating` for N months/`forever`, usage cap, expiry, plan limits, on/off) and `discount_redemptions` (one per user per code, terms copied when used); subscriptions carry the discount in use and invoices record `discount_minor` and a label such as "LAUNCH20 · 20% off".
- "Have a code?" in the plan dialog on Plans & billing: codes are matched in any case, explain why they can't be used (invalid, expired, used up, wrong plan, already used), take their share off in whole naira/dollars before any upgrade credit, are checked again at payment, and keep applying at renewals while they last. 100% codes are refused for card plans.
- `mix keepsakes.discount.create CODE --percent N --duration once|repeating|forever [--months N --max N --expires YYYY-MM-DD --plans plus,pro --description ...]` (and `Keepsakes.Billing.Discounts.create_code/1` for releases) until the admin portal exists.
- Referrals: every user has an invite code (`users.referral_code`; existing accounts were given one) and signing up through `/auth/register?ref=CODE` records who invited them. When an invited person first pays, their inviter gets a free month: added to their current paid period, or banked and added to their first paid period while on the trial or Free. Once per invited person, with an email.
- "Invite friends, get a free month" card on Plans & billing with the invite link, a copy button, and joined / months earned / waiting counts; the active discount shows with the plan details; receipts and receipt emails list the discount.
- Settings area under `/app/settings` with a tab list (a scrolling row on phones that brings the current tab into view): Profile, Account, Security, Notifications, Sharing defaults, Templates, Billing, Referrals, Domains, Data & privacy; `/app/settings` opens Profile.
- Profile tab: name, a short bio (`users.bio`) and a profile photo, cropped to a 256 px square WebP in storage; it replaces the initials in the account menu.
- Security tab: optional two-step login with an authenticator app (TOTP secret encrypted with Cloak, QR code and typed key, 10 single-use recovery codes stored hashed, regenerate or turn off with a code), and signed-in devices (browser, address and date per session, with Sign out and Sign out all other devices); sessions now record their user agent and IP.
- `/auth/two-step` after a correct password or sign-in link for accounts with two-step login (6 tries per 15 minutes), and `/auth/restore` for accounts paused for deletion.
- Notifications tab: guest activity, billing reminders and product news switches (`users.notify_*`). A daily email (07:15 Lagos time) lists which shared albums were opened since the last one; billing reminders cover the trial-ending email and a new heads-up three days before a paid plan renews.
- Sharing defaults tab: code mode, link expiry, first view, captions and downloads used for every new share link.
- Referrals tab with the invite link and counts (moved from Plans & billing); Domains tab placeholder ("Coming soon").
- Data & privacy tab: "Export everything" builds a zip of every album's photos (2400 px) and an `album.json` of their details in the background, emails a link valid for 7 days (`/app/settings/privacy/exports/:id`) and updates the page when ready (`data_exports` table). "Delete account" (type your email to confirm) signs out everywhere, stops shared links and renewals, emails the deletion date, and deletes everything for good after 14 days unless restored at login.
- Daily `HousekeepingWorker` cron: guest activity emails, removing expired exports, deleting accounts past their 14-day pause.
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
- Account settings moved into tabs: email and password at `/app/settings/account` (email confirmation links now `/app/settings/account/confirm-email/:token`, password form posts to `/app/settings/account/update-password`), the template for new albums at `/app/settings/templates`, and Plans & billing at `/app/settings/billing` (receipts at `/app/settings/billing/invoices/:id`); `/app/billing` redirects there and emails link to the new paths.
- Changing your password no longer asks for a two-step code again, since you're already signed in.
- The owner portal moved under `/app`: `/app/albums/...`, `/app/billing/...` (including the Flutterwave return page `/app/billing/return`), `/app/settings` (was `/users/settings`), `/app/settings/update-password` and `/app/confirm-email/resend`; `/app` on its own opens the album list.
- Sign-in pages moved under `/auth`: `/auth/register`, `/auth/log-in`, `/auth/log-in/:token`, `/auth/reset-password` and `/auth/log-out` (were under `/users`). The landing page (`/`), guest links (`/a/...`), webhooks and media URLs are unchanged.
- Every owner-portal page (upload screen, Share, Template, Plans & billing, settings) now shows the header and album sidebar; the `sidebar={false}` option on `Layouts.app` is gone.
- The owner header sticks to the top, and the album sidebar stays in view at viewport height while the page scrolls; a long album list scrolls inside the sidebar so New album and the storage meter stay visible.
- `Scope` no longer carries unused `subscription`/`entitlements` fields; `Keepsakes.Format.bytes/1` is shared by pages and messages.

### Fixed
- The owner sidebar no longer stretches past the screen on long pages, which pushed the storage meter out of view.
- Global `body` and heading font rules moved into the base CSS layer; they were overriding utilities such as `font-hand` on headings.
- Dark mode: the soft teal/amber surfaces and muted text now have night-theme values, so selected rows, notes and badges stay readable; text on white polaroids uses fixed ink colours in both themes.

### Security
- Opening an emailed link for an unconfirmed account from a browser that isn't logged in as that account confirms it, removes any password and expires every session. This blocks someone who pre-registered another person's email from keeping access.
