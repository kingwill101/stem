## Overview
We will introduce a `stem dlq` command group that leverages broker/backends to inspect and recover failed envelopes. Redis implementations must expose:
- A listing API returning envelope metadata + failure reason.
- A replay operation that removes entries from the DLQ and republishes them with incremented attempt count.

## Command Surface
| Command | Description |
|---------|-------------|
| `stem dlq list [queue]` | Paginated list showing id, task, attempt, failedAt, reason. |
| `stem dlq show <id>` | Dumps full envelope + error payload. |
| `stem dlq replay [queue] --limit --since --dry-run --delay` | Moves entries back to active queue. |
| `stem dlq purge [queue] --force` | Clears the DLQ after confirmation. |

## Safety Features
- Require explicit confirmation for replay/purge unless `--yes` is supplied.
- Default `--limit` for replay batches (e.g., 100).
- `--dry-run` to inspect counts before executing.

## Data Flow
1. CLI calls `ResultBackend.listDeadLetters(queue, filters)` (new contract) to obtain metadata.
2. Replay uses broker API `Broker.replayDeadLetters(queue, options)` that re-publishes envelopes and updates backend state.
3. Events are emitted via worker metrics channel to record replay counts.

## Open Decisions
- Decide whether to persist replay audit trail (propose storing last replay timestamp in backend meta).
- Determine concurrency for replay operations (initial synchronous iteration, streaming later if needed).
