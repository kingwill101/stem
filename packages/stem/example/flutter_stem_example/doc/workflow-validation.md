# Workflow workbench validation (earlier single-worker build)

## What is exercised

The workbench is not limited to image tasks. The Tasks tab accepts independent
single-photo requests and multiple bounded batches. The Workflows tab launches
1–5 report, sleep, or approval runs per request and reads real workflow state
and checkpoints from `workflows.sqlite`.

The task app, workflow store, and worker remain distinct owned resources:
the workflow layer borrows the task app, and the root joins controllers,
runtime polling, and worker shutdown before disposing stores. Android callbacks
reconstruct the same definitions and use the same files.

## Automated evidence

- Full core suite: **809 passed**, including seven gated workflow-poll lifecycle
  tests for initial scanning, non-overlap, joining disposal, errors, and restart.
- Full example suite: **91 passed**, run serially to avoid host-load timeouts.
- Example library, unit/widget tests, and integration-test source analyze cleanly.
- The Android Workmanager profile APK builds successfully.

Real SQLite tests create fresh producer, callback, and observer runtimes:

- Five independent report launches persist and complete with three checkpoints.
- A sleep outlives one bounded invocation. A later invocation resumes it without
  replacing the original `preparedAt` checkpoint.
- Approval is scoped to the selected run and survives restart. Cancelling a run
  persists cancellation without resuming native scheduling for unrelated work.
- Controllers join pending commands and reads before disposal.
- A newly due sleeper stays suspended while a separate gated delivery drains.
  It remains discoverable for a timed wakeup, and the next callback completes it.

Widget tests cover repeated queued launches, tab remounting without retiring
the publisher, root-owned storage disposal, targeted approval, persisted
checkpoint display, errors/retry, and 320/360px layouts with 2× text scaling.

## Native observations

Observed on Samsung SM-A075M, Android 16, using the profile Workmanager
entrypoint. The UI was producer/observer-only. No foreground worker was started.
Times below are the phone's local clock on September 10, 2026.

| Scenario | Observed outcome |
| --- | --- |
| Three report workflows launched together | All completed; each stored `collect`, `total`, and `publish`, with result `{"rows":3,"total":35}`. Native callback completed with `idle`, three deliveries, and WorkManager `SUCCESS`. |
| One ten-second sleep workflow | Initial callback started 13:57:13 and returned idle at 13:57:14. A timed wakeup started another drain at 13:57:23; the run completed at 13:57:24 and the callback succeeded at 13:57:25. Original `preparedAt` was preserved in both `prepare` and final result. |
| Two approval workflows | Both persisted distinct run-specific topics and draft checkpoints. Approving one through the UI completed only that run; the other remained suspended. Both original draft values were unchanged. |
| Photo task while another workflow awaited approval | The photo succeeded at attempt zero. The unapproved workflow remained suspended; it did not block ordinary task processing. |

These outcomes were checked in copied app-owned SQLite databases/WALs, not only
through UI counters. The native scenarios preceded a final review hardening:
bounded callbacks now stop/join polling immediately after the initial due scan,
before worker admission, and timed wake delays round upward to whole seconds.
The final hardening has automated regression coverage and the latest APK is
installed, but the timed wake scenario has not yet been repeated on that final
build. One approval run is intentionally left waiting for interactive testing.

## Limits and next tests

- This recorded phone run used one worker. The default topology now includes
  shared-queue and dedicated workers; see [multi-worker validation](multiworker-validation.md).
  Stale-owner workflow writes after lease expiry remain a separate recovery concern.
- WorkManager chooses execution time. Timed callbacks only append to the serial
  drain chain; they never consume workflows in a separate parallel worker.
- A generic due-run scan and broker enqueue are not one atomic transaction.
  The joined lifecycle fixes normal shutdown races, not every process-kill or
  transport-failure window.
- Workflow checkpointing does not make external effects exactly-once.
- Native workflow process-kill/retry exhaustion, stale-owner races, and force-stop
  remain separate acceptance tests. The earlier photo-task SIGKILL experiment
  is not proof of these workflow guarantees.
- Existing status-bar notifications currently describe photo batches. Workflow
  state and checkpoints are exposed on the Workflows tab.

See [Android task recovery validation](android-recovery-validation.md) for the
separate CPU/image-task experiment and [wakeup cancellation](wakeup-cancellation.md)
for saved pause intent versus native scheduling effects.
