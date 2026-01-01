# Security Profile: HMAC + TLS

This variant mirrors `examples/microservice` but adds TLS encryption for Redis while keeping HMAC-SHA256 message signing.

## Prerequisites

Generate self-signed certificates (or provide your own) before starting:

```bash
cd examples/security/hmac_tls
../../scripts/security/generate_tls_assets.sh certs redis
```

## Usage

```bash
cd examples/security/hmac_tls
docker compose up --build
```

The `.env` file enables TLS (`rediss://`) and mounts the generated cert bundle. Rotate the shared secret with `openssl rand -base64 32` whenever you redeploy.

## Local build + Docker deps (just)

The Justfile in this directory runs the microservice binaries locally while using this profile's `.env` for configuration.

```bash
just deps-up
just build
just tmux
```
