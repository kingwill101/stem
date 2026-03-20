import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _GreetingParams {
  const _GreetingParams({required this.name});

  factory _GreetingParams.fromJson(Map<String, Object?> json) {
    return _GreetingParams(name: json['name']! as String);
  }

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}

class _GreetingResult {
  const _GreetingResult({required this.message});

  factory _GreetingResult.fromJson(Map<String, Object?> json) {
    return _GreetingResult(message: json['message']! as String);
  }

  final String message;

  Map<String, Object?> toJson() => {'message': message};
}

const _greetingParamsCodec = PayloadCodec<_GreetingParams>(
  encode: _encodeGreetingParams,
  decode: _decodeGreetingParams,
);

const _greetingResultCodec = PayloadCodec<_GreetingResult>(
  encode: _encodeGreetingResult,
  decode: _decodeGreetingResult,
);

const _userUpdatedEvent = WorkflowEventRef<_GreetingParams>(
  topic: 'runtime.ref.event',
  codec: _greetingParamsCodec,
);

Object? _encodeGreetingParams(_GreetingParams value) => value.toJson();

_GreetingParams _decodeGreetingParams(Object? payload) {
  return _GreetingParams.fromJson(
    Map<String, Object?>.from(payload! as Map),
  );
}

Object? _encodeGreetingResult(_GreetingResult value) => value.toJson();

_GreetingResult _decodeGreetingResult(Object? payload) {
  return _GreetingResult.fromJson(Map<String, Object?>.from(payload! as Map));
}

