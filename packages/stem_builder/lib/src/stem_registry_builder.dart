// Registry codegen emits repeated buffer writes and long string literals.
// ignore_for_file: avoid_catches_without_on_clauses, cascade_invocations, lines_longer_than_80_chars

import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:source_gen/source_gen.dart';
import 'package:stem/stem.dart';

/// Builder that emits a consolidated registry for annotated workflows/tasks.
class StemRegistryBuilder implements Builder {
  /// Creates the registry builder.
  StemRegistryBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
    'lib/{{}}.dart': ['lib/{{}}.stem.g.dart'],
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
    const scriptStepContextChecker = TypeChecker.typeNamed(
      WorkflowScriptStepContext,
      inPackage: 'stem',
    );
    const taskContextChecker = TypeChecker.typeNamed(
      TaskInvocationContext,
      inPackage: 'stem',
    );
    const mapChecker = TypeChecker.typeNamed(Map, inSdk: true);

    final input = buildStep.inputId;
    if (!input.path.startsWith('lib/') ||
        input.path.endsWith('.g.dart') ||
        input.path.endsWith('.stem.g.dart')) {
      return;
    }

    final workflows = <_WorkflowInfo>[];
    final tasks = <_TaskInfo>[];
    var taskAdapterIndex = 0;

    if (!await buildStep.resolver.isLibrary(input)) {
      return;
    }

    final library = await buildStep.resolver.libraryFor(input);
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

      if (kind == WorkflowKind.script) {
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
        final runBinding = _validateRunMethod(
          runMethod,
          scriptContextChecker,
        );
        final scriptSteps = <_WorkflowStepInfo>[];
        for (final method in stepMethods) {
          final stepBinding = _validateScriptStepMethod(
            method,
            scriptStepContextChecker,
          );
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
          scriptSteps.add(
            _WorkflowStepInfo(
              name: stepName,
              method: method.displayName,
              acceptsFlowContext: false,
              acceptsScriptStepContext: stepBinding.acceptsContext,
              valueParameters: stepBinding.valueParameters,
              returnTypeCode: stepBinding.returnTypeCode,
              stepValueTypeCode: stepBinding.stepValueTypeCode,
              autoVersion: autoVersion,
              title: title,
              kind: kindValue,
              taskNames: taskNames,
              metadata: stepMetadata,
            ),
          );
        }
        workflows.add(
          _WorkflowInfo.script(
            name: workflowName,
            importAlias: '',
            className: classElement.displayName,
            steps: scriptSteps,
            runMethod: runMethod.displayName,
            runAcceptsScriptContext: runBinding.acceptsContext,
            runValueParameters: runBinding.valueParameters,
            version: version,
            description: description,
            metadata: metadata,
          ),
        );
        continue;
      }

      if (runMethods.isNotEmpty) {
        throw InvalidGenerationSourceError(
          'Workflow ${classElement.displayName} has @workflow.run but is not marked as script.',
          element: classElement,
        );
      }
      if (stepMethods.isEmpty) {
        throw InvalidGenerationSourceError(
          'Workflow ${classElement.displayName} has no @workflow.step methods.',
          element: classElement,
        );
      }
      final steps = <_WorkflowStepInfo>[];
      for (final method in stepMethods) {
        final stepBinding = _validateFlowStepMethod(
          method,
          flowContextChecker,
        );
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
            acceptsFlowContext: stepBinding.acceptsContext,
            acceptsScriptStepContext: false,
            valueParameters: stepBinding.valueParameters,
            returnTypeCode: null,
            stepValueTypeCode: null,
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
          importAlias: '',
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
      final taskBinding = _validateTaskFunction(
        function,
        taskContextChecker,
        mapChecker,
      );
      final readerAnnotation = ConstantReader(annotation);
      final taskName =
          _stringOrNull(readerAnnotation.peek('name')) ?? function.displayName;
      final options = _objectOrNull(readerAnnotation.peek('options'));
      final metadata = _objectOrNull(readerAnnotation.peek('metadata'));
      final runInIsolate = _boolOrDefault(
        readerAnnotation.peek('runInIsolate'),
        true,
      );

      tasks.add(
        _TaskInfo(
          name: taskName,
          importAlias: '',
          function: function.displayName,
          adapterName: taskBinding.usesLegacyMapArgs
              ? null
              : '_stemTaskAdapter${taskAdapterIndex++}',
          acceptsTaskContext: taskBinding.acceptsContext,
          valueParameters: taskBinding.valueParameters,
          usesLegacyMapArgs: taskBinding.usesLegacyMapArgs,
          options: options,
          metadata: metadata,
          runInIsolate: runInIsolate,
        ),
      );
    }

