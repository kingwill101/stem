## Why
- The `opentelemetry` Dart package is deprecated for our use-case and diverges from the maintained `dartastic_opentelemetry` implementation that already powers our metrics pipeline.
- Maintaining duplicate telemetry stacks (OpenTelemetry + Dartastic) increases binary size, configuration surface, and the risk of instrumentation drift.
- Migrating fully to `dartastic_opentelemetry` unblocks future observability features (logs/exporters) backed by a single ecosystem.

## What Changes
- Remove the `opentelemetry` dependency and refactor tracing/worker code to rely exclusively on `dartastic_opentelemetry`/`dartastic_opentelemetry_api`.
- Update observability utilities, CLI health checks, and tests to use the new APIs, ensuring tracing spans and context propagation remain intact.
- Document the new instrumentation surface, including configuration differences, and provide migration guidance for users upgrading from `opentelemetry`.

## Impact
- Reduces the number of telemetry dependencies and simplifies configuration variables exposed to operators.
- Requires code changes wherever `opentelemetry/api.dart` (and related SDK types) are imported, plus potential updates to example apps and documentation.
- Breaking change for users consuming the `opentelemetry` APIs directly through Stem; release notes must call out the migration steps.
