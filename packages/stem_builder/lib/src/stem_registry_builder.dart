// Registry codegen emits repeated buffer writes and long string literals.
// ignore_for_file: avoid_catches_without_on_clauses, cascade_invocations, lines_longer_than_80_chars

import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';
import 'package:stem/stem.dart';

/// Builder that emits a consolidated registry for annotated workflows/tasks.
class StemRegistryBuilder implements Builder {
  /// Creates the registry builder.
  StemRegistryBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'lib/$lib$': ['lib/stem_registry.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    const workflowDefnChecker = TypeChecker.typeNamed(
      WorkflowDefn,
      inPackage: 'stem',
    );
    const workflowRunChecker = TypeChecker.typeNamed(
      WorkflowRun,
      inPackage: 'stem',
    );
    const workflowStepChecker = TypeChecker.typeNamed(
      WorkflowStep,
      inPackage: 'stem',
    );
    const taskDefnChecker = TypeChecker.typeNamed(TaskDefn, inPackage: 'stem');

    const flowContextChecker = TypeChecker.typeNamed(
      FlowContext,
      inPackage: 'stem',
    );
    const scriptContextChecker = TypeChecker.typeNamed(
      WorkflowScriptContext,
      inPackage: 'stem',
    );
    const taskContextChecker = TypeChecker.typeNamed(
      TaskInvocationContext,
      inPackage: 'stem',
    );
    const mapChecker = TypeChecker.typeNamed(Map, inSdk: true);

    final workflows = <_WorkflowInfo>[];
    final tasks = <_TaskInfo>[];
    final imports = <String>{};

