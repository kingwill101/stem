## 1. Implementation
- [x] 1.1 Expand StemWorkerConfig to include all Worker options (rateLimiter,
      middleware, uniqueTaskCoordinator, retryStrategy, subscription,
      heartbeatInterval, workerHeartbeatInterval, heartbeatTransport,
      heartbeatNamespace, autoscale, lifecycle, observability, signer, and
      any remaining constructor parameters).
- [x] 1.2 Update StemApp.create/inMemory to forward the expanded worker config
      into the managed Worker with consistent defaults.
- [x] 1.3 Add StemApp.canvas to expose a Canvas helper wired to the app
      broker/backend/registry and encoder registry.

## 2. Tests
- [x] 2.1 Add unit tests that verify advanced worker options passed via
      StemWorkerConfig are applied on the managed Worker.
- [x] 2.2 Add tests that StemApp.canvas shares the app broker/backend/registry.

## 3. Documentation
- [x] 3.1 Update .site/docs snippets and example code to prefer StemApp where
      possible, now that advanced worker options are available.

## 4. Quality gates
- [x] 4.1 Run formatting, analysis, and relevant tests.
