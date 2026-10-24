# Accounts & credentials

Every third-party account Keepsake needs, how to set it up, and which
environment variables it fills. Secrets live only in `.env` files (local)
and the server's `chmod 600` env files (staging/production), never in git.
`.env.example` lists every variable.

## Production-readiness checklist (per stage)

Tick a stage off only when its accounts exist and its variables are set in
**both** the staging and the production env files.

| Stage | Needs | Variables | Verify with |
|---|---|---|---|
| 0 Foundation | nothing external | `SECRET_KEY_BASE`, `CLOAK_KEY`, `DATABASE_URL` | app boots |
| 1 Accounts | Resend | `RESEND_API_KEY`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` | register a user, confirmation email arrives |
| 2 Albums & uploads | Cloudflare R2 | `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, optional `GEOCODER` | `mix keepsakes.storage.check` (or `bin/keepsakes eval "Keepsakes.Release.storage_check()"` in a release) |
| 5 Billing | Flutterwave | added in Stage 5 | sandbox checkout |
| 8 Domains | Namecheap DNS (`edge.` record) | added in Stage 8 | `curl --resolve` |
| 11 Deploy | DigitalOcean, GitHub secrets, UptimeRobot | added in Stage 11 | staging pipeline green |

---

## Cloudflare R2 (photo storage) — Stage 2

Only the R2 product is used. **Do not add your domain to Cloudflare or
change nameservers**: DNS stays at Namecheap and the Resend records are
untouched. Photos are private and served through short-lived signed URLs,
so no public bucket, `r2.dev` subdomain or custom domain is needed.

1. **Account.** Sign up at <https://dash.cloudflare.com>, verify the email.
2. **Enable R2.** Sidebar → *R2 Object Storage*. A payment method is
   required, but the free tier (10 GB storage, 1M writes and 10M reads a
   month, free egress) keeps the bill at $0.
3. **Account ID.** Copy it from the R2 overview page.
4. **Buckets.** *Create bucket*, location *Automatic*, class *Standard*,
   public access **off**:

   | Bucket | Used by |
   |---|---|
   | `keepsakes-media` | production |
   | `keepsakes-media-staging` | staging **and local development** |
   | `keepsakes-backups` | nightly DB + media backups (Stage 11) |

5. **API tokens.** R2 overview → *Manage R2 API Tokens* → *Create API
   token*, permission **Object Read & Write**, *Apply to specific buckets
   only*. Create one token per environment:
   - production token → `keepsakes-media` only
   - staging token → `keepsakes-media-staging` only (also use it locally)
   - backups token → `keepsakes-backups` only (Stage 11)

   The **Secret Access Key is shown once**; store it in your password
   manager immediately.
6. **Variables.**

   ```sh
   S3_BUCKET=keepsakes-media-staging      # keepsakes-media in production
   S3_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
   S3_REGION=auto
   S3_ACCESS_KEY_ID=<Access Key ID>
   S3_SECRET_ACCESS_KEY=<Secret Access Key>
   ```

   Leave `S3_BUCKET` empty to use local disk instead (`LOCAL_UPLOADS_DIR`).
   Never put the production token on a laptop.
7. **Verify.** `mix keepsakes.storage.check` writes, reads, signs a URL
   for, fetches and deletes a small test object, printing each step.
8. **CORS.** Not needed: uploads go through the app, and browsers only
   `GET` signed URLs in `<img>` tags.

### Place auto-fill (`GEOCODER`)

When a photo has GPS data, its coordinates are turned into a place name
("Ikeja, Lagos") with OpenStreetMap Nominatim: free, no account, max one
request per second. The coordinates are sent to Nominatim; the stored
photo never keeps them. Set `GEOCODER=none` to switch this off.

---

## Resend (email) — Stage 1

The sending domain is already verified on Namecheap DNS. Leave those
records as they are.

1. <https://resend.com> → *API Keys* → *Create API key*, permission
   **Sending access**, restricted to your domain. Copy it once.
2. Variables:

   ```sh
   RESEND_API_KEY=re_...
   MAIL_FROM_ADDRESS=hello@yourdomain.com   # must be on the verified domain
   MAIL_FROM_NAME=Keepsake
   MAIL_DELIVERY=                           # usually leave empty, see below
   ```

3. `MAIL_DELIVERY` picks the mail adapter:

   | Value | Behaviour | Default in |
   |---|---|---|
   | `local` | nothing leaves the machine; emails appear at `/dev/mailbox` | dev |
   | `resend` | sent for real through Resend | prod |

   Leave it empty everywhere. Set `MAIL_DELIVERY=resend` in your local
   `.env` only to test real delivery from your machine.
4. Optional: add the DMARC TXT record if Resend shows it as missing.

---

## Later stages

Filled in when the stage arrives.

- **Flutterwave** (Stage 5): test keys, webhook URL + secret hash, card
  tokenization, NGN + USD, go-live KYC.
- **Namecheap DNS** (Stages 8/11): `@`, `admin`, `staging`, `edge` A records.
- **DigitalOcean** (Stage 11): SSH key, Ubuntu 24.04 droplet, cloud firewall.
- **GitHub** (Stage 11): deploy secrets, GHCR.
- **UptimeRobot** (Stage 11, optional): `/healthz` monitors.