    final outputId = buildStep.allowedOutputs.single;
    final fileName = input.pathSegments.last;
    final generatedFileName = fileName.replaceFirst('.dart', '.stem.g.dart');
    final source = await buildStep.readAsString(input);
    final declaresGeneratedPart =
        source.contains("part '$generatedFileName';") ||
        source.contains('part "$generatedFileName";');
    if (workflows.isEmpty && tasks.isEmpty) {
      if (!declaresGeneratedPart) {
        return;
      }
      await buildStep.writeAsString(
        outputId,
        _format(_RegistryEmitter.emptyPart(fileName: fileName)),
      );
      return;
    }

    final registryCode = _RegistryEmitter(
      workflows: workflows,
      tasks: tasks,
    ).emit(partOfFile: fileName);
    final formatted = _format(registryCode);
    await buildStep.writeAsString(outputId, formatted);
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

  static _RunBinding _validateRunMethod(
    MethodElement method,
    TypeChecker scriptContextChecker,
  ) {
    if (method.isPrivate) {
      throw InvalidGenerationSourceError(
        '@workflow.run method ${method.displayName} must be public.',
        element: method,
      );
    }

    final parameters = method.formalParameters;
    var acceptsContext = false;
    var startIndex = 0;
    if (parameters.isNotEmpty &&
        scriptContextChecker.isAssignableFromType(parameters.first.type)) {
      acceptsContext = true;
      startIndex = 1;
    }

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in parameters.skip(startIndex)) {
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@workflow.run method ${method.displayName} only supports required positional serializable parameters after WorkflowScriptContext.',
          element: method,
        );
      }
      if (!_isSerializableValueType(parameter.type)) {
        throw InvalidGenerationSourceError(
          '@workflow.run method ${method.displayName} parameter "${parameter.displayName}" must use a serializable type.',
          element: method,
        );
      }
      valueParameters.add(
        _ValueParameterInfo(
          name: parameter.displayName,
          typeCode: _typeCode(parameter.type),
        ),
      );
    }

    return _RunBinding(
      acceptsContext: acceptsContext,
      valueParameters: valueParameters,
    );
  }

  static _FlowStepBinding _validateFlowStepMethod(
    MethodElement method,
    TypeChecker flowContextChecker,
  ) {
    if (method.isPrivate) {
      throw InvalidGenerationSourceError(
        '@workflow.step method ${method.displayName} must be public.',
        element: method,
      );
    }
    final parameters = method.formalParameters;
    var acceptsContext = false;
    var startIndex = 0;
    if (parameters.isNotEmpty &&
        flowContextChecker.isAssignableFromType(parameters.first.type)) {
      acceptsContext = true;
      startIndex = 1;
    }

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in parameters.skip(startIndex)) {
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} only supports required positional serializable parameters after FlowContext.',
          element: method,
        );
      }
      if (!_isSerializableValueType(parameter.type)) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} parameter "${parameter.displayName}" must use a serializable type.',
          element: method,
        );
      }
      valueParameters.add(
        _ValueParameterInfo(
          name: parameter.displayName,
          typeCode: _typeCode(parameter.type),
        ),
      );
    }

    return _FlowStepBinding(
      acceptsContext: acceptsContext,
      valueParameters: valueParameters,
    );
  }

  static _ScriptStepBinding _validateScriptStepMethod(
    MethodElement method,
    TypeChecker scriptStepContextChecker,
  ) {
    if (method.isPrivate) {
      throw InvalidGenerationSourceError(
        '@workflow.step method ${method.displayName} must be public.',
        element: method,
      );
    }
    final returnType = method.returnType;
    final isFutureLike =
        returnType.isDartAsyncFuture || returnType.isDartAsyncFutureOr;
    if (!isFutureLike) {
      throw InvalidGenerationSourceError(
        '@workflow.step method ${method.displayName} in script workflows must return Future<T> or FutureOr<T>.',
        element: method,
      );
    }
    final stepValueType = _extractStepValueType(returnType);

    final parameters = method.formalParameters;
    var acceptsContext = false;
    var startIndex = 0;
    if (parameters.isNotEmpty &&
        scriptStepContextChecker.isAssignableFromType(parameters.first.type)) {
      acceptsContext = true;
      startIndex = 1;
    }

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in parameters.skip(startIndex)) {
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} only supports required positional serializable parameters after WorkflowScriptStepContext.',
          element: method,
        );
      }
      if (!_isSerializableValueType(parameter.type)) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} parameter "${parameter.displayName}" must use a serializable type.',
          element: method,
        );
      }
      valueParameters.add(
        _ValueParameterInfo(
          name: parameter.displayName,
          typeCode: _typeCode(parameter.type),
        ),
      );
    }

    return _ScriptStepBinding(
      acceptsContext: acceptsContext,
      valueParameters: valueParameters,
      returnTypeCode: _typeCode(returnType),
      stepValueTypeCode: _typeCode(stepValueType),
    );
  }

  static _TaskBinding _validateTaskFunction(
    TopLevelFunctionElement function,
    TypeChecker taskContextChecker,
    TypeChecker mapChecker,
  ) {
    final parameters = function.formalParameters;
    var acceptsContext = false;
    var startIndex = 0;
    if (parameters.isNotEmpty &&
        taskContextChecker.isAssignableFromType(parameters.first.type)) {
      acceptsContext = true;
      startIndex = 1;
    }

    final remaining = parameters.skip(startIndex).toList(growable: false);
    final legacyMapSignature =
        acceptsContext &&
        remaining.length == 1 &&
        mapChecker.isAssignableFromType(remaining.first.type) &&
        _isStringObjectMap(remaining.first.type) &&
        remaining.first.isRequiredPositional;
    if (legacyMapSignature) {
      return const _TaskBinding(
        acceptsContext: true,
        valueParameters: [],
        usesLegacyMapArgs: true,
      );
    }

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in remaining) {
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@TaskDefn function ${function.displayName} only supports required positional serializable parameters after TaskInvocationContext.',
          element: function,
        );
      }
      if (!_isSerializableValueType(parameter.type)) {
        throw InvalidGenerationSourceError(
          '@TaskDefn function ${function.displayName} parameter "${parameter.displayName}" must use a serializable type.',
          element: function,
        );
      }
      valueParameters.add(
        _ValueParameterInfo(
          name: parameter.displayName,
          typeCode: _typeCode(parameter.type),
        ),
      );
    }

    return _TaskBinding(
      acceptsContext: acceptsContext,
      valueParameters: valueParameters,
      usesLegacyMapArgs: false,
    );
  }

  static bool _isStringObjectMap(DartType type) {
    if (type is! InterfaceType) return false;
    if (!type.isDartCoreMap) return false;
    if (type.typeArguments.length != 2) return false;
    final keyType = type.typeArguments[0];
    final valueType = type.typeArguments[1];
    if (!keyType.isDartCoreString) return false;
    if (!valueType.isDartCoreObject) return false;
    return valueType.nullabilitySuffix == NullabilitySuffix.question;
  }

  static bool _isSerializableValueType(DartType type) {
    if (type is DynamicType) return false;
    if (type is VoidType) return false;
    if (type is NeverType) return false;
    if (type.isDartCoreString ||
        type.isDartCoreBool ||
        type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreNum ||
        type.isDartCoreObject ||
        type.isDartCoreNull) {
      return true;
    }
    if (type is! InterfaceType) return false;
    if (type.isDartCoreList) {
      if (type.typeArguments.length != 1) return false;
      return _isSerializableValueType(type.typeArguments.first);
    }
    if (type.isDartCoreMap) {
      if (type.typeArguments.length != 2) return false;
      final keyType = type.typeArguments[0];
      final valueType = type.typeArguments[1];
      if (!keyType.isDartCoreString) return false;
      return _isSerializableValueType(valueType);
    }
    return false;
  }

  static String _typeCode(DartType type) => type.getDisplayString();

  static DartType _extractStepValueType(DartType returnType) {
    if (returnType is InterfaceType && returnType.typeArguments.isNotEmpty) {
      return returnType.typeArguments.first;
    }
    return returnType;
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
    required this.importAlias,
    required this.className,
    required this.steps,
    this.version,
    this.description,
    this.metadata,
  }) : kind = WorkflowKind.flow,
       runMethod = null,
       runAcceptsScriptContext = false,
       runValueParameters = const [];

  _WorkflowInfo.script({
    required this.name,
    required this.importAlias,
    required this.className,
    required this.steps,
    required this.runMethod,
    required this.runAcceptsScriptContext,
    required this.runValueParameters,
    this.version,
    this.description,
    this.metadata,
  }) : kind = WorkflowKind.script;

  final String name;
  final WorkflowKind kind;
  final String importAlias;
  final String className;
  final List<_WorkflowStepInfo> steps;
  final String? runMethod;
  final bool runAcceptsScriptContext;
  final List<_ValueParameterInfo> runValueParameters;
  final String? version;
  final String? description;
  final DartObject? metadata;
}

