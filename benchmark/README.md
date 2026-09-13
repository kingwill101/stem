# Stem benchmarks

Run the repeatable store-backed throughput workload from the repository root:

```bash
# AOT: uses the cached native repodoc executable.
devenv shell -- stem-benchmark \
  --tasks 5000 --concurrency 8 \
  --output .tmp/stem-throughput-aot.json
devenv shell -- stem-benchmark \
  --check-baseline --output .tmp/stem-throughput-aot-baseline.json

# JIT: runs the same repodoc command through `dart run`.
devenv shell -- stem-benchmark-jit \
  --tasks 5000 --concurrency 8 \
  --output .tmp/stem-throughput-jit.json
```

Both commands run the same workload and report the runtime in the terminal
table and JSON artifact as `aot` or `jit`. The AOT command is the CI regression
gate; JIT results are useful for separating Dart VM warmup and execution costs
from the compiled CLI path.

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
owns the repository-wide throughput benchmark entry point. Adapter packages
may also provide separate adapter-specific throughput benchmarks beside their
implementation because Redis, Postgres and SQLite contention have different
costs.

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

### Headless DevTools Profiler CLI / MCP

Use `devtools-profiler` to launch the workload and capture CPU samples and memory
snapshots without a browser. Pass the workload directly, not `profile:job` (which
compiles AOT) or `profile:job:vm` (which adds its own VM-service launch).

```bash
devtools-profiler run \
  --cwd "$PWD" \
  --artifact-dir build/stem-profile/devtools/inline-noop \
  --method-table \
  -- dart run benchmark/stem_job_profile.dart \
  --tasks 5000 --warmup 500 --concurrency 4 \
  --mode inline --workload noop --work-units 1 \
  --output build/stem-profile/devtools/inline-noop-workload.json

devtools-profiler summarize \
  --hide-sdk --hide-runtime-helpers --method-table \
  build/stem-profile/devtools/inline-noop
```

If the executable is not on `PATH`, an existing profiler checkout can be invoked
without changing global package activation:

```bash
dart run /path/to/devtools/packages/devtools_profiler_cli/bin/devtools_profiler.dart \
  run --cwd "$PWD" \
  --artifact-dir build/stem-profile/devtools/inline-noop \
  -- dart run benchmark/stem_job_profile.dart \
  --tasks 5000 --warmup 500 --concurrency 4 --mode inline --workload noop
```

The same tool can serve an MCP client over local stdio with
`devtools-profiler mcp`. Use the CLI when no MCP connection is configured; both
expose the same profiling capabilities. No network upload is needed.

Start with a repeated inline/no-op capture, then use the same task count,
warmup, and concurrency for isolate/no-op and isolate/CPU captures. Inspect the
coordinator and child isolates: selecting only the main isolate misses handler
CPU. Keep all-isolate CPU percentages distinct from single-isolate percentages.

The existing job workload reports measured-batch latency, but whole-session CPU
captures also include startup, warmup, and shutdown. Its warmup task count does
not clear profiler samples. Unattributed native samples must not be presented as
Stem CPU, and memory snapshot deltas are not allocation totals or proof of leaks.
Keep SDK frames in the raw capture; display filters help attribution but do not
establish end-to-end speedups.

Use separate unprofiled AOT repetitions to validate a proposed throughput change:

```bash
dart run tool/profile_job.dart \
  --tasks 5000 --warmup 500 --concurrency 4 \
  --mode inline --workload noop --work-units 1 \
  --repetitions 5 --output build/stem-profile/aot-inline-noop.json
```

The profiler's VM-service capture is JIT, not AOT. Do not compare its throughput
directly with AOT as if the difference were an optimization.

### Workflow profiling

Measure workflow orchestration separately from ordinary task dispatch:

```bash
devtools-profiler run \
  --cwd "$PWD" \
  --artifact-dir build/stem-profile/devtools/workflows \
  -- dart run benchmark/stem_workflow_profile.dart \
  --runs=1000 --warmup=100 --steps=5 --concurrency=4 \
  --timeout-seconds=120 \
  --output=build/stem-profile/devtools/workflows-workload.json
```

This uses standard `StemWorkflowApp.inMemory` and sequential script checkpoints,
not the experimental workflow host. It verifies completed run IDs, results, and
checkpoint execution counts. The measured phase includes run submission,
checkpoint execution, result observation (100 ms polling), and validation; it is
not a pure checkpoint-store microbenchmark. There are no synthetic sleeps or
external services.

JSON records UTC and `Timeline.now` boundaries for warmup and measured phases.
`stem.workflow.profile.warmup` and `stem.workflow.profile.measured` are Dart VM
`TimelineTask` markers, **not** automatic DevTools Profiler regions. Whole-session
summaries still include startup/warmup; when analyzing raw VM `CpuSamples`, select
samples whose `timestamp` falls between the measured `startedTimelineMicros` and
`finishedTimelineMicros` before recomputing counts. Preserve `vmTag` attribution:
runtime exception samples are not ordinary Dart execution samples.

Use `--help` for argument details. `--hold-seconds` holds only after cleanup and
is excluded from measured phase time. See `devtools_baseline.md` for initial
captures, limitations, and the first optimization candidates.

The SQLite adapter has a file-backed worker/broker/backend workload that
exercises concurrent writer coordination:

```bash
cd packages/stem_sqlite
dart run benchmark/sqlite_throughput.dart --tasks 1000 --concurrency 4 \
  --check-baseline
```
