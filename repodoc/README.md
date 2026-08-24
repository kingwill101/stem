# repodoc

The private repository-maintenance CLI for Stem. It is the central source for
workspace discovery, dependency resolution, quality checks, tests, coverage,
examples, standalone dependency resolution, repeatable job profiling, and
store-backed throughput benchmarking.

Repodoc requires Dart 3.10.0 or newer. The repository's recommended devenv
environment remains the easiest way to provision the supported toolchain.

Use it through devenv when possible:

```bash
devenv shell
stem-workspace
stem-quality
stem-coverage
stem-standalone
stem-standalone-flutter
stem-test
stem-profile --tasks 10000 --warmup 1000 --concurrency 8 \
  --mode isolate --workload cpu --work-units 250
```

The direct form is useful for contributors who do not use devenv:

```bash
dart run repodoc/bin/repodoc.dart workspace:check
dart run repodoc/bin/repodoc.dart quality:dart
dart run repodoc/bin/repodoc.dart standalone:dart
dart run repodoc/bin/repodoc.dart standalone:flutter
dart run repodoc/bin/repodoc.dart test:all
dart run repodoc/bin/repodoc.dart coverage
dart run repodoc/bin/repodoc.dart demo:all
dart run repodoc/bin/repodoc.dart benchmark:throughput --check-baseline
dart run repodoc/bin/repodoc.dart benchmark:throughput \
  --stores memory,sqlite,postgres,redis --buckets 4,8,16
```

Throughput benchmarks run directly from repodoc. Use `--buckets` for a
concurrency sweep, for example `--buckets 4,8,16`; use `--json` for a
machine-readable report. Use `--store postgres` or `--store redis` for a
single external store, with the connection URLs supplied by devenv or the
corresponding command options. Add `--verbose` to trace store connection and
worker lifecycle stages to stderr. Add `--timings` to a PostgreSQL run to
report broker/backend operation latency and serialized connection-queue wait.

Commands are grouped by subsystem in `lib/src/commands/`. Shared workspace and
process utilities live in `lib/src/infrastructure/`.

## Taskfile migration

The root `Taskfile.yml` is a compatibility layer only. Every root maintenance
operation is implemented here and the compatibility aliases invoke `repodoc`
directly; repodoc never invokes `task`, parses a Taskfile, or depends on
go-task.

The former root operations map to these commands:

| Former operation | Repodoc command |
| --- | --- |
| `deps` | `deps` |
| `quality:dart` | `quality:dart` |
| `standalone:dart` | `standalone:dart` |
| `standalone:flutter` | `standalone:flutter` |
| `test`, `test:no-env`, `test:flutter`, `test:all` | matching `test:*` command |
| `test:contract`, `test:redis`, `test:postgres` | matching `test:*` command |
| package `test` tasks | `test:package --package <path>` |
| package `coverage` tasks | `coverage:package --package <path>` |
| `coverage`, `coverage:no-env` | matching `coverage:*` command |
| throughput benchmark | `benchmark:throughput` |
| `demo:*` | matching `demo:*` command |
| `profile:job*` | matching `profile:job:*` command |

Use `repodoc --help` for the complete command surface. The devenv scripts and
CI call these same commands, so local and CI maintenance no longer depends on
Task execution.

Repodoc keeps temporary staging, compilation, and profiling files under the
repository-local `.tmp/` directory. It sets `TMP`, `TMPDIR`, and `TEMP` for
child processes so they do not fall back to the host `/tmp` filesystem.
