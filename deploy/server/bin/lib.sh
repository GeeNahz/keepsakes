#!/usr/bin/env bash
# Shared by the scripts in bin/. Not run on its own.
#
# The server's layout (DEPLOYMENT.md, Part 2):
#   /srv/keepsakes/deploy/       this folder, copied from the repo on every deploy
#   /srv/keepsakes/infra/.env    edge, Postgres and backup settings
#   /srv/keepsakes/production/.env, /srv/keepsakes/staging/.env
#                                each app's settings
#   <env>/.deployed, .previous   the image tag running now, and the one before
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEPLOY_DIR
KS_ROOT="${KS_ROOT:-$(dirname "$DEPLOY_DIR")}"
export KS_ROOT
export KS_REGISTRY="${KS_REGISTRY:-ghcr.io/geenahz}"

die() {
  echo "error: $*" >&2
  exit 1
}

say() {
  echo "==> $*"
}

valid_env() {
  case "${1:-}" in
    production | staging) ;;
    *) die "environment must be production or staging (got '${1:-}')" ;;
  esac
}

valid_tag() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.-]{1,128}$ ]] || die "not an image tag: '${1:-}'"
}

# docker compose for the shared services (compose.infra.yaml)
infra() {
  [ -f "$KS_ROOT/infra/.env" ] || die "missing $KS_ROOT/infra/.env (see env/infra.env.example)"
  local tag_file="$KS_ROOT/infra/.deployed"
  export INFRA_TAG="${INFRA_TAG:-$(cat "$tag_file" 2>/dev/null || true)}"
  [ -n "$INFRA_TAG" ] || die "no infra tag yet: run bin/infra-up <tag> first"

  local options=()
  [ -f "$KS_ROOT/infra/.metrics-on" ] && options+=(--profile metrics)
  # This server's own additions, kept with its settings (never in the repo)
  [ -f "$KS_ROOT/infra/compose.override.yaml" ] && options+=(-f "$KS_ROOT/infra/compose.override.yaml")

  docker compose -p ks-infra \
    --project-directory "$DEPLOY_DIR" \
    -f "$DEPLOY_DIR/compose.infra.yaml" \
    --env-file "$KS_ROOT/infra/.env" \
    "${options[@]}" "$@"
}

# docker compose for one environment's app: app_compose <env> <args...>
# (IMAGE_TAG must be set for commands that create containers)
app_compose() {
  local env="$1"
  shift
  [ -f "$KS_ROOT/$env/.env" ] || die "missing $KS_ROOT/$env/.env (see env/$env.env.example)"
  KS_ENV="$env" IMAGE_TAG="${IMAGE_TAG:-$(cat "$KS_ROOT/$env/.deployed" 2>/dev/null || echo none)}" \
    docker compose -p "ks-$env" \
    --project-directory "$DEPLOY_DIR" \
    -f "$DEPLOY_DIR/compose.app.yaml" \
    "$@"
}

# Waits until a container's health check passes. Fails early if it turns
# unhealthy or stops. wait_healthy <container id> <seconds>
wait_healthy() {
  local id="$1" timeout="$2" waited=0 status
  while [ "$waited" -lt "$timeout" ]; do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || echo gone)"
    case "$status" in
      healthy) return 0 ;;
      unhealthy | exited | dead | gone) return 1 ;;
    esac
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}
