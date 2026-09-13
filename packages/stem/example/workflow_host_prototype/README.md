# Function-first workflow host prototype

This standalone **experiment**, not a stable Stem API, hosts ordinary Dart async
functions on one `StemWorkflowApp.inMemory` runtime and worker. No broker,
scheduler, or replacement retry protocol was added.

```sh
cd packages/stem/example/workflow_host_prototype
dart pub get
dart run bin/main.dart
dart test
dart analyze
```

The CLI submits two runs on one host and uses ordinary `if` logic. It exits
nonzero on failure and closes its owned resources before returning.

## Proposed surface

- `HostedWorkflow<I, R>(name:, run:)` defines a typed
  function, lowered to the existing `WorkflowScript<R>` (the same runtime used
  by `Flow`). The input is stored in a private `input` envelope so scalar and
  nullable inputs still travel through Stem's map-based start parameters.
- `flow.step<T>(name, body)` checkpoints a local async or synchronous
  closure. Values are encoded in a non-null envelope, including nullable values.
- `await WorkflowHost.inMemory(workflows: [...])` starts one reusable owned app.
- `await host.execute(definition, input)` returns `R`.
- `await host.submit(definition, input)` returns `HostedRun<R>` with `id` and
  `Future<R> result`. Result observation begins immediately. Ignoring a handle
  does not cause an unhandled background error, but callers must await its
  result to learn about failure.
- `await host.close()` rejects new submissions, joins submissions still
  starting, stops outstanding result observations with `StateError`, then
  delegates worker/resource shutdown to the existing app. It is idempotent.
- `WorkflowHost.run(workflows:, body:)` wraps creation and `try/finally` close.
  Await needed results inside the scope, not after it closes.
- Optional host `resultTimeout` bounds result observation, using existing
  `waitForCompletion` calls in 100 ms windows. It does not cancel the workflow.

Registration is fixed at host creation; submission requires the same definition
instance. Duplicate names are rejected. Names deliberately avoid the existing
`Stem` class. This is not a dynamic closure-registration service.

## Serialization without primitive boilerplate

```dart
final greeting = HostedWorkflow<String, String>(
  name: 'greeting',
  run: (flow, name) async {
    final cleaned = await flow.step('normalize-name', () => name.trim());
    return cleaned.isEmpty ? 'Hello, stranger!' : 'Hello, $cleaned!';
  },
);
await WorkflowHost.run<void>(
  workflows: [greeting],
  body: (host) async => print(await host.execute(greeting, ' Ada ')),
);
```

For DTOs, implement standard `Codec<Request, Object?>` and
`Codec<Receipt, Object?>` classes with `encoder`/`decoder` converters, then
register them once:

```dart
final codecs = PayloadCodecRegistry()
  ..register<Request>(RequestCodec())
  ..register<Receipt>(ReceiptCodec());
await WorkflowHost.run<void>(
  workflows: [checkout], // HostedWorkflow<Request, Receipt>
  codecs: codecs,
  body: (host) async {
    final receipt = await host.execute(checkout, request);
    print(receipt);
  },
);
```

The same registrations cover `Request?`, `Receipt?`, and named steps returning
those types. A codec should return its JSON map/list/scalar directly, rather than
calling `jsonEncode` itself. Decoder construction is explicit: code generation
can generate a converter, but a generic type parameter cannot discover a static
`fromJson` constructor.

## Runnable custom binary codec

```sh
dart run bin/binary_codec.dart
dart test test/example_binary_codec_test.dart
```

`lib/example_binary_codec.dart` implements a standard `dart:convert`
`Codec<BinaryMessage, Object?>` whose encoder produces real `Uint8List` bytes.
This is a minimal **custom format, not a protobuf or CBOR implementation**:
two magic bytes `42 4d` (ASCII `BM`), one version byte (`01`), a four-byte
unsigned big-endian UTF-8 byte length, then exactly that many UTF-8 bytes.
The decoder rejects bad magic, unknown versions, truncated headers/content,
trailing bytes, and malformed UTF-8.

The executable registers the codec once on `WorkflowHost`; the typed workflow
input, output, and named checkpoint use it without per-boundary encoders.
Reusing the checkpoint name demonstrates decoding a saved value without running
the body again. The original primitive greeting remains `bin/main.dart`.

It also demonstrates an actual `jsonEncode`/`jsonDecode` envelope round trip:
JSON represents the bytes as an integer list, not a binary buffer. The decoder
explicitly reconstructs `Uint8List`, first requiring every element to be an
integer in `0..255` (no coercion or silent truncation). Tests separately exercise
this persistence representation and a real in-memory host/checkpoint run.
This does **not** establish raw-binary broker transport or process-durable replay;
the selected backend still has to support the codec's representation.

Only this prototype host automatically resolves default/shared registry codecs
across its boundaries. Existing core APIs accept codecs explicitly; this example
does not add automatic global registry injection to them.

