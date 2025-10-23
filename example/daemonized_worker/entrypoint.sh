#!/usr/bin/env bash
set -euo pipefail

NODES=${STEM_WORKER_NODES:-alpha}
PID_TEMPLATE=${STEM_WORKER_PIDFILE_TEMPLATE:-/var/run/stem/%n.pid}
LOG_TEMPLATE=${STEM_WORKER_LOGFILE_TEMPLATE:-/var/log/stem/%n.log}
WORKDIR=${STEM_WORKER_WORKDIR:-/app}
COMMAND_LINE=${STEM_WORKER_COMMAND:-"dart run examples/daemonized_worker/bin/worker.dart"}
EXTRA_OPTS=${STEM_WORKER_MULTI_OPTS:-}
STEM_CLI=${STEM_CLI_COMMAND:-"dart run bin/stem.dart"}

cleanup() {
  local stop_cmd="${STEM_CLI} worker multi stop ${NODES} --pidfile=\"${PID_TEMPLATE}\""
  bash -lc "$stop_cmd" >/dev/null 2>&1 || true
  exit 0
}

trap cleanup SIGTERM SIGINT

start_cmd="${STEM_CLI} worker multi start ${NODES} \
  --pidfile=\"${PID_TEMPLATE}\" \
  --logfile=\"${LOG_TEMPLATE}\" \
  --workdir=\"${WORKDIR}\" \
  --command-line \"${COMMAND_LINE}\" ${EXTRA_OPTS}"

bash -lc "$start_cmd"

# Keep the container alive while allowing trap handlers to execute.
while true; do sleep 3600; done