    await for (final input in buildStep.findAssets(Glob('lib/**.dart'))) {
      if (input.path.endsWith('.g.dart') || input.path.contains('.g.')) {
        continue;
      }
      if (!await buildStep.resolver.isLibrary(input)) {
        continue;
      }
      final library = await buildStep.resolver.libraryFor(input);
      final hasWorkflow = library.classes.any(
        (element) => workflowDefnChecker.hasAnnotationOfExact(element),
      );
      final hasTask = library.topLevelFunctions.any(
        (element) => taskDefnChecker.hasAnnotationOfExact(element),
      );
      if (!hasWorkflow && !hasTask) {
        continue;
      }

      imports.add(_importForAsset(input));

      for (final classElement in library.classes) {
        final annotation = workflowDefnChecker.firstAnnotationOfExact(
          classElement,
          throwOnUnresolved: false,
        );
        if (annotation == null) {
          continue;
        }
        if (classElement.isPrivate) {
          throw InvalidGenerationSourceError(
            'Workflow class ${classElement.displayName} must be public.',
            element: classElement,
          );
        }
        if (classElement.isAbstract) {
          throw InvalidGenerationSourceError(
            'Workflow class ${classElement.displayName} must not be abstract.',
            element: classElement,
          );
        }
        final constructor = classElement.unnamedConstructor;
        if (constructor == null || constructor.isPrivate) {
          throw InvalidGenerationSourceError(
            'Workflow class ${classElement.displayName} needs a public default constructor.',
            element: classElement,
          );
        }
        if (constructor.formalParameters.any(
          (p) => p.isRequiredNamed || p.isRequiredPositional,
        )) {
          throw InvalidGenerationSourceError(
            'Workflow class ${classElement.displayName} default constructor must have no required parameters.',
            element: classElement,
          );
        }

        final readerAnnotation = ConstantReader(annotation);
        final workflowName =
            _stringOrNull(readerAnnotation.peek('name')) ??
            classElement.displayName;
        final version = _stringOrNull(readerAnnotation.peek('version'));
        final description = _stringOrNull(readerAnnotation.peek('description'));
        final metadata = _objectOrNull(readerAnnotation.peek('metadata'));
        final kind = _readWorkflowKind(readerAnnotation);

        final runMethods = classElement.methods
            .where(
              (method) =>
                  workflowRunChecker.hasAnnotationOfExact(method) &&
                  !method.isStatic,
            )
            .toList(growable: false);
        final stepMethods =
            classElement.methods
                .where(
                  (method) =>
                      workflowStepChecker.hasAnnotationOfExact(method) &&
                      !method.isStatic,
                )
                .toList(growable: false)
              ..sort((a, b) {
                final aOffset =
                    a.firstFragment.nameOffset ?? a.firstFragment.offset;
                final bOffset =
                    b.firstFragment.nameOffset ?? b.firstFragment.offset;
                return aOffset.compareTo(bOffset);
              });

        if (kind == WorkflowKind.script || runMethods.isNotEmpty) {
          if (runMethods.isEmpty) {
            throw InvalidGenerationSourceError(
              'Workflow ${classElement.displayName} is marked as script but has no @workflow.run method.',
              element: classElement,
            );
          }
          if (runMethods.length > 1) {
            throw InvalidGenerationSourceError(
              'Workflow ${classElement.displayName} has multiple @workflow.run methods.',
              element: classElement,
            );
          }
          final runMethod = runMethods.single;
          _validateRunMethod(runMethod, scriptContextChecker);
          workflows.add(
            _WorkflowInfo.script(
              name: workflowName,
              className: classElement.displayName,
              runMethod: runMethod.displayName,
              version: version,
              description: description,
              metadata: metadata,
            ),
          );
          continue;
        }

        if (stepMethods.isEmpty) {
          throw InvalidGenerationSourceError(
            'Workflow ${classElement.displayName} has no @workflow.step methods.',
            element: classElement,
          );
        }
        final steps = <_WorkflowStepInfo>[];
        for (final method in stepMethods) {
          _validateFlowStepMethod(method, flowContextChecker);
          final stepAnnotation = workflowStepChecker.firstAnnotationOfExact(
            method,
            throwOnUnresolved: false,
          );
          if (stepAnnotation == null) {
            continue;
          }
          final stepReader = ConstantReader(stepAnnotation);
          final stepName =
              _stringOrNull(stepReader.peek('name')) ?? method.displayName;
          final autoVersion = _boolOrDefault(
            stepReader.peek('autoVersion'),
            false,
          );
          final title = _stringOrNull(stepReader.peek('title'));
          final kindValue = _objectOrNull(stepReader.peek('kind'));
          final taskNames = _objectOrNull(stepReader.peek('taskNames'));
          final stepMetadata = _objectOrNull(stepReader.peek('metadata'));
          steps.add(
            _WorkflowStepInfo(
              name: stepName,
              method: method.displayName,
              autoVersion: autoVersion,
              title: title,
              kind: kindValue,
              taskNames: taskNames,
              metadata: stepMetadata,
            ),
          );
        }
        workflows.add(
          _WorkflowInfo.flow(
            name: workflowName,
            className: classElement.displayName,
            steps: steps,
            version: version,
            description: description,
            metadata: metadata,
          ),
        );
      }

      for (final function in library.topLevelFunctions) {
        final annotation = taskDefnChecker.firstAnnotationOfExact(
          function,
          throwOnUnresolved: false,
        );
        if (annotation == null) {
          continue;
        }
        if (function.isPrivate) {
          throw InvalidGenerationSourceError(
            'Task function ${function.displayName} must be public.',
            element: function,
          );
        }
        _validateTaskFunction(function, taskContextChecker, mapChecker);
        final readerAnnotation = ConstantReader(annotation);
        final taskName =
            _stringOrNull(readerAnnotation.peek('name')) ??
            function.displayName;
        final options = _objectOrNull(readerAnnotation.peek('options'));
        final metadata = _objectOrNull(readerAnnotation.peek('metadata'));
        final runInIsolate = _boolOrDefault(
          readerAnnotation.peek('runInIsolate'),
          true,
        );

        tasks.add(
          _TaskInfo(
            name: taskName,
            function: function.displayName,
            options: options,
            metadata: metadata,
            runInIsolate: runInIsolate,
          ),
        );
      }
    }

