# Example Dockerfile showing how to run Stem workers via `stem worker multi`.
# Build from the repository root:
#   docker build -f examples/daemonized_worker/Dockerfile -t stem-multi .
# Run with:
#   docker run --rm -e STEM_WORKER_COMMAND="dart run examples/daemonized_worker/bin/worker.dart" stem-multi
FROM dart:stable

WORKDIR /app

# Copy pubspec metadata and prefetch dependencies.
COPY pubspec.* ./
RUN dart pub get

# Copy the full repository (the Docker build context should be the repo root).
COPY . /app
RUN dart pub get

# Install the Stem CLI from the local source.
COPY examples/daemonized_worker/entrypoint.sh /usr/local/bin/stem-entrypoint.sh
RUN chmod +x /usr/local/bin/stem-entrypoint.sh \
    && mkdir -p /var/log/stem /var/run/stem

# Defaults can be overridden at runtime.
ENV STEM_WORKER_COMMAND="dart run examples/daemonized_worker/bin/worker.dart"
ENV STEM_WORKER_NODES="alpha"
ENV STEM_WORKER_PIDFILE_TEMPLATE="/var/run/stem/%n.pid"
ENV STEM_WORKER_LOGFILE_TEMPLATE="/var/log/stem/%n.log"
ENV STEM_WORKER_WORKDIR="/app"

ENTRYPOINT ["/usr/local/bin/stem-entrypoint.sh"]