## Actual guarantees and limits

- This is **memory-only, not process-durable**. `stem_memory` currently reexports
  Stem's in-memory adapters; `StemWorkflowApp.inMemory` already selects those
  adapters. Importing it does not require a separate backend configuration.
- Named steps are **local checkpoints, not remote activities**. Completed
  checkpoint data can be replayed by the existing script runtime. Reusing a
  name within a run reads that checkpoint; use distinct stable names for
  logically distinct operations, including loop iterations.
- The host uses the shared, optional `PayloadCodecRegistry` from Stem. It takes
  an immutable snapshot at creation. Register standard `dart:convert`
  `Codec<T, Object?>` instances once with `register<T>(codec)` and pass
  `codecs:` to `WorkflowHost.inMemory` or `WorkflowHost.run`. The host uses those
  codecs for workflow input, result, and named-step checkpoints. Registration
  also supports `T?`, preserving null without invoking the non-null codec.
  Explicit registrations override built-in defaults, including primitive types.
  A second explicit registration or nullable-key collision fails atomically.
  This is per-type configuration, not a global CBOR/protobuf transport selector.
- Defaults cover `String`, `bool`, `int`, `double`, `num`, `Null`, `Object`,
  `List<Object?>`, `Map<String, Object?>`, and their nullable forms. These default
  codecs require finite JSON trees with string map keys; nested DTOs, cycles, and
  non-finite numbers are rejected. No reflection, automatic `toJson`, or
  `fromJson` discovery occurs.
- Specific collections such as `List<String>`, `List<Receipt>`, and
  `Map<String, int>` require explicit codecs to reconstruct their elements.
  Casting a JSON-decoded `List<dynamic>` to `List<T>` is not a generic decoder.
- JSON codec output is a JSON-compatible value, not an extra JSON string nested
  in the payload. Optional `inputCodec:`, `resultCodec:`, and step `codec:` overrides
  accept standard codecs for boundary-specific representations. These explicit
  overrides and registered custom codecs own their wire representation and must
  produce values supported by the selected backend.
  `PayloadCodec` remains usable as a backward-compatible standard codec.
- Standard codecs can implement CBOR, protobuf, or other formats; the registry
  does not impose JSON validation on custom codecs. This does not add raw binary
  transport to Stem. Workflow input and checkpoint envelopes remain maps, and
  persistent adapters may JSON-encode those maps. A `Uint8List` can become a JSON
  list of integers, then decode as `List<dynamic>` rather than `Uint8List`.
  A byte codec must explicitly reconstruct the buffer (or use a documented
  base64 representation). Backend-compatible serialization is required;
  preserving byte-buffer runtime identity is not guaranteed.
- Ordinary code outside checkpoints may run again on replay. Side effects in a
  checkpoint can repeat if execution fails before the checkpoint is saved.
  No exactly-once or additional retry guarantees are provided.
- Terminal failed/cancelled states become `HostedWorkflowFailure` with persisted
  status/error, not the original Dart exception and stack. Ordinary script
  errors retain the runner's five retries; only exhausted failure terminalizes
  the workflow. This is core worker/runtime behavior, not a host timeout.
- Close is not workflow cancellation. Outstanding observers stop promptly;
  execution/resource shutdown follows the existing worker shutdown behavior.
  There is no forced execution timeout, suspension API, remote worker
  routing, task-result await API, resume-by-ID, or durable host recovery here.
- Durable task-result suspension/routing remains a design gap: enqueueing and
  blocking for a task result can deadlock a single worker. Stable task IDs alone
  do not guarantee deduplicated publication. This prototype does not implement
  or imply `ctx.call` semantics.

Tests cover codecs, nullable checkpoint replay within one run, multiple
submissions, shutdown races, scope cleanup, adapter selection and a real CLI
subprocess exiting. The throwing-script test awaits genuine terminal failure
through all five default backoff retries (allow up to three minutes).
Tests do not establish crash recovery or
cross-process replay.

## Failure propagation

`executeRun` records attempt errors without making the workflow terminal, so
checkpoint replay and later successful retries remain possible. Once the worker
classifies the runner task as terminally failed, its awaited
`TaskTerminalFailureHandler` finalizes the workflow before settling the delivery.
Lease-conflict retry requests retain their separate, larger retry budget.

The callback is idempotent and retried on terminal task redelivery if finalization
fails; user workflow code is not rerun for that redelivery. Task status and
workflow state are separate writes, not a transaction. This memory-only host
does not provide recovery after process loss.

The worker retains the original failed envelope in trusted task-status metadata,
so finalization uses the original arguments even if a redelivery changes them.
After signature verification, finalization precedes expiry/revocation handling.
Successful callbacks may repeat on later redelivery; they are not exactly-once.

An optional observation timeout still throws `TimeoutException` including the
latest status/error, and does not cancel execution or substitute for terminal
failure. A timeout shorter than retry backoff may observe a still-running run.
