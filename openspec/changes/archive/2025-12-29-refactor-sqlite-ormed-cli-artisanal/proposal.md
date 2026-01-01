## Why
SQLite is the first driver we want to standardize on the new ormed migration system, and the CLI needs a consistent, richer UX foundation. Aligning on ormed and artisanal reduces bespoke plumbing and gives us first-class migrations and nicer CLI outputs.

## What Changes
- Migrate the SQLite driver to ormed, including ormed CLI initialization and migration bootstrap.
- Replace `package:args` with `package:artisanal/args.dart` in the CLI (drop-in replacement).
- Adopt artisanal helpers in CLI commands for richer output while preserving existing behavior.

## Impact
- Affected specs: sqlite-driver, cli
- Affected code: packages/stem_sqlite, packages/stem/lib/src/sqlite, packages/stem_cli