    final outputId = buildStep.allowedOutputs.single;
    final registryCode = _RegistryEmitter(
      workflows: workflows,
      tasks: tasks,
      imports: imports,
    ).emit();
    final formatted = _format(registryCode);
    await buildStep.writeAsString(outputId, formatted);
  }

  static String _importForAsset(AssetId asset) {
    if (asset.path.startsWith('lib/')) {
      return 'package:${asset.package}/${asset.path.substring(4)}';
    }
    return asset.uri.toString();
  }

  static WorkflowKind _readWorkflowKind(ConstantReader reader) {
    final kind = reader.peek('kind');
    if (kind == null || kind.isNull) return WorkflowKind.flow;
    final revived = kind.revive();
    final raw = revived.accessor.split('.').last;
    return WorkflowKind.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => WorkflowKind.flow,
    );
  }

  static void _validateRunMethod(
    MethodElement method,
    TypeChecker scriptContextChecker,
  ) {
    if (method.isPrivate) {
      throw InvalidGenerationSourceError(
        '@workflow.run method ${method.displayName} must be public.',
        element: method,
      );
    }
    if (method.formalParameters.length != 1) {
      throw InvalidGenerationSourceError(
        '@workflow.run method ${method.displayName} must accept a single WorkflowScriptContext argument.',
        element: method,
      );
    }
    final param = method.formalParameters.first;
    if (!scriptContextChecker.isAssignableFromType(param.type)) {
      throw InvalidGenerationSourceError(
        '@workflow.run method ${method.displayName} must accept WorkflowScriptContext.',
        element: method,
      );
    }
  }

  static void _validateFlowStepMethod(
    MethodElement method,
    TypeChecker flowContextChecker,
  ) {
    if (method.isPrivate) {
      throw InvalidGenerationSourceError(
        '@workflow.step method ${method.displayName} must be public.',
        element: method,
      );
    }
    if (method.formalParameters.length != 1) {
      throw InvalidGenerationSourceError(
        '@workflow.step method ${method.displayName} must accept a single FlowContext argument.',
        element: method,
      );
    }
    final param = method.formalParameters.first;
    if (!flowContextChecker.isAssignableFromType(param.type)) {
      throw InvalidGenerationSourceError(
        '@workflow.step method ${method.displayName} must accept FlowContext.',
        element: method,
      );
    }
  }

  static void _validateTaskFunction(
    TopLevelFunctionElement function,
    TypeChecker taskContextChecker,
    TypeChecker mapChecker,
  ) {
    if (function.formalParameters.length != 2) {
      throw InvalidGenerationSourceError(
        '@TaskDefn function ${function.displayName} must accept (TaskInvocationContext, Map<String, Object?>).',
        element: function,
      );
    }
    final context = function.formalParameters[0];
    final args = function.formalParameters[1];
    if (!taskContextChecker.isAssignableFromType(context.type)) {
      throw InvalidGenerationSourceError(
        '@TaskDefn function ${function.displayName} must accept TaskInvocationContext as first parameter.',
        element: function,
      );
    }
    if (!mapChecker.isAssignableFromType(args.type)) {
      throw InvalidGenerationSourceError(
        '@TaskDefn function ${function.displayName} must accept Map<String, Object?> as second parameter.',
        element: function,
      );
    }
  }

  static String? _stringOrNull(ConstantReader? reader) {
    if (reader == null || reader.isNull) return null;
    return reader.stringValue;
  }

  static bool _boolOrDefault(ConstantReader? reader, bool fallback) {
    if (reader == null || reader.isNull) return fallback;
    return reader.boolValue;
  }

  static DartObject? _objectOrNull(ConstantReader? reader) {
    if (reader == null || reader.isNull) return null;
    return reader.objectValue;
  }

  static String _format(String code) {
    try {
      return DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format(code);
    } catch (_) {
      return code;
    }
  }
}

class _WorkflowInfo {
  _WorkflowInfo.flow({
    required this.name,
    required this.className,
    required this.steps,
    this.version,
    this.description,
    this.metadata,
  }) : kind = WorkflowKind.flow,
       runMethod = null;

