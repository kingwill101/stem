## Overview
Enhance Beat to deliver production-grade scheduling with operability tooling.

### Locking Model
- Use Redis SET NX PX to acquire `stem:schedule:<entryId>:lock` with TTL slightly below schedule interval.
- Introduce periodic lease renewal (half TTL) while a scheduler instance processes due entries.
- Record contention metrics (number of failed lock acquisitions) for observability change.

### Jitter & Metadata
- Store jitter value per entry; when firing, compute `scheduledAt + jitter`. Persist computed jitter used for audit.
- Persist fields in Redis hash: `nextRunAt`, `lastRunAt`, `lastError`, `jitterMs`, `enabled`.

### CLI Flow
- `stem schedule list` prints table of entries with next run and enabled flags.
- `stem schedule show <id>` dumps JSON with metadata and history (last run, last error).
- `stem schedule apply --file schedules.yaml` upserts entries, supports dry-run mode.
- `stem schedule delete <id> --yes` removes entry and metadata.
- `stem schedule dry-run <id>` evaluates next `N` fire times considering jitter.

### File Format
- YAML/JSON schema: `id`, `task`, `args`, `schedule` (cron|interval), `jitterMs`, `enabled`, `timezone`.
- Validation ensures cron expressions parse, interval >= heartbeat interval, jitter <= configurable max.

## Open Questions
- Should we version schedule definitions? (Potential future addition; for now rely on idempotent apply.)
- Where to store history beyond last run? (Potential metrics integration later.)
