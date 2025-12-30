## Why
- Operators lack a live, browser-based view into Stem’s runtime (queues, workers, scheduled jobs, DLQ), forcing them to rely on CLI snapshots and logs.
- Triggering ad-hoc jobs or replaying tasks currently requires CLI access; we need an accessible UI for day-to-day operations.
- The Hotwire + Routed stack is the preferred direction for Stem’s dashboard efforts, and we want to validate it quickly using the local routed_hotwire packages.

## What Changes
- Build a Routed Hotwire dashboard (web) that lists live overview metrics, task queues, events, and workers with sortable tables and detail drill-downs.
- Add simple controls to enqueue demo jobs, replay DLQ entries, and send worker directives (pause/shutdown) from the UI.
- Integrate dashboards with the existing Stem control plane abstractions (or Redis fallbacks) so the UI reflects real system state.
- Configure the project to depend on the local routed_hotwire packages at `~/code/dart_packages/routed_ecosystem`.

## Impact
- New `dashboard/` package (or module) housing the Hotwire app, controllers, templates, and assets.
- Updates to `pubspec.yaml` / workspace configuration to point to local routed ecosystem packages.
- Potential new APIs in Stem core or adapters for fetching summaries needed by the dashboard (queues, events, workers).
- Documentation outlining how to start the dashboard locally, including dependency overrides for the routed ecosystem.
