# Encrypted Payload Example

This example shows how to encrypt task payloads before they leave the producer
and decrypt them inside the worker. It uses AES-GCM with a shared symmetric key
stored in the `PAYLOAD_SECRET` environment variable.

## Docker Compose quick start

1. Copy the environment template and adjust as needed (the default secret is
   for demo purposes only):

   ```bash
   cp .env.example .env
   ```

2. Start Redis, the encrypted worker, and the enqueuer:

   ```bash
   docker compose up --build worker enqueuer
   ```

   The enqueuer publishes three encrypted jobs and exits. The worker decrypts
   each payload, generates a report, and stores the result.

3. Shut everything down:

   ```bash
   docker compose down
   ```

## Manual workflow

1. Start Redis:

   ```bash
   docker compose up redis -d
   ```

2. Export environment variables (generate your own 32-byte base64 secret for
   anything beyond local testing):

   ```bash
   export STEM_BROKER_URL=redis://127.0.0.1:6379/0
   export STEM_RESULT_BACKEND_URL=redis://127.0.0.1:6379/1
   export STEM_DEFAULT_QUEUE=secure
   export PAYLOAD_SECRET=$(openssl rand -base64 32)
   ```

3. Run the worker:

   ```bash
   cd examples/encrypted_payload/worker
   dart pub get
   dart run bin/worker.dart
   ```

4. In another terminal, run the enqueuer (reuse the same environment variables):

   ```bash
   cd examples/encrypted_payload/enqueuer
   dart pub get
   dart run bin/enqueue.dart
   ```

5. Cleanup:

   ```bash
   docker compose down
   ```

## How it works

- The enqueuer serialises the report payload to JSON, encrypts it with AES-GCM,
  and Enqueues a structure containing `ciphertext`, `nonce`, and `mac`.
- The worker reconstructs the `SecretBox`, decrypts the payload, and processes
  the plain data. Any tampering results in a decryption failure and the task is
  retried or dead-lettered depending on configuration.

This pattern lets you keep sensitive customer data encrypted at rest in the
broker and result backend while still leveraging Stem’s task orchestration.

## Containerised client (`container_mixed_encrypted`)

The `docker/` directory contains a self-contained binary that encrypts payloads
and enqueues a few demo tasks. Build and run it alongside Redis:

```bash
docker compose up redis -d
dart pub get
dart compile exe examples/encrypted_payload/docker/main.dart -o build/container_mixed_encrypted
PAYLOAD_SECRET=$(openssl rand -base64 32) \
STEM_BROKER_URL=redis://127.0.0.1:6379/0 \
STEM_RESULT_BACKEND_URL=redis://127.0.0.1:6379/1 \
STEM_DEFAULT_QUEUE=secure \
./build/container_mixed_encrypted
```

To run it fully containerised:

```bash
docker build -t container_mixed_encrypted -f docker/Dockerfile .
docker run --network host \
  -e STEM_BROKER_URL=redis://127.0.0.1:6379/0 \
  -e STEM_RESULT_BACKEND_URL=redis://127.0.0.1:6379/1 \
  -e STEM_DEFAULT_QUEUE=secure \
  -e PAYLOAD_SECRET=$(openssl rand -base64 32) \
  container_mixed_encrypted
```

### Local build + Docker deps (just)

By default the Justfile loads `.env`. To use the sample settings, either copy `.env.example` to `.env` or pass `ENV_FILE=.env.example` and update hostnames to `localhost` for local runs.

```bash
just deps-up
just build
# In separate terminals:
just run-worker
just run-enqueuer
# Or:
just tmux
```
