---
title: Prepare for Production
sidebar_label: Production Checklist
sidebar_position: 5
slug: /getting-started/production-checklist
---

You have Stem running with observability and operations tooling. This final
step hardens the deployment: signing, TLS, daemon supervision, and automated
quality gates so every rollout is repeatable.

## 1. Sign Payloads and Rotate Keys

Enable signing for producers and workers to detect tampering:

```bash
export STEM_SIGNING_ALGORITHM=hmac-sha256
export STEM_SIGNING_KEYS="v1:$(openssl rand -base64 32)"
export STEM_SIGNING_ACTIVE_KEY=v1
```

In code, wire the signer into both producers and workers:

```dart title="lib/bootstrap_signing.dart"
final config = StemConfig.fromEnvironment();
final signer = PayloadSigner.maybe(config.signing);

final stem = Stem(
  broker: broker,
  backend: backend,
  registry: registry,
  signer: signer,
);

final worker = Worker(
  broker: broker,
  backend: backend,
  registry: registry,
  signer: signer,
  // ... other dependencies ...
);
```

When you rotate keys, set `STEM_SIGNING_KEYS` to include both the old and new
entries, update `STEM_SIGNING_ACTIVE_KEY` with the new identifier, then deploy
workers. Stem will accept signatures from any configured key until you remove
retired entries.

## 2. Secure Connections with TLS

Use the repo’s helper script to generate local certificates or plug in the ones
issued by your platform:

```bash
scripts/security/generate_tls_assets.sh --out tmp/tls

export STEM_TLS_CA_CERT=$PWD/tmp/tls/ca.pem
export STEM_TLS_CLIENT_CERT=$PWD/tmp/tls/client.pem
export STEM_TLS_CLIENT_KEY=$PWD/tmp/tls/client-key.pem
```

Any TLS handshake issues surface actionable logs; temporarily set
`STEM_TLS_ALLOW_INSECURE=true` only while debugging.

Update Redis/Postgres URLs to include TLS if required (for example,
`rediss://host:port`).

## 3. Supervise Processes with Managed Services

Stem ships ready-to-use templates under `templates/systemd/` and
`templates/sysv/`. Drop in environment files with your Stem variables and
enable the services:

```bash
sudo cp templates/systemd/stem-worker@.service /etc/systemd/system/
sudo systemctl enable stem-worker@default.service
sudo systemctl start stem-worker@default.service

sudo systemctl enable stem-scheduler.service
sudo systemctl start stem-scheduler.service
```

For bare-metal or container images, the CLI can manage multiple instances with
templated PID/log locations:

```bash
stem worker multi start web-1 web-2 \
  --command "/usr/bin/dart run bin/worker.dart" \
  --pidfile /var/run/stem/%n.pid \
  --logfile /var/log/stem/%n.log \
  --env-file /etc/stem/worker.env
```

Verify health from your orchestration probes:

```bash
stem worker healthcheck --node web-1 --json
stem worker diagnose --node web-1 \
  --pidfile /var/run/stem/web-1.pid \
  --logfile /var/log/stem/web-1.log
```

## 4. Final Pre-Flight Checklist

Before every deployment run through these guardrails:

- **Quality gates** – execute `tool/quality/run_quality_checks.sh` to run
  format, analyze, unit/integration tests, chaos suites, and coverage targets.
- **Observability** – confirm Grafana dashboards (task success rate, latency
  p95, queue depth) and OpenTelemetry exporters are healthy.
- **Routing & schedules** – `stem routing dump --json` to confirm the active
  configuration and `stem schedule dry-run` for all modified entries.
- **DLQ hygiene** – ensure dead letters are empty or triaged with `stem dlq list`.
- **Control plane** – dry-run worker commands (`stem worker ping`, 
  `stem worker stats`) against staging to verify access.

Document the results in your team’s runbook (see
`docs/process/observability-runbook.md` and `docs/process/scheduler-parity.md`)
so the production checklist stays auditable.

## 5. Where to Go Next

- Deep-dive into the [Core Concepts](../core-concepts/index.md) section for
  everything you saw at a higher level.
- Explore the [Workers](../workers/index.md) and
  [Scheduler](../scheduler/index.md) docs for advanced tuning.
- If you’re planning larger architecture changes, follow the OpenSpec workflow
  documented in `openspec/AGENTS.md`.
