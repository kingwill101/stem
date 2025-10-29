# Security Profile: HMAC (no TLS)

This variant runs the microservice example using HMAC-SHA256 message signing and a plaintext Redis connection. It is intended for local development on a trusted network.

## Usage

```bash
cd examples/security/hmac
docker compose up --build
```

Environment variables are defined in `.env`. Replace the sample `STEM_SIGNING_KEYS` value with a fresh 32-byte secret for anything beyond experimentation:

```bash
openssl rand -base64 32
```

All build contexts point back to `examples/microservice`, so changes there are automatically reflected.
