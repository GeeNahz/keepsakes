# OpenResty = nginx + LuaJIT + a set of Lua libraries, so the proxy can run
# code during a request (needed for on-demand TLS, step 4).
# "alpine-fat" includes luarocks/opm for installing Lua packages.
FROM openresty/openresty:1.29.2.3-alpine-fat

# On-demand TLS (step 4): lua-resty-acme and the two libraries it needs,
# pinned so a rebuild never picks up something new by surprise
RUN luarocks install lua-resty-http 0.18.0-0 \
 && luarocks install lua-resty-openssl 1.9.0-1 \
 && luarocks install lua-resty-acme 0.16.0-1
# Its "file" storage (certificates kept on disk, step 5) needs this to list
# the stored certificates when checking for renewals
RUN luarocks install luafilesystem 1.9.0-1

# The certificate served while a real one is being fetched (or for names we
# won't issue for). Browsers reject it; it only exists so the handshake has
# something to start with. Throwaway, made fresh in every image.
RUN apk add --no-cache openssl \
 && mkdir -p /etc/openresty/tls /var/lib/acme \
 && openssl req -x509 -nodes -days 3650 -newkey ec \
      -pkeyopt ec_paramgen_curve:prime256v1 -subj "/CN=keepsake-fallback" \
      -keyout /etc/openresty/tls/fallback.key -out /etc/openresty/tls/fallback.crt \
 && chown -R nobody /var/lib/acme

# The image's stock site (server_name localhost) would win over our
# default_server for "localhost": nginx matches names before falling back
RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/
COPY snippets/ /etc/nginx/snippets/
COPY lua/ /etc/nginx/lua/
COPY --chmod=755 entrypoint.sh /usr/local/bin/openresty-entrypoint

# Certificates and the ACME account key: a volume in compose (step 5)
VOLUME /var/lib/acme

# Setting ENTRYPOINT clears the base image's CMD, so it's repeated here
ENTRYPOINT ["openresty-entrypoint"]
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