class _WorkflowStepInfo {
  const _WorkflowStepInfo({
    required this.name,
    required this.method,
    required this.acceptsFlowContext,
    required this.acceptsScriptStepContext,
    required this.valueParameters,
    required this.returnTypeCode,
    required this.stepValueTypeCode,
    required this.autoVersion,
    required this.title,
    required this.kind,
    required this.taskNames,
    required this.metadata,
  });

  final String name;
  final String method;
  final bool acceptsFlowContext;
  final bool acceptsScriptStepContext;
  final List<_ValueParameterInfo> valueParameters;
  final String? returnTypeCode;
  final String? stepValueTypeCode;
  final bool autoVersion;
  final String? title;
  final DartObject? kind;
  final DartObject? taskNames;
  final DartObject? metadata;
}

class _TaskInfo {
  const _TaskInfo({
    required this.name,
    required this.importAlias,
    required this.function,
    required this.adapterName,
    required this.acceptsTaskContext,
    required this.valueParameters,
    required this.usesLegacyMapArgs,
    required this.options,
    required this.metadata,
    required this.runInIsolate,
  });

  final String name;
  final String importAlias;
  final String function;
  final String? adapterName;
  final bool acceptsTaskContext;
  final List<_ValueParameterInfo> valueParameters;
  final bool usesLegacyMapArgs;
  final DartObject? options;
  final DartObject? metadata;
  final bool runInIsolate;
}

