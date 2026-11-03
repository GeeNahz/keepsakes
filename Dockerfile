# Production image: an Elixir release, built in one stage and copied into a
# small Debian image with no compilers or Mix. Stage 11 builds this in CI and
# pushes it to GHCR; the VPS pulls it. Locally:
#
#   docker compose --profile release up -d --build app_release
#
# Same versions as .tool-versions and Dockerfile.dev: Erlang 29.0 and Elixir
# 1.19.5 (the OTP 26 build). libvips comes precompiled with the vix package,
# as it does in dev, so no system image libraries are needed.
ARG ERLANG_IMAGE=hexpm/erlang:29.0-debian-trixie-20260610-slim
ARG RUNNER_IMAGE=debian:trixie-20260610-slim

# --- build ------------------------------------------------------------------
FROM ${ERLANG_IMAGE} AS build

ARG ELIXIR_VERSION=1.19.5
ARG ELIXIR_OTP=26

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/elixir.zip \
      "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-${ELIXIR_OTP}.zip" \
 && unzip -q /tmp/elixir.zip -d /usr/local/elixir \
 && rm /tmp/elixir.zip

ENV PATH="/usr/local/elixir/bin:${PATH}" LANG=C.UTF-8 MIX_ENV=prod \
    HEX_HTTP_TIMEOUT=120 HEX_HTTP_CONCURRENCY=4
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

# Dependencies first, so editing app code doesn't refetch and recompile them
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# The tailwind and esbuild binaries (downloaded once, cached in this layer)
RUN mix assets.setup

COPY priv priv
COPY lib lib
COPY assets assets
# Compile first: Tailwind scans the compiled colocated hooks and templates
RUN mix compile && mix assets.deploy

# runtime.exs is read when the release starts, so it's copied last
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# --- run --------------------------------------------------------------------
FROM ${RUNNER_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 \
    MIX_ENV=prod PORT=4000

WORKDIR /app
# Local-disk photos (used when S3_BUCKET is empty) live in a volume
RUN mkdir -p /var/lib/keepsakes/uploads && chown nobody /app /var/lib/keepsakes/uploads
VOLUME /var/lib/keepsakes/uploads

COPY --from=build --chown=nobody:root /app/_build/prod/rel/keepsakes ./
USER nobody

EXPOSE 4000
# bin/server runs pending migrations, then starts the app
CMD ["/app/bin/server"]
