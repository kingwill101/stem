#!/bin/sh
# Use the native viewer already downloaded by the developer. No Docker/install.
# Keep the foreground process attached: Ctrl+C stops it.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary=${OTEL_VIEWER_BIN:-"$HOME/Downloads/otel-desktop-viewer_linux_amd64/otel-desktop-viewer"}
if [ ! -x "$binary" ]; then
  echo "Set OTEL_VIEWER_BIN to your otel-desktop-viewer executable." >&2
  exit 1
fi
mkdir -p "$root/build/local-tracing"
printf 'Viewer: http://127.0.0.1:8000\n'
printf 'OTLP/gRPC: http://127.0.0.1:4317; OTLP/HTTP: http://127.0.0.1:4318\n'
printf 'Do not start a second copy if the viewer is already running.\n'
exec "$binary" \
  --host 127.0.0.1 --browser-port 8000 --grpc 4317 --http 4318 \
  --open-browser=false \
  --db "$root/build/local-tracing/traces.duckdb" --db-max-size 512MB
