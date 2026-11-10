#!/bin/sh
# Runs before the dev server starts (Dockerfile.dev): fetch any new deps and
# bring the database up to date, then hand over to the command (`mix phx.server`).
set -e

mix deps.get
mix ecto.create --quiet
mix ecto.migrate

exec "$@"