void main() {
  group('runtime workflow refs', () {
    test('start and wait helpers work directly with WorkflowRuntime', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final workflowRef = flow.ref<Map<String, Object?>>(
        encodeParams: (params) => params,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final runId = await workflowRef.startWith(
          workflowApp.runtime,
          const {'name': 'runtime'},
        );
        final waited = await workflowApp.runtime.waitForWorkflowRef(
          runId,
          workflowRef,
          timeout: const Duration(seconds: 2),
        );

        expect(waited?.value, 'hello runtime');

        final inlineRunId = await workflowApp.runtime.startWorkflowRef(
          workflowRef,
          const {'name': 'inline'},
        );
        final oneShot = await workflowApp.runtime.waitForCompletion<String>(
          inlineRunId,
          timeout: const Duration(seconds: 2),
          decode: workflowRef.decode,
        );

        expect(oneShot?.value, 'hello inline');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('manual workflow scripts can derive typed refs', () async {
      final script = WorkflowScript<String>(
        name: 'runtime.ref.script',
        run: (context) async {
          final name = context.params['name'] as String? ?? 'world';
          return 'script $name';
        },
      );
      final workflowRef = script.ref<Map<String, Object?>>(
        encodeParams: (params) => params,
      );

      final workflowApp = await StemWorkflowApp.inMemory(scripts: [script]);
      try {
        await workflowApp.start();

        final runId = await workflowRef.startWith(
          workflowApp.runtime,
          const {'name': 'runtime'},
        );
        final waited = await workflowRef.waitFor(
          workflowApp.runtime,
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(waited?.value, 'script runtime');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('manual workflows can derive codec-backed refs', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.codec.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final workflowRef = flow.refWithCodec<_GreetingParams>(
        paramsCodec: _greetingParamsCodec,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final result = await workflowRef.startAndWaitWith(
          workflowApp.runtime,
          const _GreetingParams(name: 'codec'),
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello codec');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('codec-backed refs preserve workflow result decoding', () async {
      final flow = Flow<_GreetingResult>(
        name: 'runtime.ref.codec.result.flow',
        resultCodec: _greetingResultCodec,
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return _GreetingResult(message: 'hello $name');
          });
        },
      );
      final workflowRef = flow.refWithCodec<_GreetingParams>(
        paramsCodec: _greetingParamsCodec,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final result = await workflowRef.startAndWaitWith(
          workflowApp.runtime,
          const _GreetingParams(name: 'codec'),
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value?.message, 'hello codec');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('manual workflows can derive no-args refs', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.no-args.flow',
        build: (builder) {
          builder.step('hello', (ctx) async => 'hello flow');
        },
      );
      final script = WorkflowScript<String>(
        name: 'runtime.ref.no-args.script',
        run: (context) async => 'hello script',
      );

      final flowRef = flow.ref0();
      final scriptRef = script.ref0();

      final workflowApp = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      try {
        await workflowApp.start();

        final flowResult = await flowRef.startAndWaitWith(
          workflowApp,
          timeout: const Duration(seconds: 2),
        );
        final scriptResult = await scriptRef.startAndWaitWith(
          workflowApp.runtime,
          timeout: const Duration(seconds: 2),
        );

        expect(flowResult?.value, 'hello flow');
        expect(scriptResult?.value, 'hello script');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('workflow refs expose fluent start builders', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.builder.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final script = WorkflowScript<String>(
        name: 'runtime.ref.builder.script',
        run: (context) async => 'hello script',
      );

      final workflowRef = flow.ref<Map<String, Object?>>(
        encodeParams: (params) => params,
      );
      final scriptRef = script.ref0();

      final workflowApp = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      try {
        await workflowApp.start();

        final flowBuilder = workflowRef
            .startBuilder(const {'name': 'builder'})
            .ttl(const Duration(minutes: 5))
            .parentRunId('parent-builder');
        final builtFlowCall = flowBuilder.build();
        final runId = await flowBuilder.startWith(workflowApp.runtime);
        final result = await workflowRef.waitFor(
          workflowApp.runtime,
          runId,
          timeout: const Duration(seconds: 2),
        );
        final state = await workflowApp.getRun(runId);

        expect(builtFlowCall.parentRunId, 'parent-builder');
        expect(builtFlowCall.ttl, const Duration(minutes: 5));
        expect(result?.value, 'hello builder');
        expect(state?.parentRunId, 'parent-builder');

        final scriptBuilder = scriptRef.startBuilder().cancellationPolicy(
          const WorkflowCancellationPolicy(
            maxRunDuration: Duration(seconds: 5),
          ),
        );
        final builtScriptCall = scriptBuilder.build();
        final oneShot = await scriptBuilder.startAndWaitWith(
          workflowApp.runtime,
          timeout: const Duration(seconds: 2),
        );

        expect(
          builtScriptCall.cancellationPolicy?.maxRunDuration,
          const Duration(seconds: 5),
        );
        expect(oneShot?.value, 'hello script');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('workflow callers expose bound workflow builders', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.bound.builder.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final script = WorkflowScript<String>(
        name: 'runtime.ref.bound.builder.script',
        run: (context) async => 'hello script',
      );

      final workflowRef = flow.ref<Map<String, Object?>>(
        encodeParams: (params) => params,
      );
      final scriptRef = script.ref0();

      final workflowApp = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      try {
        await workflowApp.start();

        final flowBuilder = workflowApp.runtime
            .startWorkflowBuilder(
              definition: workflowRef,
              params: const {'name': 'builder'},
            )
            .ttl(const Duration(minutes: 5))
            .parentRunId('parent-bound');
        final builtFlowCall = flowBuilder.build();
        final runId = await flowBuilder.start();
        final result = await workflowRef.waitFor(
          workflowApp.runtime,
          runId,
          timeout: const Duration(seconds: 2),
        );
        final state = await workflowApp.getRun(runId);

        expect(builtFlowCall.parentRunId, 'parent-bound');
        expect(builtFlowCall.ttl, const Duration(minutes: 5));
        expect(result?.value, 'hello builder');
        expect(state?.parentRunId, 'parent-bound');

        final scriptBuilder = workflowApp.runtime
            .startNoArgsWorkflowBuilder(definition: scriptRef)
            .cancellationPolicy(
              const WorkflowCancellationPolicy(
                maxRunDuration: Duration(seconds: 5),
              ),
            );
        final builtScriptCall = scriptBuilder.build();
        final oneShot = await scriptBuilder.startAndWait(
          timeout: const Duration(seconds: 2),
        );

        expect(
          builtScriptCall.cancellationPolicy?.maxRunDuration,
          const Duration(seconds: 5),
        );
        expect(oneShot?.value, 'hello script');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('typed workflow events emit directly from the event ref', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.event.flow',
        build: (builder) {
          builder.step('wait', (ctx) async {
            final payload = ctx.waitForEventRef(_userUpdatedEvent);
            if (payload == null) {
              return null;
            }
            return 'hello ${payload.name}';
          });
        },
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final runId = await flow.ref0().startWith(workflowApp);
        await workflowApp.runtime.executeRun(runId);

        await _userUpdatedEvent.emitWith(
          workflowApp,
          const _GreetingParams(name: 'event'),
        );
        await workflowApp.runtime.executeRun(runId);

        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello event');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'typed workflow event calls emit from the prebuilt call surface',
      () async {
        final flow = Flow<String>(
          name: 'runtime.ref.event.call.flow',
          build: (builder) {
            builder.step('wait', (ctx) async {
              final payload = ctx.waitForEventRef(_userUpdatedEvent);
              if (payload == null) {
                return null;
              }
              return 'hello ${payload.name}';
            });
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          await workflowApp.start();

          final runId = await flow.ref0().startWith(workflowApp);
          await workflowApp.runtime.executeRun(runId);

          await _userUpdatedEvent
              .call(const _GreetingParams(name: 'call'))
              .emitWith(workflowApp);
          await workflowApp.runtime.executeRun(runId);

          final result = await workflowApp.waitForCompletion<String>(
            runId,
            timeout: const Duration(seconds: 2),
          );

          expect(result?.value, 'hello call');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );
  });
}
