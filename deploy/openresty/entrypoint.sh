#!/bin/sh
# Prepares the certs volume and the CA list, then starts OpenResty.
set -e

# The ACME account key: made once and kept in the certs volume, so restarts
# and reloads stay the same account (a new account per reload would run
# into Let's Encrypt's account rate limit). It must be RSA: lua-resty-acme
# only knows how to sign ACME requests with RSA account keys (certificate
# keys can still be EC, see domain_key_types in nginx.conf).
mkdir -p /var/lib/acme/certs
if [ ! -f /var/lib/acme/account.key ]; then
  openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
    -out /var/lib/acme/account.key
fi
chmod 600 /var/lib/acme/account.key
# Workers run as "nobody" and write the certificates
chown -R nobody /var/lib/acme

# CAs Lua trusts for the ACME server: the system list plus any extra roots
# mounted into /etc/openresty/extra-ca (Pebble's test root, locally)
cat /etc/ssl/certs/ca-certificates.crt > /etc/openresty/tls/trusted.pem
for ca in /etc/openresty/extra-ca/*.pem; do
  [ -f "$ca" ] && cat "$ca" >> /etc/openresty/tls/trusted.pem
done

# Which app each hostname goes to: $app_backend for nginx (Lua reads the
# same variables, lua/keepsake/backends.lua). Hostnames in STAGING_HOSTS go
# to STAGING_UPSTREAM, everything else to APP_UPSTREAM.
APP_UPSTREAM="${APP_UPSTREAM:-app:4100}"
if [ -n "${STAGING_HOSTS:-}" ] && [ -z "${STAGING_UPSTREAM:-}" ]; then
  echo "STAGING_HOSTS is set but STAGING_UPSTREAM isn't" >&2
  exit 1
fi
mkdir -p /etc/openresty/generated
{
  echo "map \$host \$app_backend {"
  echo "  hostnames;"
  echo "  default $APP_UPSTREAM;"
  for host in ${STAGING_HOSTS:-}; do
    echo "  $host $STAGING_UPSTREAM;"
  done
  echo "}"
} > /etc/openresty/generated/upstream.conf

exec "$@"
