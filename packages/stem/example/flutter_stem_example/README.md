# Flutter Stem Example

This example shows a mobile-oriented way to use `stem` with the generic
`stem_flutter` package plus the SQLite adapter package `stem_flutter_sqlite`.

## What It Demonstrates

- the Flutter UI acts only as a producer and publishes jobs into a SQLite
  broker
- the worker runs in a separate Dart isolate instead of sharing the UI isolate
- task status is monitored by polling the SQLite result backend
- the broker and result backend use separate SQLite files to reduce write
  contention on mobile devices
- the generic Flutter layer is separated from the SQLite adapter layer

## Why This Layout Is Better For Mobile

SQLite is a good fit for a single-device demo, but mobile apps are sensitive to
main-isolate stalls and abrupt restarts.

This example applies the main recommendations for a smoother mobile demo:

- keep the producer off the result backend
- keep the worker off the UI isolate
- avoid using one SQLite file for both broker and backend
- use `getApplicationSupportDirectory()` so the databases live in an app-owned
  location
- use shorter broker sweep and visibility intervals so hot restart recovery is
  easier to observe during development

## Runtime Model

1. The UI isolate uses `stem_flutter_sqlite` to open the broker database and
   create a `Stem` producer.
2. The UI uses `stem_flutter_sqlite` to build the SQLite bootstrap payload and
   `stem_flutter` to supervise the worker isolate.
3. The worker isolate opens its own broker handle and its own result backend.
4. Pressing `Push Job` enqueues work into the broker.
5. The UI polls the backend with `listTaskStatuses()` and polls the broker for
   pending and inflight counts.

Jobs may briefly appear as `local pending` in the UI before the worker has
written their first status row to the backend. That state means the job was
published successfully, but the backend does not yet have a tracked status
record for it.

## Run

```bash
cd stem/packages/stem/example/flutter_stem_example
flutter pub get
flutter run -d android
```

Other Dart VM Flutter targets such as Linux, macOS, and iOS also work with the
same structure.

## Notes

- `SqliteResultBackend.watch(taskId)` is process-local. For cross-isolate or
  cross-process monitoring, poll `getTaskStatus()` or `listTaskStatuses()`
  instead.
- If the app is hot-restarted while a task is inflight, the broker may need one
  visibility-timeout cycle before the task is claimable again. This example
  keeps that timeout short to make development behavior easier to understand.
