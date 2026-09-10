# Example wakeup cancellation

`startupWakeup` reconciles native registrations without resuming a saved pause.
`requestWakeup` is the explicit resume action used by Retry wakeup and committed
new photo publication. Periodic callbacks and budget continuation never resume.

The example uses two small SQLite databases under its application support
directory:

- `wakeup-control.sqlite` stores pause intent in short transactions.
- `wakeup-control.sqlite.effects` provides a cross-isolate transaction mutex for
  native scheduler effects. It stores no tasks.

Separating them is necessary because an awaited native platform call may never
complete. Holding the intent database's write transaction across that call
would prevent Cancel from persisting and block callback admission reads.
SQLite lock acquisition uses asynchronous retry rather than a blocking busy
timeout, so a competing UI isolate can still service platform-channel work.
The retry timer is only mutex contention handling, not deferred-task polling.

Cancel and resume commit intent before attempting native effects. An effect
reads current intent before calling Android, then checks again when Android
returns. If intent changed, it applies the newer intent while retaining the
effect mutex. The same repair occurs after an old effect fails.

The public effect wait is bounded to five seconds. A timeout reports that intent
was saved but native effects remain pending; it does **not** release the mutex
or claim that the native operation stopped. Late completion continues repair,
and late failures are handled. If the platform call never completes, native
effects remain blocked until the process exits, but intent can still change and
callback admission still reads it. Mutex acquisition itself is bounded to
30 seconds; startup or an explicit action can retry failed native repair.

SQLite and Workmanager cannot commit atomically. A platform failure or process
death can leave stale native registrations. Saved pause prevents a new callback
from entering the worker, and startup retries native reconciliation. A callback
already admitted can finish or report a native retry; cancellation neither
deletes queued tasks nor guarantees interruption of active Dart. A later
explicit resume deliberately permits callback admission again even if a prior
native effect has not finished. Android still decides when admitted work runs.
