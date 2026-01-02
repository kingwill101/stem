## Why
StemApp does not currently expose the full Worker configuration surface, which
forces users to drop to manual wiring for common features (rate limiting,
observability, autoscaling, heartbeat control, signing, retries, and routing
subscriptions). This undermines the goal of using StemApp as the default
bootstrap path in documentation and examples.

## What Changes
- Expand StemWorkerConfig to cover the full Worker constructor surface.
- Forward all StemWorkerConfig options when constructing the managed Worker in
  StemApp.create and StemApp.inMemory.
- Expose a StemApp.canvas helper that reuses the app wiring for Canvas
  composition.
- Ensure overlapping options continue to apply consistently between Stem and
  Worker (with sensible defaults when not provided).
- Update documentation snippets to prefer StemApp now that advanced worker
  features are supported.

## Impact
- Affected specs: runtime_bootstrap
- Affected code: packages/stem/lib/src/bootstrap/stem_app.dart,
  packages/stem/lib/src/bootstrap/factories.dart, .site/docs, and
  packages/stem/example/docs_snippets
