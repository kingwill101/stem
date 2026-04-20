# stem_flutter_sqlite

`stem_flutter_sqlite` contains the SQLite-specific integration helpers that sit
on top of `stem_flutter`.

It covers the pieces that are inherently file-backed and SQLite-specific:

- resolving an application-support directory layout for broker/backend files
- opening a foreground SQLite-backed producer runtime
- initializing SQLite adapter dependencies needed by Flutter builds
- building background isolate bootstrap payloads for SQLite workers
- reopening broker/backend handles inside the worker isolate
- optional convenience helpers for spawning a SQLite worker from Flutter

Use `stem_flutter` for the generic Flutter worker and monitoring surface.
