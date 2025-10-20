# Security Configuration Examples

This guide demonstrates a few ready-to-run combinations for the microservice example so you can choose the level of protection that matches your environment.

Each scenario assumes you are in `examples/microservice/`.

## 1. HMAC-SHA256 without TLS

**Use file:** `.env.hmac`

```bash
cp .env.hmac .env
# Replace the sample secret with your own 32-byte base64 string
openssl rand -base64 32
```

Start the stack:

```bash
docker compose up --build
```

This uses the default HMAC-based signing and plain-text Redis connections. Suitable for local development when traffic never leaves a trusted network segment.

## 2. HMAC-SHA256 with TLS-enabled Redis

**Use file:** `.env.hmac_tls`

1. Generate certificates (only once):

   ```bash
   ../../scripts/security/generate_tls_assets.sh certs redis
   ```
2. Copy the environment file and adjust secrets if needed:

   ```bash
   cp .env.hmac_tls .env
   openssl rand -base64 32 # replace STEM_SIGNING_KEYS value
   ```
3. Launch the stack:

   ```bash
   docker compose up --build
   ```

Redis listens on TLS only and workers sign messages with the shared secret.

## 3. Ed25519 Signing + TLS-enabled Redis

**Use file:** `.env.ed25519_tls`

1. Generate a new Ed25519 keypair:

   ```bash
   dart run ../../scripts/security/generate_ed25519_keys.dart
   ```
   Copy the output into `.env.ed25519_tls` replacing the existing placeholder values.

2. Generate TLS assets if you have not already:

   ```bash
   ../../scripts/security/generate_tls_assets.sh certs redis
   ```

3. Copy the environment file and start the stack:

   ```bash
   cp .env.ed25519_tls .env
   docker compose up --build
   ```

Workers now verify signatures using the public key while producers sign with the private key. Redis traffic is wrapped in TLS.

---

Refer back to the [Security Runbook](security-runbook.md) for key rotation procedures and additional operational guidance.
