## 1. Design Sign-off
- [x] 1.1 Draft comprehensive design doc (system diagram, message schema, delivery semantics, config/security/observability, risks) in `/docs/design/stem-v1.md`.
- [x] 1.2 Record ADRs for broker/backend choice, ack+result ordering, and retry/DLQ defaults.
- [x] 1.3 Annotate public interfaces with `@since 0.1.0` and document compatibility policy in README/docs.

## 2. Risk & Spike Reports
- [x] 2.1 Publish one-pagers for Redis reclaim strategy, isolate hard timeouts, and atomic ack+set decision (include findings + keep/discard summary).

## 3. Planning & Milestones
- [x] 3.1 Create milestone plan (M1–M4) with DoR/DoD definitions and acceptance criteria; link to OpenSpec tasks.
- [x] 3.2 Capture outstanding phase checklists (security, QA gates, ops tooling) in a roadmap document.

## 4. Observability & Security Artifacts
- [x] 4.1 Define SLOs, dashboards, and alerts using existing metrics; document runbooks.
- [x] 4.2 Write the security checklist and threat model (TLS, secrets, optional signing policies).

## 5. Validation
- [x] 5.1 `openspec validate plan-stem-delivery-process --strict`.
- [x] 5.2 Stakeholder sign-off logged in design doc.
