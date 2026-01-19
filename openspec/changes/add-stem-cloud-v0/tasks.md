## 0. Scaffolding
- [x] 0.1 Split cloud contracts into stem_cloud_protocol/stem_cloud_gateway/stem_cloud_worker
- [x] 0.2 Define transport, gateway, worker, billing, and CLI contracts
- [x] 0.3 Draft ops runbook
- [x] 0.4 Add Postgres-backed gateway scaffolding
- [x] 0.5 Add Ormed migration scaffolding for tenants
- [x] 0.6 Add Stem Cloud datasource/registry scaffolding
- [x] 0.7 Add Ormed tenant store scaffolding
- [x] 0.8 Add usage counter migration + tracker
- [x] 0.9 Add assignment persistence models/migration
- [x] 0.10 Add Ormed admin service implementation
- [x] 0.11 Wire gateway to assignment store

## 1. Implementation
- [x] 1.1 Finalize worker transport protocol contract
- [x] 1.2 Implement gateway auth + tenant scoping
- [x] 1.3 Implement enqueue and status APIs
- [x] 1.4 Implement assignment dispatch + lease renewal (push-based stream)
- [x] 1.5 Implement worker client with reconnect
- [x] 1.6 Implement credit policy enforcement
- [x] 1.7 Add usage counters and alerts
- [x] 1.8 Draft ops runbook and admin tooling
- [x] 1.9 Remove TaskSource wiring from stem worker (keep broker/backends)
- [x] 1.10 Add protocol + worker adapter tests
- [x] 1.11 Add Stem Cloud workflow store + gateway endpoints
- [x] 1.11.1 Persist workflow definitions + steps in gateway storage
- [x] 1.11.2 Add workflow definition sync + lookup endpoints
- [x] 1.11.3 Add cloud workflow registry client (sync on register)
- [x] 1.12 Add local dev stack + e2e task/workflow examples
- [x] 1.13 Migrate stem_cloud_gateway to routed (^0.3.0) and rehome routes
- [x] 1.13.1 Split gateway API router into per-group route modules + handlers
- [x] 1.14 Add routed_testing/server_testing/property_testing test harnesses

### 1.A Realtime + Client Surfaces
- [x] 1.15 Add client task status WebSocket stream (separate from worker WS)
- [x] 1.20 Add minimal dashboard view for task list + status
- [x] 1.25 Wire workflow definitions into dashboard routes/views
- [x] 1.26 Support separate control-plane datastore configuration (gateway DB distinct from execution backends)

### 1.B Security + Tenant Controls
- [x] 1.16 Enforce tenant namespace scoping across all HTTP + WS endpoints
- [x] 1.17 Add per-tenant envelope signing + signature verification
- [x] 1.18 Add tenant rate limiting + queue depth quotas
  - [x] 1.18.1 Define per-tenant request budget defaults + override fields
  - [x] 1.18.2 Track rolling request counters (by route group + tenant)
  - [x] 1.18.3 Enforce queue depth quotas on publish/enqueue
  - [x] 1.18.4 Emit clear 429/409 errors with retry hints
  - [x] 1.18.5 Add tests for limit + quota enforcement paths

### 1.C Billing + Metering
- [x] 1.19 Add usage metering hooks for billing
  - [x] 1.19.1 Define metering event model (enqueued/started/completed/runtime)
  - [x] 1.19.2 Capture task transition timestamps server-side (in-memory for v0)
  - [x] 1.19.3 Persist per-tenant usage aggregates
  - [x] 1.19.4 Expose usage query endpoint for ops
  - [x] 1.19.5 Add tests for metering event emission + aggregation
- [x] 1.20 Add usage alerts (Stripe reporting deferred)
  - [ ] 1.20.1 Map usage aggregates to Stripe meter events (deferred)
  - [ ] 1.20.2 Add retry + idempotency for meter submissions (deferred)
  - [x] 1.20.3 Wire usage alert thresholds to notification hooks
  - [x] 1.20.4 Add tests for alert triggers

### 1.D Ops Tooling
- [ ] 1.21 Add minimal ops tooling for tenant lifecycle + recovery
  - [ ] 1.21.1 Add CLI commands for tenant list/update/disable
  - [x] 1.21.2 Add queue purge + dead-letter replay utilities
  - [x] 1.21.3 Add recovery path for stuck assignments
  - [ ] 1.21.4 Add tests for admin CLI commands

### 1.E Product Scope Docs
- [x] 1.22 Document workflow v0 constraints (code-defined flows only)
- [x] 1.23 Decide v0 scheduling exposure (none or basic cron API) and document
- [x] 1.24 Document autoscaling as not exposed in v0

## 2. Deferred
- [ ] 2.1 Gateway observability instrumentation (OpenTelemetry + Sentry exporters)
  - [ ] 2.1.1 Add OpenTelemetry tracing + metrics setup
  - [ ] 2.1.2 Add Sentry error reporting + release tagging
  - [ ] 2.1.3 Add docs for env configuration + sampling
