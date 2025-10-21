## 1. Research & RFC
- [x] 1.1 Audit existing worker heartbeat and CLI tooling to identify integration points for control messages.
- [x] 1.2 Finalize control channel protocol (message schema, transport reuse vs new channel) and autoscaling heuristics.

## 2. Control Plane Foundation
- [x] 2.1 Implement control channel between coordinator and workers (publish/subscribe, authentication, observability).
- [x] 2.2 Expose CLI commands (`stem worker ping/inspect/revoke/stats`) and unit tests validating responses.
  - [x] Ping command (`stem worker ping`)
  - [x] Stats command (`stem worker stats`) with aggregation tests
  - [x] Inspect command (`stem worker inspect`)
  - [x] Revoke command (`stem worker revoke`)
- [x] 2.3 Add persistent revoke store and ensure workers sync on startup.
- [x] 2.4 Refactor CLI into structured command runners (e.g., `stem worker control ...`) with consistent usage/help output.

## 3. Autoscaling Engine
- [ ] 3.1 Add autoscaler module to monitor queue depth/inflight metrics.
- [ ] 3.2 Enable dynamic concurrency adjustments within configured min/max bounds for Redis and Postgres workers.
- [ ] 3.3 Provide integration tests demonstrating scale-up/down behaviour.

## 4. Lifecycle Controls
- [ ] 4.1 Implement warm/soft/hard shutdown semantics with signal handlers and CLI triggers.
- [ ] 4.2 Add max tasks per isolate and memory-usage recycle thresholds, with tests ensuring exhausted workers restart cleanly.

## 5. Documentation & Validation
- [ ] 5.1 Update user docs with new worker commands, autoscaling configuration, and shutdown guidance.
- [ ] 5.2 `dart format`, `dart analyze`, `dart test`, and targeted integration suites (control channel, autoscaling, shutdown).
- [ ] 5.3 `openspec validate add-worker-control --strict` before review.
