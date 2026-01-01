## Overview
Rework the user-facing documentation to follow a feature-first structure that mirrors how Dart developers adopt Stem. Each capability receives a short how-to guide with runnable code snippets (using tabs for in-memory vs. external backends). Navigation will highlight these guides while contributor/ops content moves to an internal area.

## Proposed Information Architecture
1. **Getting Started** – Quick start + developer environment (already present).
2. **Core Concepts / Feature Guides**
   - Tasks & Retries (TaskOptions, TaskContext, idempotency)
   - Producer API (`Stem.enqueue`, signing, metadata, delays)
   - Worker Runtime (concurrency, lifecycle, shutdown)
   - Scheduler / Beat (interval/cron/solar/clocked specs, YAML loading, signals)
   - Routing & Broadcasts (config + programmatic usage)
   - Signals & Observability (metrics, traces, logging, health checks)
   - Persistence (result backend, schedule/lock stores, revocation store)
   - CLI & Control (enqueue, observe, worker control commands)
3. **Workers Section** – Programmatic integration, control plane, daemonization.
4. **Scheduler Section** – Beat guide only (parity doc moved internal).
5. **Brokers** – Overview for comparing backends when leaving in-memory mode.

Contributor/ops/security docs will reside under `docs/internal/` with their own index for maintainers.

## Authoring Approach
- Each feature doc starts with an in-memory example, then shows Redis/Postgres variants using Docusaurus tabs (labelled with filenames so developers can copy/paste quickly).
- Examples remain concise—just enough code to demonstrate the concept—while covering the breadth of each feature (options, signals, CLI helpers, etc.).
- Cross-links tie guides together (e.g., worker guide references signals and observability).
- Quick start / developer environment pages link into the feature guides so developers flow naturally through the documentation.
- Run `npm run build` to catch broken links after restructuring.
