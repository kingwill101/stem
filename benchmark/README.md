# Stem benchmarks

Run the repeatable store-backed throughput workload from the repository root:

```bash
devenv shell -- repodoc benchmark:throughput --tasks 5000 --concurrency 8
devenv shell -- repodoc benchmark:throughput --check-baseline
```

Select a backing store with `--store`, or compare several stores with
`--stores`:

```bash
# SQLite uses a repository-local temporary database by default.
devenv shell -- repodoc benchmark:throughput --store sqlite

# Start Postgres and Redis first; devenv supplies their benchmark URLs.
devenv up -d
devenv shell -- repodoc benchmark:throughput \
  --stores memory,sqlite,postgres,redis \
  --tasks 5000 --warmup 250 --buckets 4,8,16
devenv down
```

Override external store connections with `--postgres-url` or `--redis-url`.
Use `--sqlite-path` when a persistent SQLite database is desired. The
end-to-end metric waits for the worker's handler completion and then for the
store's broker queue to drain, so the report exposes both handler throughput
and store acknowledgement/persistence drain time. Add `--verbose` to log
connection, worker, enqueue, drain, and cleanup stages to stderr while
diagnosing a slow or unavailable store.

The PostgreSQL sweep uses separate producer and worker connections, so polling
does not serialize behind publication and acknowledgement operations. Its
worker poll interval is intentionally 100 ms for repeatable small workloads.

For PostgreSQL adapter timings, add `--timings`. The report includes operation
counts, average/P95/max latency, database execution time, and time waiting on
the adapter's serialized connection queue. It also shows the slowest
parameterized SQL statements in the terminal; the JSON artifact retains the
full SQL text without bound values:

```bash
devenv shell -- repodoc benchmark:throughput \
  --store postgres --tasks 20 --warmup 2 --concurrency 1 \
  --verbose --timings --output .tmp/postgres-throughput.json
```

The default `devenv` PostgreSQL service keeps `synchronous_commit=on`, so these
measurements include durable commit latency. That is the correct comparison
for a durable queue, but a development filesystem can make each write much
slower than the SQL plan itself. For an explicitly non-durable diagnostic
comparison only, temporarily run:

```bash
devenv shell -- psql \
  'postgresql://stem:stem@127.0.0.1:5432/stem_benchmark' \
  -c "alter database stem_benchmark set synchronous_commit = off"
devenv shell -- stem-benchmark --store postgres --tasks 1000 --concurrency 1
devenv shell -- psql \
  'postgresql://stem:stem@127.0.0.1:5432/stem_benchmark' \
  -c "alter database stem_benchmark reset synchronous_commit"
```

Reset the setting immediately after the comparison. Do not use this mode to
claim durable production throughput.

Run a concurrency sweep with `--buckets`. Bucket values are concurrency
levels, so `--buckets 4,8,16` runs the same workload at all three levels:

```bash
devenv shell -- repodoc benchmark:throughput \
  --tasks 5000 --warmup 250 --buckets 4,8,16
```

The benchmark warms up the worker before measuring and reports enqueue
throughput and end-to-end delivery/execution throughput in an Artisanal terminal
table. The checked-in baseline is a deliberately conservative minimum for CI.
Save the machine-readable result when comparing performance changes:

```bash
devenv shell -- repodoc benchmark:throughput \
  --tasks 5000 --buckets 4,8,16 \
  --output .tmp/stem-throughput.json
```

Use `--json` when a command or script needs the raw result on stdout. Repodoc
owns the benchmark implementation and is the only supported throughput entry
point. Adapter benchmarks should live beside the adapter because Redis,
Postgres and SQLite contention have different costs.

GitHub CI runs the memory benchmark as a hard regression gate and runs SQLite,
PostgreSQL, and Redis sequentially as external-store smoke/report benchmarks.
Each run is written to the GitHub job summary and uploaded as JSON artifacts.
Pull requests use a smaller workload; scheduled and manually dispatched runs
use larger workloads and configurable concurrency buckets.

## Job profiling

For a worker-oriented profile, use the deterministic job workload. It measures
enqueue, queue, execution, and task end-to-end latency separately and supports
both inline and isolate execution:

```bash
stem-profile --tasks 10000 --warmup 1000 --concurrency 8 --mode isolate --workload cpu --work-units 250
```

Outside devenv, the equivalent compatibility command is:

```bash
dart run repodoc/bin/repodoc.dart profile:job --tasks 10000 --warmup 1000 --concurrency 8 --mode isolate --workload cpu --work-units 250
```

The command compiles the workload to an AOT executable and runs five fresh
process trials. It displays the scenario and median/P95 trial summaries, then
writes the JSON artifact under `build/stem-profile/` with the Git SHA, SDK,
scenario, per-trial samples, medians, p95 values, and RSS samples. Add
`--json` for raw JSON on stdout. Use `--repetitions 10` when a comparison needs
a larger sample.

For CPU, timeline, isolate, and allocation inspection, pause the same workload
under the Dart VM service:

```bash
devenv shell -- repodoc profile:job:vm --tasks 20000 --warmup 2000 --concurrency 8 --mode isolate --workload cpu --work-units 250 --hold-seconds 10
```

The command writes connection details to
`build/stem-profile/vm-service.json` and pauses before the workload starts.
Connect DevTools using the service URI, resume the isolate, and collect the
profile while the fixed workload runs. For headless memory samples, DevTools
also supports `--record-memory-profile=<file>` with the same service URI.

These profiles use the in-memory adapter so runtime and handler costs can be
isolated. Adapter contention profiles should remain separate and use the
adapter-specific benchmark beside the adapter package.

The SQLite adapter has a file-backed worker/broker/backend workload that
exercises concurrent writer coordination:

```bash
cd packages/stem_sqlite
dart run benchmark/sqlite_throughput.dart --tasks 1000 --concurrency 4 \
  --check-baseline
```
