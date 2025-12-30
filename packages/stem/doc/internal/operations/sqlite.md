# SQLite Operational Notes

Stem's SQLite adapters are designed for embedded deployments (desktop, mobile, edge). Keep the following settings in place when opening the database:

- Enable write-ahead logging (`PRAGMA journal_mode=WAL;`) so concurrent readers don't block writes.
- Set `PRAGMA synchronous=NORMAL;` for a good durability/latency trade-off. Use `FULL` where durability is paramount.
- Keep transactions short—enqueue, dequeue, and result updates are scoped to the minimum statements needed.
- Run periodic sweepers to reclaim expired locks and clean TTL'd rows. The adapters expose maintenance hooks for this purpose.
- Vacuum during maintenance windows if the file grows significantly after large bursts of jobs.

The `stem_sqlite` package bundles schema migrations via Ormed and applies the recommended pragmas automatically.