class _FlowStepBinding {
  const _FlowStepBinding({
    required this.acceptsContext,
    required this.valueParameters,
  });

  final bool acceptsContext;
  final List<_ValueParameterInfo> valueParameters;
}

class _RunBinding {
  const _RunBinding({
    required this.acceptsContext,
    required this.valueParameters,
  });

  final bool acceptsContext;
  final List<_ValueParameterInfo> valueParameters;
}

class _ScriptStepBinding {
  const _ScriptStepBinding({
    required this.acceptsContext,
    required this.valueParameters,
    required this.returnTypeCode,
    required this.stepValueTypeCode,
  });

  final bool acceptsContext;
  final List<_ValueParameterInfo> valueParameters;
  final String returnTypeCode;
  final String stepValueTypeCode;
}

class _TaskBinding {
  const _TaskBinding({
    required this.acceptsContext,
    required this.valueParameters,
    required this.usesLegacyMapArgs,
  });

  final bool acceptsContext;
  final List<_ValueParameterInfo> valueParameters;
  final bool usesLegacyMapArgs;
}

class _ValueParameterInfo {
  const _ValueParameterInfo({
    required this.name,
    required this.typeCode,
  });

  final String name;
  final String typeCode;
}

class _RegistryEmitter {
  _RegistryEmitter({
    required this.workflows,
    required this.tasks,
  });

