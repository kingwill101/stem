# SQLite Operational Notes

Stem's SQLite adapters are designed for embedded deployments (desktop, mobile,
edge) and single-host demos. Keep the following settings and process layout
guidance in place:

## Operational guidance

- Enable write-ahead logging (`PRAGMA journal_mode=WAL;`) so concurrent readers
  don't block writes.
- Set `PRAGMA synchronous=NORMAL;` for a good durability/latency trade-off. Use
  `FULL` where durability is paramount.
- Keep transactions short—enqueue, dequeue, and result updates are scoped to the
  minimum statements needed.
- Run periodic sweepers to reclaim expired locks and clean TTL'd rows. The
  adapters expose maintenance hooks for this purpose.
- Vacuum during maintenance windows if the file grows significantly after large
  bursts of jobs.

## Process layout (avoid WAL contention)

SQLite allows only one writer at a time. To avoid lock contention:

- Use **separate database files** for the broker and result backend.
- Keep **producers off the result backend** (let workers be the only writers).
- Avoid running multiple processes that write to the same SQLite file.
- Prefer local disk (avoid network filesystems for WAL-backed files).

## Native assets

The `sqlite3` package uses native assets. For stable behavior in CLI tools,
build and run the bundled binaries (`dart build cli`) instead of relying on
`dart run`.

The `stem_sqlite` package bundles schema migrations via Ormed and applies the
recommended pragmas automatically.
