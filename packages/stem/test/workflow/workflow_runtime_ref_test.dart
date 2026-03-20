import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _GreetingParams {
  const _GreetingParams({required this.name});

  factory _GreetingParams.fromJson(Map<String, dynamic> json) {
    return _GreetingParams(name: json['name']! as String);
  }

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}

class _GreetingResult {
  const _GreetingResult({required this.message});

  factory _GreetingResult.fromJson(Map<String, dynamic> json) {
    return _GreetingResult(message: json['message']! as String);
  }

  final String message;

  Map<String, Object?> toJson() => {'message': message};
}

const _greetingParamsCodec = PayloadCodec<_GreetingParams>.json(
  decode: _GreetingParams.fromJson,
  typeName: '_GreetingParams',
);

const _greetingResultCodec = PayloadCodec<_GreetingResult>.json(
  decode: _GreetingResult.fromJson,
  typeName: '_GreetingResult',
);

final _userUpdatedEvent = WorkflowEventRef<_GreetingParams>.json(
  topic: 'runtime.ref.event',
  decode: _GreetingParams.fromJson,
  typeName: '_GreetingParams',
);

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

        final runId = await workflowRef.start(
          workflowApp.runtime,
          params: const {'name': 'runtime'},
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

        final runId = await workflowRef.start(
          workflowApp.runtime,
          params: const {'name': 'runtime'},
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
      final workflowRef = flow.refCodec<_GreetingParams>(
        paramsCodec: _greetingParamsCodec,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final result = await workflowRef.startAndWait(
          workflowApp.runtime,
          params: const _GreetingParams(name: 'codec'),
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello codec');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('manual workflows can derive json-backed refs', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.json.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return 'hello $name';
          });
        },
      );
      final workflowRef = flow.refJson<_GreetingParams>();

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final result = await workflowRef.startAndWait(
          workflowApp.runtime,
          params: const _GreetingParams(name: 'json'),
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello json');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('manual workflows can derive versioned-json refs', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.versioned-json.flow',
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.requiredParam<String>('name');
            final version = ctx.requiredParam<int>(PayloadCodec.versionKey);
            return 'hello $name v$version';
          });
        },
      );
      final workflowRef = flow.refVersionedJson<_GreetingParams>(version: 2);

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final result = await workflowRef.startAndWait(
          workflowApp.runtime,
          params: const _GreetingParams(name: 'json'),
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello json v2');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'manual workflows can derive json-backed refs with result decoding',
      () async {
        final flow = Flow<_GreetingResult>(
          name: 'runtime.ref.json.ref-result.flow',
          build: (builder) {
            builder.step(
              'hello',
              (ctx) async => const _GreetingResult(message: 'hello ref json'),
            );
          },
        );
        final workflowRef = flow.refJson<_GreetingParams>(
          decodeResultJson: _GreetingResult.fromJson,
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          await workflowApp.start();

          final result = await workflowRef.startAndWait(
            workflowApp.runtime,
            params: const _GreetingParams(name: 'ignored'),
            timeout: const Duration(seconds: 2),
          );

          expect(result?.value?.message, 'hello ref json');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('codec-backed refs preserve workflow result decoding', () async {
      final flow = Flow<_GreetingResult>.codec(
        name: 'runtime.ref.codec.result.flow',
        resultCodec: _greetingResultCodec,
        build: (builder) {
          builder.step('hello', (ctx) async {
            final name = ctx.params['name'] as String? ?? 'world';
            return _GreetingResult(message: 'hello $name');
          });
        },
      );
      final workflowRef = flow.refCodec<_GreetingParams>(
        paramsCodec: _greetingParamsCodec,
      );

      final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
      try {
        await workflowApp.start();

        final result = await workflowRef.startAndWait(
          workflowApp.runtime,
          params: const _GreetingParams(name: 'codec'),
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value?.message, 'hello codec');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'raw workflow definitions expose direct codec result helpers',
      () async {
        final flow = WorkflowDefinition<_GreetingResult>.flowCodec(
          name: 'runtime.ref.definition.codec.result.flow',
          resultCodec: _greetingResultCodec,
          build: (builder) {
            builder.step(
              'hello',
              (ctx) async => const _GreetingResult(
                message: 'hello definition flow codec',
              ),
            );
          },
        );
        final script = WorkflowDefinition<_GreetingResult>.scriptCodec(
          name: 'runtime.ref.definition.codec.result.script',
          resultCodec: _greetingResultCodec,
          run: (context) async =>
              const _GreetingResult(message: 'hello definition script codec'),
        );

        final workflowApp = await StemWorkflowApp.inMemory();
        try {
          workflowApp.registerWorkflows([flow, script]);
          await workflowApp.start();

          final flowResult = await flow.ref0().startAndWait(
            workflowApp.runtime,
            timeout: const Duration(seconds: 2),
          );
          final scriptResult = await script.ref0().startAndWait(
            workflowApp.runtime,
            timeout: const Duration(seconds: 2),
          );

          expect(flowResult?.value?.message, 'hello definition flow codec');
          expect(
            scriptResult?.value?.message,
            'hello definition script codec',
          );
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('manual workflows can derive json-backed result decoding', () async {
      final flow = Flow<_GreetingResult>.json(
        name: 'runtime.ref.json.result.flow',
        decodeResult: _GreetingResult.fromJson,
        build: (builder) {
          builder.step(
            'hello',
            (ctx) async => const _GreetingResult(message: 'hello flow json'),
          );
        },
      );
      final script = WorkflowScript<_GreetingResult>.json(
        name: 'runtime.ref.json.result.script',
        decodeResult: _GreetingResult.fromJson,
        run: (context) async =>
            const _GreetingResult(message: 'hello script json'),
      );

      final workflowApp = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      try {
        await workflowApp.start();

        final flowResult = await flow.startAndWait(
          workflowApp.runtime,
          timeout: const Duration(seconds: 2),
        );
        final scriptResult = await script.startAndWait(
          workflowApp.runtime,
          timeout: const Duration(seconds: 2),
        );

        expect(flowResult?.value?.message, 'hello flow json');
        expect(scriptResult?.value?.message, 'hello script json');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test(
      'raw workflow definitions expose direct json result helpers',
      () async {
        final flow = WorkflowDefinition<_GreetingResult>.flowJson(
          name: 'runtime.ref.definition.json.result.flow',
          decodeResult: _GreetingResult.fromJson,
          build: (builder) {
            builder.step(
              'hello',
              (ctx) async =>
                  const _GreetingResult(message: 'hello definition flow json'),
            );
          },
        );
        final script = WorkflowDefinition<_GreetingResult>.scriptJson(
          name: 'runtime.ref.definition.json.result.script',
          decodeResult: _GreetingResult.fromJson,
          run: (context) async =>
              const _GreetingResult(message: 'hello definition script json'),
        );

        final workflowApp = await StemWorkflowApp.inMemory();
        try {
          workflowApp.registerWorkflows([flow, script]);
          await workflowApp.start();

          final flowResult = await flow.ref0().startAndWait(
            workflowApp.runtime,
            timeout: const Duration(seconds: 2),
          );
          final scriptResult = await script.ref0().startAndWait(
            workflowApp.runtime,
            timeout: const Duration(seconds: 2),
          );

          expect(flowResult?.value?.message, 'hello definition flow json');
          expect(scriptResult?.value?.message, 'hello definition script json');
        } finally {
          await workflowApp.shutdown();
        }
      },
    );

    test('manual workflows expose direct no-args helpers', () async {
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

      final workflowApp = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      try {
        await workflowApp.start();

        final flowResult = await flow.startAndWait(
          workflowApp,
          timeout: const Duration(seconds: 2),
        );
        final scriptRunId = await script.start(workflowApp.runtime);
        final scriptResult = await script.waitFor(
          workflowApp.runtime,
          scriptRunId,
          timeout: const Duration(seconds: 2),
        );

        expect(flowResult?.value, 'hello flow');
        expect(scriptResult?.value, 'hello script');
      } finally {
        await workflowApp.shutdown();
      }
    });

    test('workflow refs build explicit start calls', () async {
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
      final workflowApp = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      try {
        await workflowApp.start();

        final builtFlowCall = workflowRef.buildStart(
          params: const {'name': 'builder'},
        ).copyWith(
          ttl: const Duration(minutes: 5),
          parentRunId: 'parent-builder',
        );
        final runId = await workflowApp.runtime.startWorkflowCall(
          builtFlowCall,
        );
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

        final builtScriptCall = script.ref0().asRef.buildStart(
          params: (),
          cancellationPolicy: const WorkflowCancellationPolicy(
            maxRunDuration: Duration(seconds: 5),
          ),
        );
        final scriptRunId = await workflowApp.runtime.startWorkflowCall(
          builtScriptCall,
        );
        final oneShot = await builtScriptCall.definition.waitFor(
          workflowApp.runtime,
          scriptRunId,
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

    test('workflow refs build explicit workflow start calls', () async {
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

        final builtFlowCall = workflowRef.buildStart(
          params: const {'name': 'builder'},
        ).copyWith(
          ttl: const Duration(minutes: 5),
          parentRunId: 'parent-bound',
        );
        final runId = await workflowApp.runtime.startWorkflowCall(
          builtFlowCall,
        );
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

        final builtScriptCall = scriptRef.asRef.buildStart(
          params: (),
          cancellationPolicy: const WorkflowCancellationPolicy(
            maxRunDuration: Duration(seconds: 5),
          ),
        );
        final scriptRunId = await workflowApp.runtime.startWorkflowCall(
          builtScriptCall,
        );
        final oneShot = await builtScriptCall.definition.waitFor(
          workflowApp.runtime,
          scriptRunId,
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
            final payload = _userUpdatedEvent.waitValue(ctx);
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

        final runId = await flow.ref0().start(workflowApp);
        await workflowApp.runtime.executeRun(runId);

        await _userUpdatedEvent.emit(
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
              final payload = await _userUpdatedEvent.wait(ctx);
              return 'hello ${payload.name}';
            });
          },
        );

        final workflowApp = await StemWorkflowApp.inMemory(flows: [flow]);
        try {
          await workflowApp.start();

          final runId = await flow.ref0().start(workflowApp);
          await workflowApp.runtime.executeRun(runId);

          await _userUpdatedEvent.emit(
            workflowApp,
            const _GreetingParams(name: 'call'),
          );
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

    test('workflow event emitters expose bound event calls', () async {
      final flow = Flow<String>(
        name: 'runtime.ref.event.bound.flow',
        build: (builder) {
          builder.step('wait', (ctx) async {
            final payload = _userUpdatedEvent.waitValue(ctx);
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

        final runId = await flow.ref0().start(workflowApp);
        await workflowApp.runtime.executeRun(runId);

        expect(_userUpdatedEvent.topic, 'runtime.ref.event');

        await _userUpdatedEvent.emit(
          workflowApp,
          const _GreetingParams(name: 'bound'),
        );
        await workflowApp.runtime.executeRun(runId);

        final result = await workflowApp.waitForCompletion<String>(
          runId,
          timeout: const Duration(seconds: 2),
        );

        expect(result?.value, 'hello bound');
      } finally {
        await workflowApp.shutdown();
      }
    });
  });
}
