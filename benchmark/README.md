# Stem benchmarks

Run the repeatable in-memory throughput workload from the repository root:

```bash
dart run benchmark/stem_throughput.dart --tasks 5000 --concurrency 8
dart run benchmark/stem_throughput.dart --check-baseline
```

The benchmark warms up the worker before measuring and reports enqueue
throughput and end-to-end delivery/execution throughput as JSON. The checked-in
baseline is a deliberately conservative minimum for CI; record machine-specific
results with the commit and Dart SDK when comparing performance changes. Adapter
benchmarks should live beside the adapter because Redis, Postgres and SQLite
contention have different costs.

The SQLite adapter has a file-backed worker/broker/backend workload that
exercises concurrent writer coordination:

```bash
cd packages/stem_sqlite
dart run benchmark/sqlite_throughput.dart --tasks 1000 --concurrency 4 \
  --check-baseline
```
