# stem_flutter

`stem_flutter` provides Flutter-specific integration helpers for Stem.

It is intentionally focused on the Flutter concerns that apply across broker and
backend adapters:

- spawning and supervising a worker isolate from Flutter
- monitoring queue depth, worker heartbeats, and recent jobs for UI surfaces
- keeping mobile runtime coordination out of app code

What it does not do:

- promise an always-on background worker on iOS or Android
- hide platform lifecycle limits
- force a specific broker/backend adapter such as SQLite
- force a specific scheduler integration

Use `stem_flutter_sqlite` if you want the SQLite adapter package.
