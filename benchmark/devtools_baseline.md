# Initial DevTools Profiler baseline

This is a diagnostic baseline, not a performance regression threshold or an
optimization result. Source revision: `0dfc1713` (only the pending changelog and
profiling documentation/harness work differ). Captured with the local
`devtools_profiler_cli` checkout reporting version `0.5.2`, Dart 3.13.1 JIT on
Linux x64, with eight logical processors. The profiler checkout is not pinned,
so exact profiler behavior may differ elsewhere.

## Captures

Every scenario uses the existing `stem_job_profile.dart` workload, the memory
broker/backend, 5,000 measured tasks, 500 warmup tasks, and concurrency four.
Captures ran sequentially; no production optimization was applied between runs.
Raw artifacts are local, ignored output under
`build/stem-profile/devtools-baseline/`, not committed source.

| Artifact subdirectory | Workload | Measured batch | Tasks/s | Queue median | Execution median |
| --- | --- | ---: | ---: | ---: | ---: |
| `inline-noop` | Inline, no-op | 6.658 s | 751 | 1.622 ms | 0.813 ms |
| `inline-noop-repeat` | Same inline baseline | 4.720 s | 1,059 | 1.029 ms | 0.520 ms |
| `isolate-noop` | Isolate, no-op | 5.592 s | 894 | 2,722.842 ms | 2.174 ms |
| `isolate-cpu` | Isolate, 250 SHA-256 work units | 5.764 s | 867 | 2,835.212 ms | 2.632 ms |

The inline repeat differs substantially without a source change. These are
single diagnostic captures, not a statistically stable throughput estimate.
The coordinator enqueues much faster in the isolate cases, creating a backlog;
their queue latency is not an isolated measurement of message-passing cost.

## First investigation target: tracing acquisition

`StemTracer._obtainTracer` accounts for 16.1% and 15.3% inclusive samples in the
two inline captures. `OTel._getAndCacheOtelFactory` accounts for 11.3% and 10.1%
self samples, with `APITracerProvider.getTracer` contributing another 3.9% and
4.0% self samples. The acquisition path remains visible in both isolate cases.

These percentages use **all captured samples**, not just attributed Dart samples,
and inclusive values overlap. The lookup path in
`packages/stem/lib/src/observability/tracing.dart` obtains a tracer on every
trace operation before checking whether that tracer is enabled.

Next: investigate API-only versus SDK-initialized behavior, fallback exceptions,
and repeated provider lookup. Any cache/fast-path experiment must preserve
zone-local trace context, late initialization, and provider replacement.
Do not simply cache one tracer permanently or disable observability to claim a
runtime improvement.

Read-only tracing of the installed Dartastic 0.10.0 dependency identifies a
plausible mechanism: the SDK `OTel.tracerProvider()` expects an SDK provider,
whereas an API-only/no-op factory supplies an API provider. Stem first tries the
SDK path and catches `TypeError`/`StateError` before obtaining the API tracer.
Both providers already cache tracer instances; repeated acquisition can still
repeat factory lookup, validation, and the fallback exception path. This source
analysis does not count exceptions in the captured runs.

The first A/B candidate is resolving through the appropriate provider without
repeated fallback, or caching the tracer keyed by the current factory identity.
The factory is global within an isolate in this dependency version; ambient
trace context is zone-local and must still be read per operation. Test late SDK
initialization, factory reset/replacement, shutdown, and separate parent-span
zones before accepting any candidate.

## Workflow capture and measured-window attribution

The new `stem_workflow_profile.dart` workload completed 1,000 measured workflows,
each with five sequential checkpoints, after 100 warmup workflows. Concurrency
was four. All 5,000 measured checkpoints executed with the expected results.

- Measured enqueue time: 2.017 s.
- Measured end-to-end time: 3.346 s, or 299 workflows/s.
- Whole-session profiler duration: 23.98 s, with 82.1% native `unknown` samples
  in the profiler summary. That percentage is not a steady-state runtime cost.
