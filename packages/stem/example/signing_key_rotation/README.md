# Signing Key Rotation Drill

This demo shows how to rotate HMAC signing keys while keeping overlapping keys
available for verification. The worker accepts both keys, while producers switch
their active signing key.

## Topology

- **Redis** – broker + result backend.
- **Worker** – verifies signatures using both keys.
- **Producer** – signs payloads with the active key (`primary` → `rotated`).

## Quick Start

```bash
cd example/signing_key_rotation
# or from repo root:
# cd packages/stem/example/signing_key_rotation

just deps-up
just build

# Terminal 1: start the worker (uses .env with both keys)
just run-worker

# Terminal 2: enqueue with the primary key
just run-producer-primary

# Rotate: enqueue again with the rotated key
just run-producer-rotated
```

The worker should process tasks from both runs without error, proving the
rotation overlap works.

## Files

- `.env` – worker config (both keys, active key = `primary`).
- `.env.primary` – producer config using the primary key.
- `.env.rotate` – producer config using the rotated key.

## Tips

- If you remove a key from `STEM_SIGNING_KEYS`, any tasks signed with that key
  will be rejected and sent to the DLQ (`reason=signature-invalid`).
- You can verify DLQ contents with `just build-cli` and `just stem dlq list`.
