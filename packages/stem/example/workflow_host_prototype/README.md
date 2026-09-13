# Historical workflow host example

`workflow_host_prototype` is retained as a package and directory name for
existing commands. It is no longer an independent prototype: all workflow
hosting examples use the supported core `package:stem` `WorkflowHost`,
`HostedWorkflow`, and `HostedWorkflowContext` implementations. The
`lib/workflow_host.dart` entrypoint is only a compatibility re-export for
historical imports.

See the [main workflow host guide](../../doc/workflow_host.md) for the
supported API and lifecycle model.

```sh
cd packages/stem/example/workflow_host_prototype
dart pub get
dart run bin/main.dart
dart run bin/binary_codec.dart
dart test
dart analyze
```

Examples create an in-memory host, use it, and close it in `finally`. The core
host has no prototype-only `WorkflowHost.run` scope helper; this package's tests
use small test-local fixtures where that setup is repeated.

## Binary codec example

`lib/example_binary_codec.dart` implements a standard `dart:convert`
`Codec<BinaryMessage, Object?>`. Its custom format has magic bytes `42 4d`
(`BM`), version `01`, a four-byte unsigned big-endian UTF-8 length, and the
UTF-8 content. The decoder rejects invalid magic/version, truncation, trailing
bytes, and malformed UTF-8.

The binary executable registers that codec on the core host and uses it for
workflow input, output, and a named checkpoint. It also demonstrates a JSON
envelope round trip: JSON represents `Uint8List` as an integer list, so the
decoder explicitly reconstructs the byte buffer. This demonstrates codec
boundaries, not raw-binary transport or process-durable replay; the selected
backend must support the representation.

The tests retain useful assertions for typed DTOs, nullable checkpoint replay,
multiple submissions, result failures, shutdown behavior, codec registration,
adapter selection, and the CLI. Assertions that depended on the retired
prototype's eager result observation, object identity, or private scope
guarantees are intentionally not part of this example.
