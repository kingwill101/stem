## Why
- Newcomers currently bounce between terse in-memory examples and scattered reference pages without a single story that carries them from installing Stem to operating it in production.
- The `getting-started` sidebar misaligns with existing content (e.g. promising an OTLP demo) and omits critical topics such as environment bootstrapping, observability defaults, and deployment checklists.
- Teams adopting Stem need prescriptive documentation that answers “what do I do next?” at every stage, reducing support churn and accelerating successful rollouts.

## What Changes
- Author a newcomer-focused onboarding guide in `.site/docs` that walks through prerequisites, installing Stem, running the first task, connecting to Redis/Postgres, enabling telemetry, and preparing for deployment.
- Rework existing `getting-started` pages (intro, quick start, developer environment) to align with the new journey, eliminate contradictions, and clearly point readers to the next step.
- Add production-readiness material (deployment checklist, ops reminders, verification commands) so readers finish the section with confidence to ship.
- Weave the full Stem feature set (core pipeline, worker operations & signals, observability, security/deployment, enablement/quality) through the journey with concrete examples and clear pointers to deeper references.
- Update navigation (sidebar ordering and cross-links) to highlight the journey and surface follow-up resources (core concepts, workers, scheduler).

## Impact
- Documentation-only change touching `.site/docs` (and matching sidebar metadata); no runtime code or packages are affected.
- Requires running the Docusaurus build (`npm run build` inside `.site/`) to validate MDX formatting once content lands.
