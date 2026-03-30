# Changelog

## 0.1.1-wip

- Updated internal package constraints to accept the in-progress `stem`
  prerelease and matching sibling package prereleases during workspace
  development.

## 0.1.0

- Updated the dashboard data layer to use Ormed 0.2.0.
- Reworked the dashboard into a richer operations console with dedicated views
  for tasks, jobs, workflows, workers, failures, audit, events, namespaces, and
  search.
- Refactored UI rendering into modular page components and shared table/layout
  primitives for better maintainability.
- Introduced a full Tailwind-based styling system and updated responsive layout
  behavior for sidebar/header/content rendering.
- Improved navigation and Turbo frame behavior to reduce stale-content flashes
  during page switches.
- Expanded dashboard state/service/server models and test coverage to support
  the new views and metadata-rich rendering paths.
- Clarified workflow views by labeling script-runtime nodes as checkpoints
  instead of steps.
- Initial release of the `stem_dashboard` package.