  final List<_WorkflowInfo> workflows;
  final List<_TaskInfo> tasks;

  static String emptyPart({required String fileName}) {
    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln(
      '// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import',
    );
    buffer.writeln();
    buffer.writeln("part of '$fileName';");
    return buffer.toString();
  }

  String emit({required String partOfFile}) {
    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln(
      '// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import',
    );
    buffer.writeln();
    buffer.writeln("part of '$partOfFile';");
    buffer.writeln();

    _emitWorkflows(buffer);
    _emitWorkflowStartHelpers(buffer);
    _emitManifest(buffer);
    _emitGeneratedHelpers(buffer);
    _emitTaskAdapters(buffer);
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
    buffer.writeln();
    buffer.writeln('Future<StemWorkflowApp> createStemGeneratedWorkflowApp({');
    buffer.writeln('  required StemApp stemApp,');
    buffer.writeln('  bool registerTasks = true,');
    buffer.writeln(
      '  Duration pollInterval = const Duration(milliseconds: 500),',
    );
    buffer.writeln(
      '  Duration leaseExtension = const Duration(seconds: 30),',
    );
    buffer.writeln('  WorkflowRegistry? workflowRegistry,');
    buffer.writeln('  WorkflowIntrospectionSink? introspectionSink,');
    buffer.writeln('}) async {');
    buffer.writeln('  if (registerTasks) {');
    buffer.writeln('    for (final handler in stemTasks) {');
    buffer.writeln('      stemApp.register(handler);');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln('  return StemWorkflowApp.create(');
    buffer.writeln('    stemApp: stemApp,');
    buffer.writeln('    flows: stemFlows,');
    buffer.writeln('    scripts: stemScripts,');
    buffer.writeln('    pollInterval: pollInterval,');
    buffer.writeln('    leaseExtension: leaseExtension,');
    buffer.writeln('    workflowRegistry: workflowRegistry,');
    buffer.writeln('    introspectionSink: introspectionSink,');
    buffer.writeln('  );');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln(
      'Future<StemWorkflowApp> createStemGeneratedInMemoryApp() async {',
    );
    buffer.writeln(
      '  final stemApp = await StemApp.inMemory(tasks: stemTasks);',
    );
    buffer.writeln('  return createStemGeneratedWorkflowApp(');
    buffer.writeln('    stemApp: stemApp,');
    buffer.writeln('    registerTasks: false,');
    buffer.writeln('  );');
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
      buffer.writeln(
        '      final impl = ${_qualify(workflow.importAlias, workflow.className)}();',
      );
      for (final step in workflow.steps) {
        final stepArgs = step.valueParameters
            .map((param) => _decodeArg('ctx.params', param))
            .join(', ');
        final invocationArgs = <String>[
          if (step.acceptsFlowContext) 'ctx',
          if (stepArgs.isNotEmpty) stepArgs,
        ].join(', ');
        buffer.writeln('      flow.step(');
        buffer.writeln('        ${_string(step.name)},');
        buffer.writeln(
          '        (ctx) => impl.${step.method}($invocationArgs),',
        );
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

    final scriptWorkflows = workflows
        .where((workflow) => workflow.kind == WorkflowKind.script)
        .toList(growable: false);
    final scriptProxyClassNames = <_WorkflowInfo, String>{};
    var scriptProxyIndex = 0;
    for (final workflow in scriptWorkflows) {
      if (workflow.steps.isEmpty) {
        continue;
      }
      final proxyClassName = '_StemScriptProxy${scriptProxyIndex++}';
      scriptProxyClassNames[workflow] = proxyClassName;
      buffer.writeln(
        'class $proxyClassName extends ${_qualify(workflow.importAlias, workflow.className)} {',
      );
      buffer.writeln('  $proxyClassName(this._script);');
      buffer.writeln('  final WorkflowScriptContext _script;');
      for (final step in workflow.steps) {
        final signatureParts = <String>[
          if (step.acceptsScriptStepContext)
            'WorkflowScriptStepContext context',
          ...step.valueParameters.map(
            (parameter) => '${parameter.typeCode} ${parameter.name}',
          ),
        ];
        final invocationArgs = <String>[
          if (step.acceptsScriptStepContext) 'context',
          ...step.valueParameters.map((parameter) => parameter.name),
        ];
        buffer.writeln('  @override');
        buffer.writeln(
          '  ${step.returnTypeCode} ${step.method}(${signatureParts.join(', ')}) {',
        );
        buffer.writeln('    return _script.step<${step.stepValueTypeCode}>(');
        buffer.writeln('      ${_string(step.name)},');
        buffer.writeln(
          '      (context) => super.${step.method}(${invocationArgs.join(', ')}),',
        );
        if (step.autoVersion) {
          buffer.writeln('      autoVersion: true,');
        }
        buffer.writeln('    );');
        buffer.writeln('  }');
      }
      buffer.writeln('}');
      buffer.writeln();
    }

    buffer.writeln(
      'final List<WorkflowScript> stemScripts = <WorkflowScript>[',
    );
    for (final workflow in scriptWorkflows) {
      final proxyClass = scriptProxyClassNames[workflow];
      buffer.writeln('  WorkflowScript(');
      buffer.writeln('    name: ${_string(workflow.name)},');
      if (workflow.steps.isNotEmpty) {
        buffer.writeln('    steps: [');
        for (final step in workflow.steps) {
          buffer.writeln('      FlowStep(');
          buffer.writeln('        name: ${_string(step.name)},');
          buffer.writeln(
            '        handler: _stemScriptManifestStepNoop,',
          );
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
          buffer.writeln('      ),');
        }
        buffer.writeln('    ],');
      }
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
      if (proxyClass != null) {
        final runArgs = <String>[
          if (workflow.runAcceptsScriptContext) 'script',
          ...workflow.runValueParameters.map(
            (parameter) => _decodeArg('script.params', parameter),
          ),
        ].join(', ');
        buffer.writeln(
          '    run: (script) => $proxyClass(script).${workflow.runMethod}($runArgs),',
        );
      } else {
        final runArgs = <String>[
          if (workflow.runAcceptsScriptContext) 'script',
          ...workflow.runValueParameters.map(
            (parameter) => _decodeArg('script.params', parameter),
          ),
        ].join(', ');
        buffer.writeln(
          '    run: (script) => ${_qualify(workflow.importAlias, workflow.className)}().${workflow.runMethod}($runArgs),',
        );
      }
      buffer.writeln('  ),');
    }
    buffer.writeln('];');
    buffer.writeln();
  }

  void _emitWorkflowStartHelpers(StringBuffer buffer) {
    if (workflows.isEmpty) {
      return;
    }
    final symbolNames = _symbolNamesForWorkflows(workflows);
    final fieldNames = <_WorkflowInfo, String>{};
    final usedFields = <String>{};
    for (final workflow in workflows) {
      final base = _lowerCamel(symbolNames[workflow]!);
      var candidate = base;
      var suffix = 2;
      while (usedFields.contains(candidate)) {
        candidate = '$base$suffix';
        suffix += 1;
      }
      usedFields.add(candidate);
      fieldNames[workflow] = candidate;
    }

    buffer.writeln('abstract final class StemWorkflowNames {');
    for (final workflow in workflows) {
      buffer.writeln(
        '  static const String ${fieldNames[workflow]} = ${_string(workflow.name)};',
      );
    }
    buffer.writeln('}');
    buffer.writeln();

    _emitWorkflowStarterExtension(
      buffer,
      extensionName: 'StemGeneratedWorkflowAppStarters',
      targetType: 'StemWorkflowApp',
      symbolNames: symbolNames,
      fieldNames: fieldNames,
    );
    _emitWorkflowStarterExtension(
      buffer,
      extensionName: 'StemGeneratedWorkflowRuntimeStarters',
      targetType: 'WorkflowRuntime',
      symbolNames: symbolNames,
      fieldNames: fieldNames,
    );
  }

  void _emitWorkflowStarterExtension(
    StringBuffer buffer, {
    required String extensionName,
    required String targetType,
    required Map<_WorkflowInfo, String> symbolNames,
    required Map<_WorkflowInfo, String> fieldNames,
  }) {
    buffer.writeln('extension $extensionName on $targetType {');
    for (final workflow in workflows) {
      final methodName = 'start${symbolNames[workflow]}';
      if (workflow.kind == WorkflowKind.script &&
          workflow.runValueParameters.isNotEmpty) {
        buffer.writeln('  Future<String> $methodName({');
        for (final parameter in workflow.runValueParameters) {
          buffer.writeln(
            '    required ${parameter.typeCode} ${parameter.name},',
          );
        }
        buffer.writeln('    Map<String, Object?> extraParams = const {},');
        buffer.writeln('    String? parentRunId,');
        buffer.writeln('    Duration? ttl,');
        buffer.writeln(
          '    WorkflowCancellationPolicy? cancellationPolicy,',
        );
        buffer.writeln('  }) {');
        buffer.writeln('    final params = <String, Object?>{');
        buffer.writeln('      ...extraParams,');
        for (final parameter in workflow.runValueParameters) {
          buffer.writeln(
            '      ${_string(parameter.name)}: ${parameter.name},',
          );
        }
        buffer.writeln('    };');
        buffer.writeln('    return startWorkflow(');
        buffer.writeln('      StemWorkflowNames.${fieldNames[workflow]},');
        buffer.writeln('      params: params,');
        buffer.writeln('      parentRunId: parentRunId,');
        buffer.writeln('      ttl: ttl,');
        buffer.writeln('      cancellationPolicy: cancellationPolicy,');
        buffer.writeln('    );');
        buffer.writeln('  }');
      } else {
        buffer.writeln('  Future<String> $methodName({');
        buffer.writeln('    Map<String, Object?> params = const {},');
        buffer.writeln('    String? parentRunId,');
        buffer.writeln('    Duration? ttl,');
        buffer.writeln(
          '    WorkflowCancellationPolicy? cancellationPolicy,',
        );
        buffer.writeln('  }) {');
        buffer.writeln('    return startWorkflow(');
        buffer.writeln('      StemWorkflowNames.${fieldNames[workflow]},');
        buffer.writeln('      params: params,');
        buffer.writeln('      parentRunId: parentRunId,');
        buffer.writeln('      ttl: ttl,');
        buffer.writeln('      cancellationPolicy: cancellationPolicy,');
        buffer.writeln('    );');
        buffer.writeln('  }');
      }
      buffer.writeln();
    }
    buffer.writeln('}');
    buffer.writeln();
  }

  Map<_WorkflowInfo, String> _symbolNamesForWorkflows(
    List<_WorkflowInfo> values,
  ) {
    final result = <_WorkflowInfo, String>{};
    final used = <String>{};
    for (final workflow in values) {
      final candidates = _workflowSymbolCandidates(workflow.name);
      var chosen = candidates.firstWhere(
        (candidate) => !used.contains(candidate),
        orElse: () => candidates.last,
      );
      if (used.contains(chosen)) {
        final base = chosen;
        var suffix = 2;
        while (used.contains(chosen)) {
          chosen = '$base$suffix';
          suffix += 1;
        }
      }
      used.add(chosen);
      result[workflow] = chosen;
    }
    return result;
  }

  List<String> _workflowSymbolCandidates(String workflowName) {
    final segments = workflowName
        .split('.')
        .map(_pascalIdentifier)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return const ['Workflow'];
    }
    final candidates = <String>[];
    for (var take = 1; take <= segments.length; take += 1) {
      candidates.add(
        segments.sublist(segments.length - take).join(),
      );
    }
    return candidates;
  }

