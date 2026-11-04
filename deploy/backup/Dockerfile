# Nightly backups: Postgres dumps, the edge's certificates, local-disk
# photos, and a copy of each media bucket, encrypted with age and stored in
# R2 by rclone. Built on the same Postgres image as the database, so
# pg_dump and pg_restore always match the server's version.
#
# Runs schedule.sh (sleeps until BACKUP_AT, backs up, repeats). By hand,
# on the server: bin/backup now | list | drill (deploy/server/bin/backup).
FROM postgres:18.4

RUN apt-get update \
 && apt-get install -y --no-install-recommends age rclone curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 schedule.sh backup.sh restore.sh /usr/local/bin/

# rclone is configured entirely from RCLONE_CONFIG_* variables; an empty
# config path means "no config file" (otherwise it notes the missing file
# on every call)
ENV RCLONE_CONFIG=""

# Clears the Postgres image's entrypoint: this container never runs a server
ENTRYPOINT []
CMD ["schedule.sh"]
