## Why
- Stem’s example suite does not demonstrate several flagship features (rate limiting, delayed delivery, DLQ replay, worker control channel, autoscaling, scheduler drift signals, signing key rotation, quality gates), leaving newcomers without runnable guidance.
- Documentation now references these capabilities; without examples teams must reverse-engineer usage from core libraries, increasing onboarding friction and support load.
- Comprehensive examples will provide end-to-end validation of the platform and serve as regression fixtures as we expand feature coverage.

## What Changes
- Introduce a structured backlog of runnable examples (Docker-ready where appropriate) covering delayed enqueue + rate limiting, DLQ operations, worker control tooling, autoscaling, scheduler observability, signing key rotation, ops health checks, quality gate scripts, and progress/heartbeat reporting.
- Update the docs sidebar/index to surface the new examples and cross-link from the getting-started “Next Steps” sections.
- Wire each example with README instructions, environment templates, and automated scripts so they are copy-paste runnable.

## Impact
- New directories under `examples/` with supporting Dart code, Docker Compose manifests, and configuration.
- Documentation additions (example index pages) plus potential updates to CI to validate the examples.
- No production runtime changes, but repo footprint/matrix will grow—ensure CI execution time stays acceptable (may need to gate long-running stacks behind optional targets).