  _WorkflowInfo.script({
    required this.name,
    required this.className,
    required this.runMethod,
    this.version,
    this.description,
    this.metadata,
  }) : kind = WorkflowKind.script,
       steps = const [];

  final String name;
  final WorkflowKind kind;
  final String className;
  final List<_WorkflowStepInfo> steps;
  final String? runMethod;
  final String? version;
  final String? description;
  final DartObject? metadata;
}

class _WorkflowStepInfo {
  const _WorkflowStepInfo({
    required this.name,
    required this.method,
    required this.autoVersion,
    required this.title,
    required this.kind,
    required this.taskNames,
    required this.metadata,
  });

  final String name;
  final String method;
  final bool autoVersion;
  final String? title;
  final DartObject? kind;
  final DartObject? taskNames;
  final DartObject? metadata;
}

class _TaskInfo {
  const _TaskInfo({
    required this.name,
    required this.function,
    required this.options,
    required this.metadata,
    required this.runInIsolate,
  });

  final String name;
  final String function;
  final DartObject? options;
  final DartObject? metadata;
  final bool runInIsolate;
}

class _RegistryEmitter {
  _RegistryEmitter({
    required this.workflows,
    required this.tasks,
    required this.imports,
  });

  final List<_WorkflowInfo> workflows;
  final List<_TaskInfo> tasks;
  final Set<String> imports;

  String emit() {
    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln(
      '// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types',
    );
    buffer.writeln();
    buffer.writeln("import 'package:stem/stem.dart';");
    for (final import in imports..remove('package:stem/stem.dart')) {
      buffer.writeln("import '$import';");
    }
    buffer.writeln();

    _emitWorkflows(buffer);
    _emitTasks(buffer);

    buffer.writeln('void registerStemDefinitions({');
    buffer.writeln('  required WorkflowRegistry workflows,');
    buffer.writeln('  required TaskRegistry tasks,');
    buffer.writeln('}) {');
    buffer.writeln('  for (final flow in stemFlows) {');
    buffer.writeln('    workflows.register(flow.definition);');
    buffer.writeln('  }');
    buffer.writeln('  for (final script in stemScripts) {');
    buffer.writeln('    workflows.register(script.definition);');
    buffer.writeln('  }');
    buffer.writeln('  for (final handler in stemTasks) {');
    buffer.writeln('    tasks.register(handler);');
    buffer.writeln('  }');
    buffer.writeln('}');
    return buffer.toString();
  }

  void _emitWorkflows(StringBuffer buffer) {
    buffer.writeln('final List<Flow> stemFlows = <Flow>[');
    for (final workflow in workflows.where(
      (w) => w.kind == WorkflowKind.flow,
    )) {
      buffer.writeln('  Flow(');
      buffer.writeln('    name: ${_string(workflow.name)},');
      if (workflow.version != null) {
        buffer.writeln('    version: ${_string(workflow.version!)},');
      }
      if (workflow.description != null) {
        buffer.writeln('    description: ${_string(workflow.description!)},');
      }
      if (workflow.metadata != null) {
        buffer.writeln(
          '    metadata: ${_dartObjectToCode(workflow.metadata!)},',
        );
      }
      buffer.writeln('    build: (flow) {');
      buffer.writeln('      final impl = ${workflow.className}();');
      for (final step in workflow.steps) {
        buffer.writeln('      flow.step(');
        buffer.writeln('        ${_string(step.name)},');
        buffer.writeln('        (ctx) => impl.${step.method}(ctx),');
        if (step.autoVersion) {
          buffer.writeln('        autoVersion: true,');
        }
        if (step.title != null) {
          buffer.writeln('        title: ${_string(step.title!)},');
        }
        if (step.kind != null) {
          buffer.writeln('        kind: ${_dartObjectToCode(step.kind!)},');
        }
        if (step.taskNames != null) {
          buffer.writeln(
            '        taskNames: ${_dartObjectToCode(step.taskNames!)},',
          );
        }
        if (step.metadata != null) {
          buffer.writeln(
            '        metadata: ${_dartObjectToCode(step.metadata!)},',
          );
        }
        buffer.writeln('      );');
      }
      buffer.writeln('    },');
      buffer.writeln('  ),');
    }
    buffer.writeln('];');
    buffer.writeln();

    buffer.writeln(
      'final List<WorkflowScript> stemScripts = <WorkflowScript>[',
    );
    for (final workflow in workflows.where(
      (w) => w.kind == WorkflowKind.script,
    )) {
      buffer.writeln('  WorkflowScript(');
      buffer.writeln('    name: ${_string(workflow.name)},');
      if (workflow.version != null) {
        buffer.writeln('    version: ${_string(workflow.version!)},');
      }
      if (workflow.description != null) {
        buffer.writeln('    description: ${_string(workflow.description!)},');
      }
      if (workflow.metadata != null) {
        buffer.writeln(
          '    metadata: ${_dartObjectToCode(workflow.metadata!)},',
        );
      }
      buffer.writeln(
        '    run: (script) => ${workflow.className}().${workflow.runMethod}(script),',
      );
      buffer.writeln('  ),');
    }
    buffer.writeln('];');
    buffer.writeln();
  }

