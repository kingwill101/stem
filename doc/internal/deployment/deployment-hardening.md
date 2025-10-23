---
title: Deployment Hardening
sidebar_label: Hardening
sidebar_position: 2
slug: /deployment/hardening
---

This checklist captures production-ready defaults for Stem services—producers,
workers, beat, and the supporting Redis infrastructure.

## Configuration & secrets

- Load secrets via your platform's secret manager (AWS Secrets Manager, Vault,
  Kubernetes Secrets, etc.). Inject `STEM_SIGNING_*` and `STEM_TLS_*` at process
  start rather than storing them in dotfiles.
- Rotate signing keys regularly. Keep both the retiring and the new key in
  `STEM_SIGNING_KEYS` during rollout, update `STEM_SIGNING_ACTIVE_KEY` last, then
  drop the old entry once workers report zero verification failures.
- Store TLS assets (server/client certs) in a dedicated secrets store; mount
  them read-only in containers.

## Redis hardening

- Run Redis with TLS enabled and `tls-auth-clients yes`.
- Set resource limits (`maxmemory`, eviction policies) to prevent unbounded
  growth. Monitor `used_memory` and `connected_clients`.
- Enable persistence (AOF or RDB) if you rely on durability, or disable it for
  purely transient broker use.
- Configure authentication (`requirepass`) even with TLS to guard against
  accidental plaintext connections.

## Service readiness & health

- Producers: expose a lightweight readiness endpoint that validates the broker
  connection (e.g., ping Redis or run a no-op `Stem.enqueue` on startup).
- Workers: report liveness/heartbeat metrics (`stem.worker.heartbeat.missed`) and
  provide a `/healthz` that checks the broker connection plus isolate pool
  status.
- Beat: ensure schedules can load by running `stem schedule list` (or dry-run)
  on boot and fail fast if the store is unreachable.

## Logging & observability

- Ship `stemLogger` output to your centralized log platform (Loki, ELK, etc.).
- Capture metrics (`stem.tasks.*`, `stem.scheduler.*`, DLQ depth) and create
  dashboards for throughput, retry/failure rates, and schedule lag.
- Turn on tracing (`StemTracer`) if you need end-to-end visibility from
  producers to handlers; export to OTLP-compatible backends (Jaeger, Tempo).

## Deployment strategy

- Use rolling deployments with a small surge to avoid draining the queue (e.g.,
  upgrade workers gradually while keeping enough capacity online).
- Quiesce workers gracefully: call `worker.shutdown()` which drains in-flight
  tasks and returns them to the broker if necessary.
- For beat, run at least two replicas with the same lock store to avoid missed
  schedules. Deploy them in separate failure domains.
- After upgrades, check:
  - `stem observe metrics` (look for spikes in `stem.tasks.failed`)
  - `stem observe groups --id <chordId>` for critical workflows
  - Redis INFO (`redis-cli --tls INFO`) for memory/latency changes

## Disaster recovery

- Back up the schedule store and result backend regularly (if persistent).
- Document failover procedures: how to promote standby Redis instances, replay
  DLQ entries, and reseed schedules.
- Practice chaos scenarios (kill workers mid-task, expire TLS certs) in staging
  to verify the observability and recovery guides.

Use this checklist alongside the [Observability & Recovery](recovery-guide.md)
page to ensure your deployment is resilient and easy to operate.