  String _pascalIdentifier(String value) {
    final parts = value
        .split(RegExp('[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'Workflow';
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer
        ..write(part[0].toUpperCase())
        ..write(part.substring(1));
    }
    var result = buffer.toString();
    if (RegExp('^[0-9]').hasMatch(result)) {
      result = 'Workflow$result';
    }
    return result;
  }

  String _lowerCamel(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toLowerCase()}${value.substring(1)}';
  }

  void _emitTasks(StringBuffer buffer) {
    buffer.writeln(
      'final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[',
    );
    for (final task in tasks) {
      final entrypoint = task.usesLegacyMapArgs
          ? _qualify(task.importAlias, task.function)
          : task.adapterName!;
      buffer.writeln('  FunctionTaskHandler<Object?>(');
      buffer.writeln('    name: ${_string(task.name)},');
      buffer.writeln('    entrypoint: $entrypoint,');
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

  void _emitTaskAdapters(StringBuffer buffer) {
    final typedTasks = tasks.where((task) => !task.usesLegacyMapArgs).toList();
    if (typedTasks.isEmpty) {
      return;
    }
    for (final task in typedTasks) {
      final adapterName = task.adapterName!;
      final callArgs = <String>[
        if (task.acceptsTaskContext) 'context',
        ...task.valueParameters.map((param) => _decodeArg('args', param)),
      ].join(', ');
      buffer.writeln(
        'Future<Object?> $adapterName(TaskInvocationContext context, Map<String, Object?> args) async {',
      );
      buffer.writeln(
        '  return await Future<Object?>.value(${_qualify(task.importAlias, task.function)}($callArgs));',
      );
      buffer.writeln('}');
      buffer.writeln();
    }
  }

  void _emitGeneratedHelpers(StringBuffer buffer) {
    final needsScriptStepNoop = workflows.any(
      (workflow) =>
          workflow.kind == WorkflowKind.script && workflow.steps.isNotEmpty,
    );
    if (needsScriptStepNoop) {
      buffer.writeln(
        'Future<Object?> _stemScriptManifestStepNoop(FlowContext context) async => null;',
      );
      buffer.writeln();
    }

    final needsArgHelper =
        tasks.any((task) => !task.usesLegacyMapArgs) ||
        workflows.any(
          (workflow) =>
              workflow.runValueParameters.isNotEmpty ||
              workflow.steps.any((step) => step.valueParameters.isNotEmpty),
        );
    if (!needsArgHelper) {
      return;
    }
    buffer.writeln('Object? _stemRequireArg(');
    buffer.writeln('  Map<String, Object?> args,');
    buffer.writeln('  String name,');
    buffer.writeln(') {');
    buffer.writeln('  if (!args.containsKey(name)) {');
    buffer.writeln(
      "    throw ArgumentError('Missing required argument \"\$name\".');",
    );
    buffer.writeln('  }');
    buffer.writeln('  return args[name];');
    buffer.writeln('}');
    buffer.writeln();
  }

  void _emitManifest(StringBuffer buffer) {
    buffer.writeln(
      'final List<WorkflowManifestEntry> stemWorkflowManifest = <WorkflowManifestEntry>[',
    );
    buffer.writeln(
      '  ...stemFlows.map((flow) => flow.definition.toManifestEntry()),',
    );
    buffer.writeln(
      '  ...stemScripts.map((script) => script.definition.toManifestEntry()),',
    );
    buffer.writeln('];');
    buffer.writeln();
  }

  String _decodeArg(String sourceMap, _ValueParameterInfo parameter) {
    return '(_stemRequireArg($sourceMap, ${_string(parameter.name)}) '
        'as ${parameter.typeCode})';
  }

  String _qualify(String alias, String symbol) {
    if (alias.isEmpty) return symbol;
    return '$alias.$symbol';
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
