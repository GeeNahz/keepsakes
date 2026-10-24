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
- Core components `logo`, `avatar`, `badge`, `meter` and `modal`, plus `primary`/`secondary`/`outline`/`ghost`/`danger` button variants.
- Dev-only component gallery at `/dev/components`.
- GitHub Actions CI workflow running `mix precommit` against Postgres 18 on every push and pull request.

### Changed
- Migrations default to UUID primary keys, UUID foreign keys and `utc_datetime` timestamps via `migration_primary_key` / `migration_foreign_key` Repo config.
- AGENTS.md now prefers daisyUI components themed with the Keepsake themes instead of forbidding daisyUI.
- Interim app layout uses the Keepsake logo and theme toggle in place of the Phoenix scaffold header.
