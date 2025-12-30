## Why
- The public documentation currently mixes contributor workflows and deployment ops, leaving Dart application developers without clear, end-to-end guidance on Stem's feature set.
- Key capabilities (programmatic worker integration, retry strategy tuning, Beat scheduling, routing, observability, signals, result backends) lack dedicated, consumer-focused guides with runnable code snippets.
- Consolidating feature documentation will reduce onboarding friction, ensure parity with published examples, and provide a single reference for teams adopting Stem via pub.dev.

## What Changes
- Author a "Features" doc suite that maps each Stem capability (tasks, producers, workers, scheduler, routing, signals, observability, persistence, CLI/control plane) to concise how-to guides with runnable examples.
- Surface these guides in the site navigation, ensuring cross-links from Getting Started and Core Concepts lead to the new pages.
- Provide clear, concise code samples (using tabs with labelled filenames where variants exist) illustrating in-memory vs. Redis/Postgres usage, retry tuning, Beat schedules, and signal instrumentation.
- Remove or relocate contributor/ops-only docs from the public navigation so the primary flow targets application developers.

## Impact
- Developers gain a structured "feature catalog" showing how to embed Stem in apps without digging through examples or internal docs.
- Maintainers can evolve features with corresponding doc requirements, keeping consumer docs in sync with runtime behaviour.
- Contributor-facing or ops-heavy guidance will still exist under `docs/internal/`, minimizing clutter for end users.
