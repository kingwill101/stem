# Security Profile: HMAC + TLS

This variant mirrors `examples/microservice` but adds TLS encryption for Redis while keeping HMAC-SHA256 message signing.

## Prerequisites

Generate self-signed certificates (or provide your own) before starting:

```bash
cd examples/security/hmac_tls
task tls:certs
```

## Usage

```bash
cd examples/security/hmac_tls
docker compose up --build
```

The `.env` file enables TLS (`rediss://`) and mounts the generated cert bundle. Rotate the shared secret with `openssl rand -base64 32` whenever you redeploy.

## Local build + Docker deps (task)

The Taskfile in this directory runs the microservice binaries locally while using this profile's `.env.local` for configuration.

```bash
task tls:certs
task keys:rotate
task deps-up
task build
# in separate terminals:
task run:worker
task run:enqueuer
```
