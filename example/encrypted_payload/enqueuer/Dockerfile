# syntax=docker/dockerfile:1

FROM dart:stable AS dev
WORKDIR /app
COPY . .
WORKDIR /app/examples/encrypted_payload/enqueuer
RUN dart pub get
CMD ["dart", "run", "bin/enqueue.dart"]

FROM dart:stable AS build
WORKDIR /app
COPY . .
WORKDIR /app/examples/encrypted_payload/enqueuer
RUN dart pub get
RUN dart compile exe bin/enqueue.dart -o /app/build/encrypted_enqueuer

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/build/encrypted_enqueuer /app/encrypted_enqueuer
ENTRYPOINT ["/app/encrypted_enqueuer"]
