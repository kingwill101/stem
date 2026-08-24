#!/usr/bin/env bash
set -euo pipefail

# Integration TLS assets are disposable fixtures. Keep them out of Git and
# regenerate them before Docker Compose starts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TLS_GENERATOR="$REPO_ROOT/packages/stem/scripts/security/generate_tls_assets.sh"
REDIS_CERT_DIR="$REPO_ROOT/packages/stem/example/microservice/certs"
POSTGRES_CERT_DIR="$SCRIPT_DIR/postgres/certs"

redis_assets=(
  "$REDIS_CERT_DIR/ca.crt"
  "$REDIS_CERT_DIR/server.crt"
  "$REDIS_CERT_DIR/server.key"
  "$REDIS_CERT_DIR/client.crt"
  "$REDIS_CERT_DIR/client.key"
)
postgres_assets=(
  "$POSTGRES_CERT_DIR/root.crt"
  "$POSTGRES_CERT_DIR/server.crt"
  "$POSTGRES_CERT_DIR/server.key"
)

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate integration TLS assets." >&2
  exit 1
fi

needs_generation=0
for asset in "${redis_assets[@]}" "${postgres_assets[@]}"; do
  if [[ ! -f "$asset" ]]; then
    needs_generation=1
    break
  fi
done

if [[ "$needs_generation" -eq 1 ]]; then
  "$TLS_GENERATOR" "$REDIS_CERT_DIR" "redis" "redis,localhost,127.0.0.1" >/dev/null

  temporary_dir="$(mktemp -d)"
  trap 'rm -rf "$temporary_dir"' EXIT
  "$TLS_GENERATOR" "$temporary_dir" "postgres" "postgres,localhost,127.0.0.1" \
    >/dev/null
  mkdir -p "$POSTGRES_CERT_DIR"
  cp "$temporary_dir/ca.crt" "$POSTGRES_CERT_DIR/root.crt"
  cp "$temporary_dir/server.crt" "$POSTGRES_CERT_DIR/server.crt"
  cp "$temporary_dir/server.key" "$POSTGRES_CERT_DIR/server.key"
  chmod 600 "$POSTGRES_CERT_DIR/server.key"
else
  echo "Reusing existing disposable TLS assets."
fi

# The certificate files are mounted into containers whose runtime user is not
# the host user that generated them. The generator's restrictive umask also
# creates the directories with mode 700, which prevents Redis from traversing
# the bind mount even when the files themselves are readable.
chmod 755 "$REDIS_CERT_DIR" "$POSTGRES_CERT_DIR"

# Redis runs as the unprivileged `redis` user inside the test container. These
# assets are disposable, ignored fixtures, so make the mounted Redis files
# readable by that user while leaving the general TLS generator restrictive.
chmod 644 \
  "$REDIS_CERT_DIR/ca.crt" \
  "$REDIS_CERT_DIR/server.crt" \
  "$REDIS_CERT_DIR/server.key" \
  "$REDIS_CERT_DIR/client.crt" \
  "$REDIS_CERT_DIR/client.key"

echo "Disposable Redis and PostgreSQL TLS assets are ready."
