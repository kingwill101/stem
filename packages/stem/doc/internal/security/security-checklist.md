---
title: Security Checklist
sidebar_label: Checklist
sidebar_position: 1
slug: /security/checklist
---

## Transport & Secrets

- [ ] Enforce TLS for Redis connections (`rediss://`); document certificate management.
- [ ] Store credentials in secret manager, inject via env vars (`STEM_REDIS_URL`, etc.).
- [ ] Rotate credentials quarterly; update docs when rotation occurs.

## Payload & Data Protection

- [ ] Provide optional payload signing (HMAC) guidance; stub helper in backlog.
- [ ] Recommend encrypting sensitive args before enqueue; document pattern.
- [ ] Ensure result backend TTLs comply with data retention policies.

## Access Control

- [ ] Restrict Redis ACLs: separate read/write users for workers vs. CLI.
- [ ] CLI commands requiring mutation (replay/purge) should log audit events.
- [ ] Define RBAC for future admin APIs.

## Compliance & Tooling

- [ ] Run dependency vulnerability scan (e.g., `dart pub outdated --security`).
- [ ] Document third-party licenses (Redis client, OpenTelemetry).
- [ ] Capture threat model summary in design doc.

## Incident Response

- [ ] Link to observability runbook for detection.
- [ ] Define contact rotation and escalation path.
- [ ] Record post-incident review template.