- Artifacts: `workflow-five-steps/`, `workflow-five-steps-workload.json`, and
  the locally derived `workflow-measured-cpu.json`.

Filtering the raw `CpuSamples.samples` by the measured phase's VM timeline
timestamps retains 2,744 samples. Counting each function once per stack for
inclusive attribution, with the first stack entry as the leaf, shows:

| Frame | Attribution | Measured-window samples |
| --- | --- | ---: |
| `StemTracer.trace` | Inclusive | 16.4% |
| Workflow script `step` | Inclusive | 14.8% |
| `StemTracer._obtainTracer` | Inclusive | 11.4% |
| `WorkflowRuntime._enqueueRun` | Inclusive | 11.2% |
| `Signal.emit` | Leaf | 6.9% |
| `TaskSuccessPayload` construction | Leaf | 4.5% |

These values overlap and are sampled stack attribution, not independent costs
that can be added. In particular, 288 measured-window samples carry VM tag
`DRT_Throw` with `_getAndCacheOtelFactory` as the leaf (10.5% of the window).
This supports investigating the tracing exception path in a real workflow
workload, not just the no-op task benchmark. It does **not** mean 288 exceptions
occurred, or prove that removing the path yields a 10.5% throughput gain.

Signal dispatch/payload construction and checkpoint bookkeeping are secondary
investigation targets. First determine subscriber/telemetry configuration and
allocation behavior; do not suppress signals or validation to claim a speedup.
Result polling and deterministic-result validation remain part of this harness.

## Separate unprofiled AOT baseline

Five fresh AOT processes ran the same inline/no-op task scenario without
DevTools instrumentation:

- End-to-end tasks/s: 6,198; 6,739; 7,410; 7,648; 5,840.
- Median: 6,739 tasks/s; median batch time: 741.91 ms.
- Median post-workload RSS: 62,418,944 bytes.
- Artifact: `aot-inline-noop.json`.

These trials are not a before/after optimization comparison with the JIT
captures. The range also shows that controlled repetitions remain necessary.

## Other observations

- The CPU workload captures five isolates (coordinator plus four execution
  isolates), and its handler is visible: `_cpuProfileEntrypoint` contributes
  25.6% inclusive samples; hashing dominates its callees. The capture therefore
  includes actual child-isolate work rather than coordinator-only sampling.
- Whole-session native `unknown` samples are 63.1%, 66.5%, 74.6%, and 50.1%
  respectively. Their cause is not established; do not assign them to Stem or
  infer idle time from them.
- End heap snapshots are roughly 36 MiB for inline captures and 279–295 MiB
  across the isolate captures. These include JIT/runtime structures, retained
  benchmark statuses, and profiler exit-pause effects. They do **not** establish
  a leak or an application memory budget.
- Isolate captures reported resume warnings for exit-paused isolates already
  collected during cleanup. Targets exited successfully and CPU/memory artifacts
  were written, but teardown measurements require caution.
- Whole-session capture durations (13.7–21.0 s) exceed the measured batch times.
  There are no explicit profiler regions in the existing job workload. Startup,
  warmup, and shutdown cannot be attributed to the steady-state batch from the
  summary alone.

## Next measurements

1. Capture explicit post-warmup phases and inspect per-isolate CPU/allocation
   data. Repeat enough runs to characterize baseline variance.
2. Validate any tracing experiment with identical captures and independent
   unprofiled AOT repetitions; test telemetry configuration changes for
   correctness.
3. Profile fixed-count, fixed-checkpoint workflows separately from ordinary tasks.
   Deliberate sleeps and per-run observation polling must be distinguished from
   checkpoint execution cost.
4. Profile SQLite and external adapters separately. These memory-only captures
   do not establish database, network, lease contention, or mobile bottlenecks.

See `README.md` for reproducible CLI/MCP setup and AOT commands.
