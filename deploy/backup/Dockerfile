# Nightly backups: Postgres dumps, the edge's certificates, local-disk
# photos, and a copy of each media bucket, encrypted with age and stored in
# R2 by rclone. Built on the same Postgres image as the database, so
# pg_dump and pg_restore always match the server's version.
#
# Runs schedule.sh (sleeps until BACKUP_AT, backs up, repeats). By hand,
# on the server: bin/backup now | list | drill (deploy/server/bin/backup).
FROM postgres:18.4

RUN apt-get update \
 && apt-get install -y --no-install-recommends age curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# rclone from its own releases, not Debian's package: Debian ships 1.60
# (2022), which R2 answers with "501 Not Implemented" on every first
# upload. Pinned, and checked against the release's SHA256SUMS.
ARG RCLONE_VERSION=1.76.0
ARG TARGETARCH
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      amd64) sum=b00f00b3266c3764413afe599d3ec316f6f43b3e0ea8a0bc1d186d2133e46df7 ;; \
      arm64) sum=ee169016675e23a69d77240565133ff7dbc9b33d16fa8f7053d4af39f1eaeb78 ;; \
      *) echo "no rclone checksum for ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip; \
    zip="rclone-v${RCLONE_VERSION}-linux-${TARGETARCH:-amd64}"; \
    curl -fsSLo /tmp/rclone.zip "https://downloads.rclone.org/v${RCLONE_VERSION}/${zip}.zip"; \
    echo "${sum}  /tmp/rclone.zip" | sha256sum -c -; \
    unzip -q /tmp/rclone.zip -d /tmp; \
    install -m 755 "/tmp/${zip}/rclone" /usr/local/bin/rclone; \
    rm -rf /tmp/rclone.zip "/tmp/${zip}"; \
    apt-get purge -y unzip; \
    rm -rf /var/lib/apt/lists/*; \
    rclone version | head -1

COPY --chmod=755 schedule.sh backup.sh restore.sh /usr/local/bin/

# rclone is configured entirely from RCLONE_CONFIG_* variables; an empty
# config path means "no config file" (otherwise it notes the missing file
# on every call)
ENV RCLONE_CONFIG=""

# Clears the Postgres image's entrypoint: this container never runs a server
ENTRYPOINT []
CMD ["schedule.sh"]
