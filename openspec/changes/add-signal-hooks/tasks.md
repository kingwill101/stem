## 1. Research & Design
- [x] 1.1 Inventory Celery signals and map them to Stem lifecycle events.
- [x] 1.2 Define signal API (registration, payload types, filtering) and capture decisions in design.md.

## 2. Signal Infrastructure
- [x] 2.1 Implement lightweight signal dispatcher supporting sync/async handlers and filtering.
- [x] 2.2 Expose registration APIs (`StemSignals.taskPrerun`, etc.) and unit tests.

## 3. Runtime Emitters
- [x] 3.1 Emit signals in coordinator (before/after publish, enqueue) and ensure middleware integration.
- [x] 3.2 Emit worker signals (task received, prerun, postrun, retry, success, failure, revoked) with contextual payloads.
- [x] 3.3 Emit worker lifecycle signals (ready, shutdown, heartbeat) and scheduler signals (entry due, run success/failure).

## 4. Bridging & Configuration
- [x] 4.1 Provide compatibility helpers for middleware to emit signals and vice versa.
- [x] 4.2 Add configuration to enable/disable specific signals and document performance considerations.

## 5. Observability & Docs
- [x] 5.1 Document available signals, payloads, ordering guarantees, and usage examples.
- [x] 5.2 Update tests to cover signal dispatch order and ensure no regressions when handlers throw.
- [x] 5.3 `dart format`, `dart analyze`, `dart test`, and `openspec validate add-signal-hooks --strict` before review.
