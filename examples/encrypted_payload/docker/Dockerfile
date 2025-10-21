# syntax=docker/dockerfile:1

FROM dart:stable
WORKDIR /app
COPY . .

RUN dart pub get
RUN dart compile exe examples/encrypted_payload/docker/main.dart -o /app/build/container_mixed_encrypted

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=0 /app/build/container_mixed_encrypted /app/container_mixed_encrypted
ENTRYPOINT ["/app/container_mixed_encrypted"]
