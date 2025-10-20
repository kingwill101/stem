## Approach

- Follow the existing doc structure under `.site/docs/` for new planning artifacts. Place the design doc and spike summaries in `docs/design/` to keep them close to technical documentation.
- Reuse the ADR format established in previous repositories (title, status, context, decision, consequences) to ensure consistency.
- Milestones and DoR/DoD definitions will live in a new `/docs/process/roadmap.md` file, referencing the OpenSpec tasks for traceability.
- Annotate interfaces directly in `lib/src/core/contracts.dart` and related files, adding `@since 0.1.0` comments without breaking API signatures.
- SLO dashboards: leverage existing OTLP metrics; outline required charts/alerts in the runbook while deferring actual Grafana setup to implementation tasks.
- Security checklist will cover TLS requirements, secret management, payload signing guidance, and link to future compliance scans.
