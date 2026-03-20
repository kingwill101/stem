import 'package:contextual/contextual.dart' show Level, LogDriver, LogEntry;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBroker broker;
  late InMemoryResultBackend backend;
  late InMemoryTaskRegistry registry;
  late Stem stem;
  late InMemoryWorkflowStore store;
  late WorkflowRuntime runtime;
  late FakeWorkflowClock clock;
  late _RecordingWorkflowIntrospectionSink introspection;

  setUp(() {
    broker = InMemoryBroker();
    backend = InMemoryResultBackend();
    registry = InMemoryTaskRegistry();
    stem = Stem(broker: broker, registry: registry, backend: backend);
    clock = FakeWorkflowClock(DateTime.utc(2024));
    store = InMemoryWorkflowStore(clock: clock);
    introspection = _RecordingWorkflowIntrospectionSink();
    runtime = WorkflowRuntime(
      stem: stem,
      store: store,
      eventBus: InMemoryEventBus(store),
      clock: clock,
      pollInterval: const Duration(milliseconds: 25),
      leaseExtension: const Duration(seconds: 5),
      introspectionSink: introspection,
    );
    registry.register(runtime.workflowRunnerHandler());
  });

  tearDown(() async {
    await runtime.dispose();
    broker.dispose();
  });

  test('executes workflow and persists results', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'demo.workflow',
        build: (flow) {
          flow
            ..step('prepare', (context) async => 'ready')
            ..step(
              'finish',
              (context) async => '${context.previousResult}-done',
            );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('demo.workflow');
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.completed);
    expect(state?.result, 'ready-done');
    expect(await store.readStep<String>(runId, 'prepare'), 'ready');
    expect(await store.readStep<String>(runId, 'finish'), 'ready-done');
  });

  test(
    'startWorkflow persists runtime metadata and strips internal params',
    () async {
      runtime.registerWorkflow(
        Flow(
          name: 'metadata.workflow',
          build: (flow) {
            flow.step('inspect', (context) async => context.params['tenant']);
          },
        ).definition,
      );

      final runId = await runtime.startWorkflow(
        'metadata.workflow',
        params: const {'tenant': 'acme'},
      );

      final state = await store.get(runId);
      expect(state, isNotNull);
      expect(
        state!.params.containsKey(workflowRuntimeMetadataParamKey),
        isTrue,
      );
      expect(state.workflowParams, equals(const {'tenant': 'acme'}));
      expect(state.orchestrationQueue, equals(runtime.queue));
      expect(state.executionQueue, equals(runtime.executionQueue));
      expect(
        state.workflowParams.containsKey(workflowRuntimeMetadataParamKey),
        isFalse,
      );
      expect(
        state.workflowParams.containsKey(workflowParentRunIdParamKey),
        isFalse,
      );
      expect(introspection.runtimeEvents, isNotEmpty);
      expect(
        introspection.runtimeEvents.last.type,
        equals(WorkflowRuntimeEventType.continuationEnqueued),
      );
    },
  );

  test(
    'startWorkflow persists parent run id without exposing it to handlers',
    () async {
      runtime.registerWorkflow(
        Flow(
          name: 'parent.runtime.workflow',
          build: (flow) {
            flow.step('inspect', (context) async => context.params);
          },
        ).definition,
      );

      final runId = await runtime.startWorkflow(
        'parent.runtime.workflow',
        parentRunId: 'wf-parent',
        params: const {'tenant': 'acme'},
      );

      final state = await store.get(runId);
      expect(state, isNotNull);
      expect(state!.parentRunId, 'wf-parent');
      expect(state.workflowParams, equals(const {'tenant': 'acme'}));
      expect(
        state.params[workflowParentRunIdParamKey],
        equals('wf-parent'),
      );
    },
  );

  test('flow context workflows starts typed child workflows', () async {
    final childRef = WorkflowRef<Map<String, Object?>, String>(
      name: 'child.runtime.flow',
      encodeParams: (params) => params,
    );

    runtime
      ..registerWorkflow(
        Flow(
          name: 'child.runtime.flow',
          build: (flow) {
            flow.step('hello', (context) async {
              final value = context.params['value'] as String? ?? 'child';
              return 'ok:$value';
            });
          },
        ).definition,
      )
      ..registerWorkflow(
        Flow(
          name: 'parent.runtime.flow',
          build: (flow) {
            flow.step('spawn', (context) async {
              return childRef.start(
                context,
                params: const {'value': 'spawned'},
              );
            });
          },
        ).definition,
      );

    final parentRunId = await runtime.startWorkflow('parent.runtime.flow');
    await runtime.executeRun(parentRunId);

    final parentState = await store.get(parentRunId);
    final childRunId = parentState!.result! as String;
    final childState = await store.get(childRunId);

    expect(childState, isNotNull);
    expect(childState!.workflow, 'child.runtime.flow');
    expect(childState.parentRunId, parentRunId);
    expect(childState.workflowParams, equals(const {'value': 'spawned'}));
  });

  test('script checkpoint workflows starts typed child workflows', () async {
    final childRef = WorkflowRef<Map<String, Object?>, String>(
      name: 'child.runtime.script',
      encodeParams: (params) => params,
    );

    runtime
      ..registerWorkflow(
        Flow(
          name: 'child.runtime.script',
          build: (flow) {
            flow.step('hello', (context) async {
              final value = context.params['value'] as String? ?? 'child';
              return 'ok:$value';
            });
          },
        ).definition,
      )
      ..registerWorkflow(
        WorkflowScript<String>(
          name: 'parent.runtime.script',
          checkpoints: [
            WorkflowCheckpoint(name: 'spawn'),
          ],
          run: (script) async {
            return script.step<String>('spawn', (context) async {
              return childRef.start(
                context,
                params: const {'value': 'script-child'},
              );
            });
          },
        ).definition,
      );

    final parentRunId = await runtime.startWorkflow('parent.runtime.script');
    await runtime.executeRun(parentRunId);

    final parentState = await store.get(parentRunId);
    final childRunId = parentState!.result! as String;
    final childState = await store.get(childRunId);

    expect(childState, isNotNull);
    expect(childState!.workflow, 'child.runtime.script');
    expect(childState.parentRunId, parentRunId);
    expect(childState.workflowParams, equals(const {'value': 'script-child'}));
  });

  test(
    'flow contexts can startAndWait for child workflows directly',
    () async {
      final childRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'child.runtime.wait.flow',
        encodeParams: (params) => params,
      );

      runtime
        ..registerWorkflow(
          Flow(
            name: 'child.runtime.wait.flow',
            build: (flow) {
              flow.step('hello', (context) async {
                final value = context.params['value'] as String? ?? 'child';
                return 'ok:$value';
              });
            },
          ).definition,
        )
        ..registerWorkflow(
          Flow(
            name: 'parent.runtime.wait.flow',
            build: (flow) {
              flow.step('spawn', (context) async {
                final childResult = await childRef.startAndWait(
                  context,
                  params: const {'value': 'spawned'},
                  timeout: const Duration(seconds: 2),
                );
                return {
                  'childRunId': childResult?.runId,
                  'childValue': childResult?.value,
                };
              });
            },
          ).definition,
        );

      final parentRunId = await runtime.startWorkflow(
        'parent.runtime.wait.flow',
      );
      await runtime.executeRun(parentRunId);

      final parentState = await store.get(parentRunId);
      final result = Map<String, Object?>.from(parentState!.result! as Map);
      expect(result['childRunId'], isA<String>());
      expect(result['childValue'], 'ok:spawned');
    },
  );

  test(
    'script checkpoints can startAndWait for child workflows directly',
    () async {
      final childRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'child.runtime.wait.script',
        encodeParams: (params) => params,
      );

      runtime
        ..registerWorkflow(
          Flow(
            name: 'child.runtime.wait.script',
            build: (flow) {
              flow.step('hello', (context) async {
                final value = context.params['value'] as String? ?? 'child';
                return 'ok:$value';
              });
            },
          ).definition,
        )
        ..registerWorkflow(
          WorkflowScript<Map<String, Object?>>(
            name: 'parent.runtime.wait.script',
            checkpoints: [WorkflowCheckpoint(name: 'spawn')],
            run: (script) async {
              return script.step<Map<String, Object?>>('spawn', (
                context,
              ) async {
                final childResult = await childRef.startAndWait(
                  context,
                  params: const {'value': 'script-child'},
                  timeout: const Duration(seconds: 2),
                );
                return {
                  'childRunId': childResult?.runId,
                  'childValue': childResult?.value,
                };
              });
            },
          ).definition,
        );

      final parentRunId = await runtime.startWorkflow(
        'parent.runtime.wait.script',
      );
      await runtime.executeRun(parentRunId);

      final parentState = await store.get(parentRunId);
      final result = Map<String, Object?>.from(parentState!.result! as Map);
      expect(result['childRunId'], isA<String>());
      expect(result['childValue'], 'ok:script-child');
    },
  );

  test('viewRunDetail exposes uniform run and checkpoint views', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'views.workflow',
        build: (flow) {
          flow.step('only', (context) async => 'done');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('views.workflow');
    await runtime.executeRun(runId);

    final detail = await runtime.viewRunDetail(runId);
    expect(detail, isNotNull);
    expect(detail!.run.runId, equals(runId));
    expect(detail.run.workflow, equals('views.workflow'));
    expect(detail.checkpoints, hasLength(1));
    expect(detail.checkpoints.first.baseCheckpointName, equals('only'));
    expect(detail.checkpoints.first.checkpointName, equals('only'));
  });

  test('workflowManifest exposes typed manifest entries', () {
    runtime.registerWorkflow(
      Flow(
        name: 'manifest.runtime.workflow',
        build: (flow) {
          flow.step('only', (context) async => 'done');
        },
      ).definition,
    );

    final manifest = runtime.workflowManifest();
    final entry = manifest.firstWhere(
      (item) => item.name == 'manifest.runtime.workflow',
    );
    expect(entry.id, isNotEmpty);
    expect(entry.steps, hasLength(1));
    expect(entry.steps.first.name, equals('only'));
  });

  test('extends lease when checkpoints persist', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'lease.workflow',
        build: (flow) {
          flow.step('only', (context) async => 'done');
        },
      ).definition,
    );

    final extendCalls = <Duration>[];
    final context = TaskContext(
      id: 'lease-task',
      attempt: 1,
      headers: <String, String>{},
      meta: <String, Object?>{},
      heartbeat: () {},
      extendLease: (duration) async => extendCalls.add(duration),
      progress: (_, {data}) async {},
    );

    final runId = await runtime.startWorkflow('lease.workflow');
    await runtime.executeRun(runId, taskContext: context);

    expect(extendCalls, isNotEmpty);
    expect(
      extendCalls.every((duration) => duration == runtime.leaseExtension),
      isTrue,
    );
  });

  test('retries when run lease is held by another runtime', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'lease.conflict.workflow',
        build: (flow) {
          flow.step('only', (context) async => 'done');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('lease.conflict.workflow');
    final claimed = await store.claimRun(
      runId,
      ownerId: 'other-runtime',
    );
    expect(claimed, isTrue);

    TaskRetryRequest? retry;
    try {
      await runtime.executeRun(runId);
    } on TaskRetryRequest catch (error) {
      retry = error;
    }

    expect(retry, isNotNull);
    expect(retry!.countdown, runtime.runLeaseDuration);
    expect(retry.maxRetries, greaterThan(0));

    final state = await store.get(runId);
    expect(state?.ownerId, 'other-runtime');
    expect(state?.status, WorkflowStatus.running);
  });

  test('suspends on sleep and resumes after delay', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'sleep.workflow',
        build: (flow) {
          flow
            ..step('wait', (context) async {
              final resume = context.takeResumeData();
              if (resume == true) {
                return 'slept';
              }
              context.sleep(const Duration(milliseconds: 20));
              return null;
            })
            ..step(
              'complete',
              (context) async => '${context.previousResult}-done',
            );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('sleep.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.resumeAt, isNotNull);

    // Simulate beat loop discovering the due run.
    clock.advance(const Duration(milliseconds: 30));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'slept-done');
  });

  test('sleep auto resumes without manual guard', () async {
    var iterations = 0;

    runtime.registerWorkflow(
      Flow(
        name: 'sleep.autoresume.workflow',
        build: (flow) {
          flow.step('loop', (context) async {
            iterations += 1;
            if (iterations == 1) {
              context.sleep(const Duration(milliseconds: 20));
              return 'waiting';
            }
            return 'resumed';
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('sleep.autoresume.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);

    clock.advance(const Duration(milliseconds: 40));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(iterations, 2);
    expect(completed?.result, 'resumed');
  });

  test('sleepFor suspends and resumes without manual guards', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'sleep.expression.workflow',
        build: (flow) {
          flow
            ..step('wait', (context) async {
              await context.sleepFor(
                duration: const Duration(milliseconds: 20),
              );
              return 'slept';
            })
            ..step(
              'complete',
              (context) async => '${context.previousResult}-done',
            );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('sleep.expression.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.resumeAt, isNotNull);

    clock.advance(const Duration(milliseconds: 30));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'slept-done');
  });

  test('awaitEvent suspends and resumes with payload', () async {
    String? observedPayload;

    runtime.registerWorkflow(
      Flow(
        name: 'event.workflow',
        build: (flow) {
          flow.step('wait', (context) async {
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('user.updated');
              return null;
            }
            final payload = resume as Map<String, Object?>;
            observedPayload = payload['id'] as String?;
            return payload['id'];
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, 'user.updated');

    await runtime.emit('user.updated', const {'id': 'user-123'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(observedPayload, 'user-123');
  });

  test('waitForEvent suspends and resumes with payload', () async {
    String? observedPayload;

    runtime.registerWorkflow(
      Flow(
        name: 'event.expression.workflow',
        build: (flow) {
          flow.step('wait', (context) async {
            final payload = await context.waitForEvent<Map<String, Object?>>(
              topic: 'user.updated.expression',
            );
            observedPayload = payload['id'] as String?;
            return payload['id'];
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.expression.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, 'user.updated.expression');

    await runtime.emit('user.updated.expression', const {'id': 'user-789'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(observedPayload, 'user-789');
    expect(completed?.result, 'user-789');
  });

  test('emitValue resumes flows with codec-backed DTO payloads', () async {
    _UserUpdatedEvent? observedPayload;

    runtime.registerWorkflow(
      Flow(
        name: 'event.typed.workflow',
        build: (flow) {
          flow.step<String?>(
            'wait',
            (context) async {
              final resume = context.takeResumeValue<_UserUpdatedEvent>(
                codec: _userUpdatedEventCodec,
              );
              if (resume == null) {
                context.awaitEvent('user.updated.typed');
                return null;
              }
              observedPayload = resume;
              return resume.id;
            },
          );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.typed.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, 'user.updated.typed');

    await runtime.emitValue(
      'user.updated.typed',
      const _UserUpdatedEvent(id: 'user-typed-1'),
      codec: _userUpdatedEventCodec,
    );
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(observedPayload?.id, 'user-typed-1');
    expect(completed?.result, 'user-typed-1');
  });

  test(
    'emitJson resumes flows with DTO payloads without a manual map',
    () async {
      _UserUpdatedEvent? observedPayload;

      runtime.registerWorkflow(
        Flow(
          name: 'event.json.workflow',
          build: (flow) {
            flow.step<String?>(
              'wait',
              (context) async {
                final resume = context.takeResumeValue<_UserUpdatedEvent>(
                  codec: _userUpdatedEventCodec,
                );
                if (resume == null) {
                  context.awaitEvent('user.updated.json');
                  return null;
                }
                observedPayload = resume;
                return resume.id;
              },
            );
          },
        ).definition,
      );

      final runId = await runtime.startWorkflow('event.json.workflow');
      await runtime.executeRun(runId);

      final suspended = await store.get(runId);
      expect(suspended?.status, WorkflowStatus.suspended);
      expect(suspended?.waitTopic, 'user.updated.json');

      await runtime.emitJson(
        'user.updated.json',
        const _UserUpdatedEvent(id: 'user-json-1'),
      );
      await runtime.executeRun(runId);

      final completed = await store.get(runId);
      expect(completed?.status, WorkflowStatus.completed);
      expect(observedPayload?.id, 'user-json-1');
      expect(completed?.result, 'user-json-1');
    },
  );

  test(
    'emitVersionedJson resumes flows with versioned DTO payloads',
    () async {
      _UserUpdatedEvent? observedPayload;

      runtime.registerWorkflow(
        Flow(
          name: 'event.versioned.json.workflow',
          build: (flow) {
            flow.step<String?>(
              'wait',
              (context) async {
                final resume = context.takeResumeValue<_UserUpdatedEvent>(
                  codec: _userUpdatedEventCodec,
                );
                if (resume == null) {
                  context.awaitEvent('user.updated.versioned.json');
                  return null;
                }
                observedPayload = resume;
                return resume.id;
              },
            );
          },
        ).definition,
      );

      final runId = await runtime.startWorkflow(
        'event.versioned.json.workflow',
      );
      await runtime.executeRun(runId);

      final suspended = await store.get(runId);
      expect(suspended?.status, WorkflowStatus.suspended);
      expect(suspended?.waitTopic, 'user.updated.versioned.json');

      await runtime.emitVersionedJson(
        'user.updated.versioned.json',
        const _UserUpdatedEvent(id: 'user-json-2'),
        version: 2,
      );
      await runtime.executeRun(runId);

      final completed = await store.get(runId);
      expect(completed?.status, WorkflowStatus.completed);
      expect(observedPayload?.id, 'user-json-2');
      expect(completed?.result, 'user-json-2');
    },
  );

  test('emitEvent resumes flows with typed workflow event refs', () async {
    final event = WorkflowEventRef<_UserUpdatedEvent>.codec(
      topic: 'user.updated.ref',
      codec: _userUpdatedEventCodec,
    );
    _UserUpdatedEvent? observedPayload;

    runtime.registerWorkflow(
      Flow(
        name: 'event.ref.workflow',
        build: (flow) {
          flow.step<String?>(
            'wait',
            (context) async {
              final resume = event.waitValue(context);
              if (resume == null) {
                return null;
              }
              observedPayload = resume;
              return resume.id;
            },
          );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.ref.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, event.topic);

    await event.emit(
      runtime,
      const _UserUpdatedEvent(id: 'user-typed-2'),
    );
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(observedPayload?.id, 'user-typed-2');
    expect(completed?.result, 'user-typed-2');
  });

  test('emitEvent resumes flows with versioned-json workflow event refs', () async {
    final event = WorkflowEventRef<_UserUpdatedEvent>.versionedJson(
      topic: 'user.updated.versioned.ref',
      version: 2,
      decode: _UserUpdatedEvent.fromVersionedJson,
      typeName: '_UserUpdatedEvent',
    );
    _UserUpdatedEvent? observedPayload;

    runtime.registerWorkflow(
      Flow(
        name: 'event.versioned.ref.workflow',
        build: (flow) {
          flow.step<String?>(
            'wait',
            (context) async {
              final resume = event.waitValue(context);
              if (resume == null) {
                return null;
              }
              observedPayload = resume;
              return resume.id;
            },
          );
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.versioned.ref.workflow');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, event.topic);

    await event.emit(
      runtime,
      const _UserUpdatedEvent(id: 'user-versioned-ref-2'),
    );
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(observedPayload?.id, 'user-versioned-ref-2');
    expect(completed?.result, 'user-versioned-ref-2');
  });

  test('emit persists payload before worker resumes execution', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'event.persisted',
        build: (flow) {
          flow.step('wait', (context) async {
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('persist.event');
              return null;
            }
            final payload = resume as Map<String, Object?>;
            return payload['value'];
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('event.persisted');
    await runtime.executeRun(runId);

    await runtime.emit('persist.event', const <String, Object?>{
      'value': 'ready',
    });

    final afterEmit = await store.get(runId);
    expect(afterEmit?.status, WorkflowStatus.running);
    expect(afterEmit?.suspensionData?['payload'], {'value': 'ready'});

    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'ready');
  });

  test('saveStep refreshes run heartbeat', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'heartbeat.workflow',
        build: (flow) {
          flow.step('first', (context) async => 'done');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('heartbeat.workflow');
    final initial = await store.get(runId);
    expect(initial?.updatedAt, isNotNull);

    clock.advance(const Duration(milliseconds: 2));
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.updatedAt, isNotNull);
    expect(completed!.updatedAt!.isAfter(initial!.updatedAt!), isTrue);
  });

  test('sleep then event workflow reaches terminal state', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'durable.sleep.event',
        build: (flow) {
          flow
            ..step('initial', (context) async {
              final resume = context.takeResumeData();
              if (resume != true) {
                context.sleep(const Duration(milliseconds: 20));
                return null;
              }
              return 'awake';
            })
            ..step('await-event', (context) async {
              final resume = context.takeResumeData();
              if (resume == null) {
                context.awaitEvent('demo.event');
                return null;
              }
              final payload = resume as Map<String, Object?>;
              return payload['message'];
            });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('durable.sleep.event');
    await runtime.executeRun(runId);

    final afterSleep = await store.get(runId);
    expect(afterSleep?.status, WorkflowStatus.suspended);
    expect(afterSleep?.cursor, 0);
    expect(afterSleep?.resumeAt, isNotNull);

    clock.advance(const Duration(milliseconds: 25));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final awaitingEvent = await store.get(runId);
    expect(awaitingEvent?.status, WorkflowStatus.suspended);
    expect(awaitingEvent?.cursor, 1);
    expect(awaitingEvent?.waitTopic, 'demo.event');

    await runtime.emit('demo.event', const {'message': 'event received'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'event received');
  });

  test('idempotency helper returns stable key across retries', () async {
    var attempts = 0;
    final observedKeys = <String>[];

    runtime.registerWorkflow(
      Flow(
        name: 'idempotency.workflow',
        build: (flow) {
          flow.step('idempotent-call', (context) async {
            final key = context.idempotencyKey('charge');
            observedKeys.add(key);
            if (attempts++ == 0) {
              throw StateError('transient');
            }
            return key;
          });
        },
      ).definition,
    );

    final extendCalls = <Duration>[];
    final context = TaskContext(
      id: 'idempotent-task',
      attempt: 1,
      headers: <String, String>{},
      meta: <String, Object?>{},
      heartbeat: () {},
      extendLease: (duration) async => extendCalls.add(duration),
      progress: (_, {data}) async {},
    );

    final runId = await runtime.startWorkflow('idempotency.workflow');
    await expectLater(
      () => runtime.executeRun(runId, taskContext: context),
      throwsA(isA<StateError>()),
    );

    await runtime.executeRun(runId, taskContext: context);

    expect(observedKeys.length, 2);
    expect(observedKeys.first, observedKeys.last);
    expect(extendCalls, isNotEmpty);
  });

  test('autoVersion stores sequential checkpoints when rewound', () async {
    final iterations = <int>[];

    runtime.registerWorkflow(
      Flow(
        name: 'repeat.workflow',
        build: (flow) {
          flow
            ..step('repeat', (context) async {
              iterations.add(context.iteration);
              return 'value-${context.iteration}';
            }, autoVersion: true)
            ..step('tail', (context) async => context.previousResult);
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('repeat.workflow');
    await runtime.executeRun(runId);

    var steps = await store.listSteps(runId);
    expect(iterations, [0]);
    expect(steps.map((s) => s.name), containsAll(['repeat#0', 'tail']));

    await store.rewindToStep(runId, 'repeat');
    final rewoundState = await store.get(runId);
    expect(rewoundState?.status, WorkflowStatus.suspended);
    await store.markRunning(runId);
    await runtime.executeRun(runId);

    steps = await store.listSteps(runId);
    expect(iterations, [0, 0]);
    expect(steps.map((s) => s.name), containsAll(['repeat#0', 'tail']));
  });

  test('autoVersion preserves iteration across suspension', () async {
    final iterations = <int>[];

    runtime.registerWorkflow(
      Flow(
        name: 'await.workflow',
        build: (flow) {
          flow.step('await-step', (context) async {
            iterations.add(context.iteration);
            final resume = context.takeResumeData();
            if (resume == null) {
              context.awaitEvent('loop.event');
              return null;
            }
            return (resume as Map<String, Object?>)['value'];
          }, autoVersion: true);
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('await.workflow');
    await runtime.executeRun(runId);

    // Step should be suspended waiting on event.
    var state = await store.get(runId);
    expect(state?.status, WorkflowStatus.suspended);

    await runtime.emit('loop.event', const {'value': 'done'});
    await runtime.executeRun(runId);

    state = await store.get(runId);
    expect(state?.status, WorkflowStatus.completed);
    expect(iterations, [0, 0]);
    final steps = await store.listSteps(runId);
    expect(steps.map((s) => s.name), contains('await-step#0'));
  });

  test('script facade executes sequential steps', () async {
    String? previousSeen;

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.basic',
        run: (script) async {
          final first = await script.step('first', (step) async => 'ready');
          final second = await script.step('second', (step) async {
            previousSeen = step.previousResult as String?;
            return '$first-done';
          });
          return second;
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.basic');
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.completed);
    expect(state?.result, 'ready-done');
    expect(previousSeen, 'ready');
    expect(await store.readStep<String>(runId, 'first'), 'ready');
    expect(await store.readStep<String>(runId, 'second'), 'ready-done');
  });

  test('script step sleep suspends and resumes', () async {
    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.sleep',
        run: (script) async {
          await script.step('wait', (step) async {
            final resume = step.takeResumeData();
            if (resume != true) {
              await step.sleep(const Duration(milliseconds: 20));
              return 'waiting';
            }
            return 'slept';
          });
          return 'done';
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.sleep');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.resumeAt, isNotNull);

    clock.advance(const Duration(milliseconds: 30));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(completed?.result, 'done');
    expect(await store.readStep<String>(runId, 'wait'), 'slept');
  });

  test('script sleep auto resumes without manual guard', () async {
    var iterations = 0;

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.sleep.autoresume',
        run: (script) async {
          return script.step('loop', (step) async {
            iterations += 1;
            if (iterations == 1) {
              await step.sleep(const Duration(milliseconds: 20));
              return 'waiting';
            }
            return 'resumed';
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.sleep.autoresume');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);

    clock.advance(const Duration(milliseconds: 40));
    final due = await store.dueRuns(clock.now());
    for (final id in due) {
      final state = await store.get(id);
      await store.markResumed(id, data: state?.suspensionData);
      await runtime.executeRun(id);
    }

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(iterations, 2);
    expect(completed?.result, 'resumed');
  });

  test('script awaitEvent resumes with payload', () async {
    Map<String, Object?>? resumePayload;

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.event',
        run: (script) async {
          final result = await script.step('wait', (step) async {
            final resume = step.takeResumeData();
            if (resume == null) {
              await step.awaitEvent('user.updated');
              return 'waiting';
            }
            resumePayload = resume as Map<String, Object?>?;
            return resumePayload?['id'];
          });
          return result;
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.event');
    await runtime.executeRun(runId);

    final suspended = await store.get(runId);
    expect(suspended?.status, WorkflowStatus.suspended);
    expect(suspended?.waitTopic, 'user.updated');

    await runtime.emit('user.updated', const {'id': 'user-42'});
    await runtime.executeRun(runId);

    final completed = await store.get(runId);
    expect(completed?.status, WorkflowStatus.completed);
    expect(resumePayload?['id'], 'user-42');
    expect(completed?.result, 'user-42');
  });

  test(
    'script waitForEvent uses named args and resumes with payload',
    () async {
      Map<String, Object?>? resumePayload;

      runtime.registerWorkflow(
        WorkflowScript(
          name: 'script.event.expression',
          run: (script) async {
            final result = await script.step('wait', (step) async {
              final payload = await step.waitForEvent<Map<String, Object?>>(
                topic: 'user.updated.expression.script',
              );
              resumePayload = payload;
              return payload['id'];
            });
            return result;
          },
        ).definition,
      );

      final runId = await runtime.startWorkflow('script.event.expression');
      await runtime.executeRun(runId);

      final suspended = await store.get(runId);
      expect(suspended?.status, WorkflowStatus.suspended);
      expect(suspended?.waitTopic, 'user.updated.expression.script');

      await runtime.emit(
        'user.updated.expression.script',
        const {'id': 'user-43'},
      );
      await runtime.executeRun(runId);

      final completed = await store.get(runId);
      expect(completed?.status, WorkflowStatus.completed);
      expect(resumePayload?['id'], 'user-43');
      expect(completed?.result, 'user-43');
    },
  );

  test('script autoVersion step persists sequential checkpoints', () async {
    final iterations = <int>[];

    runtime.registerWorkflow(
      WorkflowScript(
        name: 'script.autoversion',
        run: (script) async {
          for (var i = 0; i < 3; i++) {
            await script.step<int>('repeat', (step) async {
              iterations.add(step.iteration);
              return step.iteration;
            }, autoVersion: true);
          }
          return iterations.length;
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('script.autoversion');
    await runtime.executeRun(runId);

    expect(iterations, [0, 1, 2]);
    expect(await store.readStep<int>(runId, 'repeat#0'), 0);
    expect(await store.readStep<int>(runId, 'repeat#1'), 1);
    expect(await store.readStep<int>(runId, 'repeat#2'), 2);
    final state = await store.get(runId);
    expect(state?.result, 3);
  });

  test('emits step events to the introspection sink', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'introspection.workflow',
        build: (flow) {
          flow
            ..step('first', (context) async => 'one')
            ..step('second', (context) async => 'two');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('introspection.workflow');
    await runtime.executeRun(runId);

    final events = introspection.events
        .where((event) => event.workflow == 'introspection.workflow')
        .toList();

    expect(
      events.any((event) => event.type == WorkflowStepEventType.started),
      isTrue,
    );
    expect(
      events.any((event) => event.type == WorkflowStepEventType.completed),
      isTrue,
    );
  });

  test('records failures and propagates errors', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'failing.workflow',
        build: (flow) {
          flow.step('boom', (context) async {
            throw StateError('kaboom');
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('failing.workflow');
    await expectLater(
      () => runtime.executeRun(runId),
      throwsA(isA<StateError>()),
    );

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.running);
    expect(state?.lastError?['error'], contains('kaboom'));
  });

  test('cancelWorkflow transitions to cancelled state', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'cancel.workflow',
        build: (flow) {
          flow.step('noop', (context) async => 'noop');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow('cancel.workflow');
    await runtime.cancelWorkflow(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.cancelled);
  });

  test('maxRunDuration cancels runs that exceed the limit', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'duration.workflow',
        build: (flow) {
          flow.step('fast', (context) async => 'done');
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow(
      'duration.workflow',
      cancellationPolicy: const WorkflowCancellationPolicy(
        maxRunDuration: Duration(milliseconds: 5),
      ),
    );

    clock.advance(const Duration(milliseconds: 15));
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.cancelled);
    expect(state?.cancellationData?['reason'], 'maxRunDuration');
  });

  test('maxSuspendDuration cancels runs that stay suspended', () async {
    runtime.registerWorkflow(
      Flow(
        name: 'suspend.workflow',
        build: (flow) {
          flow.step('sleep', (context) async {
            final resume = context.takeResumeData();
            if (resume != true) {
              context.sleep(const Duration(milliseconds: 100));
              return null;
            }
            return 'done';
          });
        },
      ).definition,
    );

    final runId = await runtime.startWorkflow(
      'suspend.workflow',
      cancellationPolicy: const WorkflowCancellationPolicy(
        maxSuspendDuration: Duration(milliseconds: 20),
      ),
    );

    await runtime.executeRun(runId);
    clock.advance(const Duration(milliseconds: 80));
    await runtime.executeRun(runId);

    final state = await store.get(runId);
    expect(state?.status, WorkflowStatus.cancelled);
    expect(state?.cancellationData?['reason'], 'maxSuspendDuration');
  });

  test('enqueued tasks include workflow metadata', () async {
    const taskName = 'tasks.meta';
    registry.register(
      FunctionTaskHandler<void>.inline(
        name: taskName,
        entrypoint: (context, args) async => null,
      ),
    );

    runtime.registerWorkflow(
      Flow(
        name: 'meta.workflow',
        build: (flow) {
          flow.step('dispatch', (context) async {
            await context.enqueue(
              taskName,
              meta: const {'custom': 'value'},
            );
            return 'done';
          });
        },
      ).definition,
    );

    final runId = await store.createRun(
      workflow: 'meta.workflow',
      params: const {},
    );
    await runtime.executeRun(runId);

    final delivery = await broker
        .consume(RoutingSubscription.singleQueue('default'))
        .first
        .timeout(const Duration(seconds: 1));

    expect(delivery.envelope.name, taskName);
    final meta = delivery.envelope.meta;
    expect(meta['stem.workflow.runId'], runId);
    expect(meta['stem.workflow.name'], 'meta.workflow');
    expect(meta['stem.workflow.step'], 'dispatch');
    expect(meta['stem.workflow.stepIndex'], 0);
    expect(meta['stem.workflow.iteration'], 0);
    expect(meta['custom'], 'value');
  });

  test('stem enqueue in steps includes workflow metadata', () async {
    const taskName = 'tasks.meta.direct';
    registry.register(
      FunctionTaskHandler<void>.inline(
        name: taskName,
        entrypoint: (context, args) async => null,
      ),
    );

    runtime.registerWorkflow(
      Flow(
        name: 'meta.direct.workflow',
        build: (flow) {
          flow.step('dispatch', (context) async {
            await stem.enqueue(
              taskName,
              meta: const {'origin': 'direct'},
            );
            return 'done';
          });
        },
      ).definition,
    );

    final runId = await store.createRun(
      workflow: 'meta.direct.workflow',
      params: const {},
    );
    await runtime.executeRun(runId);

    final delivery = await broker
        .consume(RoutingSubscription.singleQueue('default'))
        .first
        .timeout(const Duration(seconds: 1));

    expect(delivery.envelope.name, taskName);
    final meta = delivery.envelope.meta;
    expect(meta['stem.workflow.runId'], runId);
    expect(meta['stem.workflow.name'], 'meta.direct.workflow');
    expect(meta['stem.workflow.step'], 'dispatch');
    expect(meta['stem.workflow.stepIndex'], 0);
    expect(meta['stem.workflow.iteration'], 0);
    expect(meta['origin'], 'direct');
  });

  test(
    'emits workflow lifecycle logs for enqueue, suspension, and completion',
    () async {
      final driver = _RecordingLogDriver();
      stemLogger
        ..addChannel(
          'workflow-runtime-log-test-${DateTime.now().microsecondsSinceEpoch}',
          driver,
        )
        ..setLevel(Level.debug);

      runtime.registerWorkflow(
        Flow(
          name: 'logging.suspend.workflow',
          build: (flow) {
            flow.step('wait', (context) async {
              context.sleep(const Duration(milliseconds: 20));
              return null;
            });
          },
        ).definition,
      );
      runtime.registerWorkflow(
        Flow(
          name: 'logging.complete.workflow',
          build: (flow) {
            flow.step('finish', (context) async => 'done');
          },
        ).definition,
      );

      final suspendedRunId = await runtime.startWorkflow(
        'logging.suspend.workflow',
      );
      await runtime.executeRun(suspendedRunId);

      final completedRunId = await runtime.startWorkflow(
        'logging.complete.workflow',
      );
      await runtime.executeRun(completedRunId);

      LogEntry findEntry(String runId, String message) =>
          driver.entries.firstWhere(
            (entry) =>
                entry.record.message == message &&
                entry.record.context.all()['workflowRunId'] == runId,
          );

      final enqueued = driver.entries.firstWhere(
        (entry) =>
            entry.record.message == 'Workflow {workflow} enqueued' &&
            entry.record.context.all()['workflowRunId'] == suspendedRunId &&
            entry.record.context.all()['workflowReason'] == 'start',
      );
      expect(
        enqueued.record.context.all()['workflow'],
        equals('logging.suspend.workflow'),
      );
      expect(enqueued.record.context.all()['workflowReason'], equals('start'));

      final suspended = findEntry(
        suspendedRunId,
        'Workflow {workflow} suspended',
      );
      expect(suspended.record.context.all()['workflowStep'], equals('wait'));
      expect(
        suspended.record.context.all()['workflowSuspensionType'],
        equals('sleep'),
      );

      final completed = findEntry(
        completedRunId,
        'Workflow {workflow} completed',
      );
      expect(
        completed.record.context.all()['workflow'],
        equals('logging.complete.workflow'),
      );
    },
  );

  test('enqueue builder in steps includes workflow metadata', () async {
    const taskName = 'tasks.meta.builder';
    registry.register(
      FunctionTaskHandler<void>.inline(
        name: taskName,
        entrypoint: (context, args) async => null,
      ),
    );

    final definition = TaskDefinition<Map<String, Object?>, void>(
      name: taskName,
      encodeArgs: (args) => args,
    );

    runtime.registerWorkflow(
      Flow(
        name: 'meta.builder.workflow',
        build: (flow) {
          flow.step('dispatch', (context) async {
            final call = definition.buildCall(
              const <String, Object?>{},
              meta: const {'origin': 'builder'},
            );
            await stem.enqueueCall(call);
            return 'done';
          });
        },
      ).definition,
    );

    final runId = await store.createRun(
      workflow: 'meta.builder.workflow',
      params: const {},
    );
    await runtime.executeRun(runId);

    final delivery = await broker
        .consume(RoutingSubscription.singleQueue('default'))
        .first
        .timeout(const Duration(seconds: 1));

    expect(delivery.envelope.name, taskName);
    final meta = delivery.envelope.meta;
    expect(meta['stem.workflow.runId'], runId);
    expect(meta['stem.workflow.name'], 'meta.builder.workflow');
    expect(meta['stem.workflow.step'], 'dispatch');
    expect(meta['stem.workflow.stepIndex'], 0);
    expect(meta['stem.workflow.iteration'], 0);
    expect(meta['origin'], 'builder');
  });
}

class _RecordingWorkflowIntrospectionSink implements WorkflowIntrospectionSink {
  final List<WorkflowStepEvent> events = [];
  final List<WorkflowRuntimeEvent> runtimeEvents = [];

  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async {
    events.add(event);
  }

  @override
  Future<void> recordRuntimeEvent(WorkflowRuntimeEvent event) async {
    runtimeEvents.add(event);
  }
}

class _RecordingLogDriver extends LogDriver {
  _RecordingLogDriver() : entries = <LogEntry>[], super('recording');

  final List<LogEntry> entries;

  @override
  Future<void> log(LogEntry entry) async {
    entries.add(entry);
  }
}

const _userUpdatedEventCodec = PayloadCodec<_UserUpdatedEvent>.json(
  decode: _UserUpdatedEvent.fromJson,
  typeName: '_UserUpdatedEvent',
);

class _UserUpdatedEvent {
  const _UserUpdatedEvent({required this.id});

  final String id;

  Map<String, Object?> toJson() => {'id': id};

  static _UserUpdatedEvent fromJson(Map<String, Object?> json) {
    return _UserUpdatedEvent(id: json['id'] as String);
  }

  static _UserUpdatedEvent fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _UserUpdatedEvent(id: json['id'] as String);
  }
}
