#!/bin/sh
set -eu

# The host-mounted fixture keys remain owner-only. Copy them into the
# container's private temporary filesystem so Redis can use them after it
# drops privileges from the root bootstrap user.
source_dir=/etc/redis/certs
runtime_dir=/tmp/stem-redis-certs

if [ "$(id -u)" -ne 0 ]; then
  echo 'The Redis TLS test entrypoint must start as root.' >&2
  exit 1
fi

mkdir -p "$runtime_dir"
for asset in "$source_dir"/*.crt "$source_dir"/*.key; do
  if [ -f "$asset" ]; then
    cp "$asset" "$runtime_dir/"
  fi
done

chown redis:redis "$runtime_dir"
chown redis:redis "$runtime_dir"/*
chmod 755 "$runtime_dir"
for asset in "$runtime_dir"/*.crt; do
  if [ -f "$asset" ]; then
    chmod 644 "$asset"
  fi
done
for asset in "$runtime_dir"/*.key; do
  if [ -f "$asset" ]; then
    chmod 600 "$asset"
  fi
done

if [ "$#" -eq 0 ]; then
  set -- redis-server
fi

exec /usr/bin/setpriv --reuid redis --regid redis --clear-groups "$@"
