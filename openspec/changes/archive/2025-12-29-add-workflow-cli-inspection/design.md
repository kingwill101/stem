# Design: Workflow CLI inspection tooling

## Overview
Extend the CLI package with new subcommands under `stem wf`:
- `stem wf waiters [--topic <topic>] [--status suspended]` – lists runs awaiting events, showing watcher info.
- `stem wf leases <runId>` (or extend `show`) – displays lease expiry, suspension/cancellation policies, last heartbeat.

## Implementation Notes
- CLI resolves run data via existing store/adapter APIs (requires new methods in the core package for watchers/policies).
- Output should favour tables/JSON to make automation easier.
- Tests use in-memory workflow app to simulate runs and validate CLI output (golden tests).

## Risks
Low; primarily CLI plumbing. Ensure new APIs are surfaced through packages for use outside CLI if needed.