  void _emitTasks(StringBuffer buffer) {
    buffer.writeln(
      'final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[',
    );
    for (final task in tasks) {
      buffer.writeln('  FunctionTaskHandler<Object?>(');
      buffer.writeln('    name: ${_string(task.name)},');
      buffer.writeln('    entrypoint: ${task.function},');
      if (task.options != null) {
        buffer.writeln('    options: ${_dartObjectToCode(task.options!)},');
      }
      if (task.metadata != null) {
        buffer.writeln('    metadata: ${_dartObjectToCode(task.metadata!)},');
      }
      if (!task.runInIsolate) {
        buffer.writeln('    runInIsolate: false,');
      }
      buffer.writeln('  ),');
    }
    buffer.writeln('];');
    buffer.writeln();
  }
}

String _dartObjectToCode(DartObject object) {
  final reader = ConstantReader(object);
  if (reader.isNull) return 'null';
  if (reader.isBool) return reader.boolValue.toString();
  if (reader.isInt) return reader.intValue.toString();
  if (reader.isDouble) return reader.doubleValue.toString();
  if (reader.isString) return jsonEncode(reader.stringValue);
  if (reader.isList) {
    final items = reader.listValue.map(_dartObjectToCode).join(', ');
    return '[$items]';
  }
  if (reader.isMap) {
    final entries = reader.mapValue.entries
        .map((entry) {
          final key = entry.key;
          if (key == null) {
            throw InvalidGenerationSourceError(
              'Map keys in annotations must be non-null constants.',
            );
          }
          final keyCode = _dartObjectToCode(key);
          final value = entry.value;
          if (value == null) {
            return '$keyCode: null';
          }
          return '$keyCode: ${_dartObjectToCode(value)}';
        })
        .join(', ');
    return '{$entries}';
  }

  final revived = reader.revive();
  if (revived.isPrivate) {
    throw InvalidGenerationSourceError(
      'Annotation values must reference public constants.',
    );
  }
  return _reviveToCode(revived);
}

String _reviveToCode(Revivable revived) {
  final source = revived.source;
  if (source.scheme == 'package' && source.pathSegments.isNotEmpty) {
    final package = source.pathSegments.first;
    if (package != 'stem') {
      throw InvalidGenerationSourceError(
        'Annotation values from package:$package are not supported yet.',
      );
    }
  }

  final args = <String>[];
  for (final arg in revived.positionalArguments) {
    args.add(_dartObjectToCode(arg));
  }
  revived.namedArguments.forEach((key, value) {
    args.add('$key: ${_dartObjectToCode(value)}');
  });
  final argsCode = args.join(', ');

  if (source.fragment.isEmpty) {
    if (args.isEmpty) {
      return revived.accessor;
    }
    return '${revived.accessor}($argsCode)';
  }
  final accessor = revived.accessor.isEmpty ? '' : '.${revived.accessor}';
  return 'const ${source.fragment}$accessor($argsCode)';
}

String _string(String value) => jsonEncode(value);
