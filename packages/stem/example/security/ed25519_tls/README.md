# Security Profile: Ed25519 + TLS

This profile turns on Ed25519 public/private key signing in addition to TLS-encrypted Redis traffic.

## Generate Keys & Certificates

```bash
cd examples/security/ed25519_tls
# Produce a new Ed25519 key pair
task keys:ed25519

# Generate TLS certificates if needed
task tls:certs
```

## Usage

```bash
cd examples/security/ed25519_tls
docker compose up --build
```

Workers trust the public key(s) defined in `.env`, while the enqueuer signs with the private key. Rotate keys periodically following the security runbook.

## Local build + Docker deps (task)

The Taskfile in this directory runs the microservice binaries locally while using this profile's `.env.local` for configuration.

```bash
task tls:certs
task keys:ed25519
task deps-up
task build
# in separate terminals:
task run:worker
task run:enqueuer
```
