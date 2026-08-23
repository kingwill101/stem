# Stem benchmarks

Run the repeatable in-memory throughput workload from the repository root:

```bash
devenv shell -- repodoc benchmark:throughput --tasks 5000 --concurrency 8
devenv shell -- repodoc benchmark:throughput --check-baseline
```

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
