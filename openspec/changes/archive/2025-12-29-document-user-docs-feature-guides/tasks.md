## 1. Planning & Audit
- [x] 1.1 Catalogue current `.site/docs` coverage, identify overlaps with examples, and confirm which internal docs move to `docs/internal/`.
- [x] 1.2 Finalize the feature taxonomy for consumer docs (tasks, producer API, worker runtime, Beat scheduler, routing, signals, observability, persistence, CLI/control).

## 2. Author Feature Guides
- [x] 2.1 Create/expand task & retry guide with concise, runnable snippets (in-memory + Redis) and TaskContext usage.
- [x] 2.2 Document producer APIs (enqueue patterns, signing, delayed tasks) with tabbed examples labelled by filename/back-end variant.
- [x] 2.3 Expand worker runtime docs (concurrency, lifecycle, shutdown) with brief examples and cross-links to signals/control plane.
- [x] 2.4 Produce Beat scheduler guide covering schedule specs, YAML loading, programmatic APIs, and observability hooks; ensure each spec type has a short example.
- [x] 2.5 Document routing/broadcast config with YAML + Dart registration examples, highlighting key sub-features (priorities, broadcasts, aliases).
- [x] 2.6 Add observability guide (metrics, traces, logging, health checks) with exporter setup examples and signal usage.
- [x] 2.7 Cover persistence surfaces (result backend, schedule/lock stores, revocation store) with usage notes and minimal examples.
- [x] 2.8 Summarize CLI/control plane commands relevant to app developers (enqueue, observe, worker control) with brief usage snippets.

## 3. Navigation & Cleanup
- [x] 3.1 Update `.site/sidebars.ts` and index pages to surface the new feature docs, ensuring logical next/previous flow.
- [x] 3.2 Relocate ops/security/contributor docs to `docs/internal/` (or link from a separate contributor index) so public navigation stays consumer-focused.
- [x] 3.3 Validate all Markdown links and code samples (`npm run build`, `dart format`) and ensure developer quick start references the new guides.

## 4. Acceptance
- [x] 4.1 `npm run build` (docs) and `dart test` (as needed for updated examples).
- [x] 4.2 `openspec validate document-user-docs-feature-guides --strict`.
