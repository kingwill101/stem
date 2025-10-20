# Stem Email Service Example

This example demonstrates a real-world email notification service using Stem. It enqueues email tasks asynchronously, processes them with retries, and tracks results.

## Prerequisites

- Docker and Docker Compose
- Dart 3.3+ (optional, only required for local execution)

## Configuration

Environment variables used by the services:

| Variable | Default (Docker) | Description |
| --- | --- | --- |
| `STEM_BROKER_URL` | `redis://redis:6379/0` | Redis Streams broker connection string. |
| `STEM_RESULT_BACKEND_URL` | `redis://redis:6379/1` | Redis result backend connection string. |
| `PORT` | `8082` | Port for the enqueue API. |
| `SMTP_HOST` | `mailhog` | SMTP host address. |
| `SMTP_PORT` | `1025` | SMTP port. |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | empty | Credentials for authenticated SMTP servers. |
| `SMTP_USE_TLS` | `false` | Enable TLS if your provider requires it. |
| `SMTP_ALLOW_INSECURE` | `true` | Allow insecure connections (useful with MailHog). |
| `EMAIL_FROM_ADDRESS` | `noreply@example.com` | Sender email address. |
| `EMAIL_FROM_NAME` | `Stem Email Service` | Sender display name. |

Copy `.env.example` to `.env` before running with Docker and adjust values as needed.

## Running with Docker Compose

```bash
cd examples/email_service
cp .env.example .env # optional override
docker compose up --build
```

Services started:

- Redis (task broker + result backend)
- MailHog (SMTP capture + web UI at http://localhost:8025)
- Email enqueue API (`http://localhost:8082`)
- Email worker

Send a test email:

```bash
curl -X POST http://localhost:8082/send-email \
  -H 'content-type: application/json' \
  -d '{"to": "recipient@example.com", "subject": "Test Email", "body": "Hello from Stem!"}'
```

Inspect the message via the MailHog UI.

Stop the stack with `docker compose down`.

## Running locally with Dart

1. Start Redis and MailHog:

   ```bash
   docker compose up -d redis mailhog
   ```

2. Export or set the environment variables (matching `.env.example`).

3. Run the worker:

   ```bash
   dart pub get
   dart run bin/worker.dart
   ```

4. In another terminal, run the enqueue API:

   ```bash
   dart run bin/enqueuer.dart
   ```

5. Send email tasks using the curl command above.

This setup demonstrates how to integrate Stem with external I/O, retries, and a result backend while using MailHog as a development-friendly SMTP server.
