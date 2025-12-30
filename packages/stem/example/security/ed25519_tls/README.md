# Security Profile: Ed25519 + TLS

This profile turns on Ed25519 public/private key signing in addition to TLS-encrypted Redis traffic.

## Generate Keys & Certificates

```bash
cd examples/security/ed25519_tls
# Produce a new Ed25519 key pair
dart run ../../scripts/security/generate_ed25519_keys.dart
# Update .env with the printed values

# Generate TLS certificates if needed
../../scripts/security/generate_tls_assets.sh certs redis
```

## Usage

```bash
cd examples/security/ed25519_tls
docker compose up --build
```

Workers trust the public key(s) defined in `.env`, while the enqueuer signs with the private key. Rotate keys periodically following the security runbook.

## Local build + Docker deps (just)

The Justfile in this directory runs the microservice binaries locally while using this profile's `.env` for configuration.

```bash
just deps-up
just build
just tmux
```
