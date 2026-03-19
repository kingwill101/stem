// Registry codegen emits repeated buffer writes and long string literals.
// ignore_for_file: avoid_catches_without_on_clauses, cascade_invocations, lines_longer_than_80_chars

import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
      final starterName = _stringOrNull(readerAnnotation.peek('starterName'));
      final nameField = _stringOrNull(readerAnnotation.peek('nameField'));
      final kind = _readWorkflowKind(readerAnnotation);

      final annotatedRunMethods = classElement.methods
          .where(
            (method) =>
                workflowRunChecker.hasAnnotationOfExact(method) &&
                !method.isStatic,
          )
          .toList(growable: false);
      final inferredRunMethods = classElement.methods
          .where(
            (method) => method.displayName == 'run' && !method.isStatic,
          )
          .toList(growable: false);
      final runMethods = kind == WorkflowKind.script
          ? (annotatedRunMethods.isNotEmpty
                ? annotatedRunMethods
                : inferredRunMethods)
          : annotatedRunMethods;
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
            'Workflow ${classElement.displayName} is marked as script but has no run entry method. Add @WorkflowRun or define a public run(...) method.',
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
              flowContextParameterName: null,
              flowContextIsNamed: false,
              scriptStepContextParameterName: stepBinding.contextParameterName,
              scriptStepContextIsNamed: stepBinding.contextIsNamed,
              valueParameters: stepBinding.valueParameters,
              returnTypeCode: stepBinding.returnTypeCode,
              stepValueTypeCode: stepBinding.stepValueTypeCode,
              stepValuePayloadCodecTypeCode:
                  stepBinding.stepValuePayloadCodecTypeCode,
              autoVersion: autoVersion,
              title: title,
              kind: kindValue,
              taskNames: taskNames,
              metadata: stepMetadata,
            ),
          );
        }
        _ensureUniqueWorkflowStepNames(
          classElement,
          scriptSteps,
          label: 'checkpoint',
        );
        await _diagnoseScriptCheckpointPatterns(
          buildStep,
          classElement,
          runMethod,
          scriptSteps,
          runAcceptsScriptContext: runBinding.contextParameterName != null,
        );
        workflows.add(
          _WorkflowInfo.script(
            name: workflowName,
            importAlias: '',
            className: classElement.displayName,
            steps: scriptSteps,
            runMethod: runMethod.displayName,
            runContextParameterName: runBinding.contextParameterName,
            runContextIsNamed: runBinding.contextIsNamed,
            runValueParameters: runBinding.valueParameters,
            resultTypeCode: runBinding.resultTypeCode,
            resultPayloadCodecTypeCode: runBinding.resultPayloadCodecTypeCode,
            version: version,
            description: description,
            metadata: metadata,
            starterNameOverride: starterName,
            nameFieldOverride: nameField,
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
            flowContextParameterName: stepBinding.contextParameterName,
            flowContextIsNamed: stepBinding.contextIsNamed,
            scriptStepContextParameterName: null,
            scriptStepContextIsNamed: false,
            valueParameters: stepBinding.valueParameters,
            returnTypeCode: null,
            stepValueTypeCode: stepBinding.stepValueTypeCode,
            stepValuePayloadCodecTypeCode:
                stepBinding.stepValuePayloadCodecTypeCode,
            autoVersion: autoVersion,
            title: title,
            kind: kindValue,
            taskNames: taskNames,
            metadata: stepMetadata,
          ),
        );
      }
      _ensureUniqueWorkflowStepNames(classElement, steps, label: 'step');
      workflows.add(
        _WorkflowInfo.flow(
          name: workflowName,
          importAlias: '',
          className: classElement.displayName,
          steps: steps,
          resultTypeCode:
              steps.isEmpty ? 'Object?' : (steps.last.stepValueTypeCode ?? 'Object?'),
          resultPayloadCodecTypeCode: steps.isEmpty
              ? null
              : steps.last.stepValuePayloadCodecTypeCode,
          version: version,
          description: description,
          metadata: metadata,
          starterNameOverride: starterName,
          nameFieldOverride: nameField,
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
      final metadataReader = readerAnnotation.peek('metadata');
      final metadataResultEncoder = metadataReader?.peek('resultEncoder');
      if (taskBinding.resultPayloadCodecTypeCode != null &&
          metadataResultEncoder != null &&
          !metadataResultEncoder.isNull) {
        throw InvalidGenerationSourceError(
          '@TaskDefn function ${function.displayName} defines a codec-backed DTO result and an explicit metadata.resultEncoder. Choose one encoding path.',
          element: function,
        );
      }
      final runInIsolate = _boolOrDefault(
        readerAnnotation.peek('runInIsolate'),
        true,
      );

      tasks.add(
        _TaskInfo(
          name: taskName,
          importAlias: '',
          function: function.displayName,
          adapterName:
              taskBinding.usesLegacyMapArgs && !taskBinding.contextIsNamed
              ? null
              : '_stemTaskAdapter${taskAdapterIndex++}',
          taskContextParameterName: taskBinding.contextParameterName,
          taskContextIsNamed: taskBinding.contextIsNamed,
          valueParameters: taskBinding.valueParameters,
          usesLegacyMapArgs: taskBinding.usesLegacyMapArgs,
          resultTypeCode: taskBinding.resultTypeCode,
          resultPayloadCodecTypeCode: taskBinding.resultPayloadCodecTypeCode,
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
    final contextParameter = _extractInjectedContextParameter(
      parameters,
      scriptContextChecker,
      method,
      annotationLabel: '@workflow.run method',
      contextTypeLabel: 'WorkflowScriptContext',
    );

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in parameters) {
      if (identical(parameter, contextParameter?.parameter)) {
        continue;
      }
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@workflow.run method ${method.displayName} only supports required positional serializable or codec-backed parameters after WorkflowScriptContext.',
          element: method,
        );
      }
      final valueParameter = _createValueParameterInfo(parameter);
      if (valueParameter == null) {
        throw InvalidGenerationSourceError(
          '@workflow.run method ${method.displayName} parameter "${parameter.displayName}" must use a serializable or codec-backed DTO type.',
          element: method,
        );
      }
      valueParameters.add(valueParameter);
    }

    return _RunBinding(
      contextParameterName: contextParameter?.name,
      contextIsNamed: contextParameter?.isNamed ?? false,
      valueParameters: valueParameters,
      resultTypeCode: _workflowResultTypeCode(method.returnType),
      resultPayloadCodecTypeCode: _workflowResultPayloadCodecTypeCode(
        method.returnType,
      ),
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
    final contextParameter = _extractInjectedContextParameter(
      parameters,
      flowContextChecker,
      method,
      annotationLabel: '@workflow.step method',
      contextTypeLabel: 'FlowContext',
    );

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in parameters) {
      if (identical(parameter, contextParameter?.parameter)) {
        continue;
      }
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} only supports required positional serializable or codec-backed parameters after FlowContext.',
          element: method,
        );
      }
      final valueParameter = _createValueParameterInfo(parameter);
      if (valueParameter == null) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} parameter "${parameter.displayName}" must use a serializable or codec-backed DTO type.',
          element: method,
        );
      }
      valueParameters.add(valueParameter);
    }

    return _FlowStepBinding(
      contextParameterName: contextParameter?.name,
      contextIsNamed: contextParameter?.isNamed ?? false,
      valueParameters: valueParameters,
      stepValueTypeCode: _workflowResultTypeCode(method.returnType),
      stepValuePayloadCodecTypeCode: _workflowResultPayloadCodecTypeCode(
        method.returnType,
      ),
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
    final contextParameter = _extractInjectedContextParameter(
      parameters,
      scriptStepContextChecker,
      method,
      annotationLabel: '@workflow.step method',
      contextTypeLabel: 'WorkflowScriptStepContext',
    );

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in parameters) {
      if (identical(parameter, contextParameter?.parameter)) {
        continue;
      }
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} only supports required positional serializable or codec-backed parameters after WorkflowScriptStepContext.',
          element: method,
        );
      }
      final valueParameter = _createValueParameterInfo(parameter);
      if (valueParameter == null) {
        throw InvalidGenerationSourceError(
          '@workflow.step method ${method.displayName} parameter "${parameter.displayName}" must use a serializable or codec-backed DTO type.',
          element: method,
        );
      }
      valueParameters.add(valueParameter);
    }

    return _ScriptStepBinding(
      contextParameterName: contextParameter?.name,
      contextIsNamed: contextParameter?.isNamed ?? false,
      valueParameters: valueParameters,
      returnTypeCode: _typeCode(returnType),
      stepValueTypeCode: _typeCode(stepValueType),
      stepValuePayloadCodecTypeCode: _payloadCodecTypeCode(stepValueType),
    );
  }

  static _TaskBinding _validateTaskFunction(
    TopLevelFunctionElement function,
    TypeChecker taskContextChecker,
    TypeChecker mapChecker,
  ) {
    final parameters = function.formalParameters;
    final contextParameter = _extractInjectedContextParameter(
      parameters,
      taskContextChecker,
      function,
      annotationLabel: '@TaskDefn function',
      contextTypeLabel: 'TaskInvocationContext',
    );

    final remaining = parameters
        .where((parameter) => !identical(parameter, contextParameter?.parameter))
        .toList(growable: false);
    final legacyMapSignature =
        contextParameter != null &&
        remaining.length == 1 &&
        mapChecker.isAssignableFromType(remaining.first.type) &&
        _isStringObjectMap(remaining.first.type) &&
        remaining.first.isRequiredPositional;
    if (legacyMapSignature) {
      return _TaskBinding(
        contextParameterName: contextParameter.name,
        contextIsNamed: contextParameter.isNamed,
        valueParameters: [],
        usesLegacyMapArgs: true,
        resultTypeCode: _taskResultTypeCode(function.returnType),
        resultPayloadCodecTypeCode: _taskResultPayloadCodecTypeCode(
          function.returnType,
        ),
      );
    }

    final valueParameters = <_ValueParameterInfo>[];
    for (final parameter in remaining) {
      if (!parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          '@TaskDefn function ${function.displayName} only supports required positional serializable or codec-backed parameters after TaskInvocationContext.',
          element: function,
        );
      }
      final valueParameter = _createValueParameterInfo(parameter);
      if (valueParameter == null) {
        throw InvalidGenerationSourceError(
          '@TaskDefn function ${function.displayName} parameter "${parameter.displayName}" must use a serializable or codec-backed DTO type.',
          element: function,
        );
      }
      valueParameters.add(valueParameter);
    }

    return _TaskBinding(
      contextParameterName: contextParameter?.name,
      contextIsNamed: contextParameter?.isNamed ?? false,
      valueParameters: valueParameters,
      usesLegacyMapArgs: false,
      resultTypeCode: _taskResultTypeCode(function.returnType),
      resultPayloadCodecTypeCode: _taskResultPayloadCodecTypeCode(
        function.returnType,
      ),
    );
  }

  static _ValueParameterInfo? _createValueParameterInfo(
    FormalParameterElement parameter,
  ) {
    final type = parameter.type;
    final codecTypeCode = _payloadCodecTypeCode(type);
    if (!_isSerializableValueType(type) && codecTypeCode == null) {
      return null;
    }
    return _ValueParameterInfo(
      name: parameter.displayName,
      typeCode: _typeCode(type),
      payloadCodecTypeCode: codecTypeCode,
    );
  }

  static _InjectedContextParameter? _extractInjectedContextParameter(
    List<FormalParameterElement> parameters,
    TypeChecker checker,
    Element element, {
    required String annotationLabel,
    required String contextTypeLabel,
  }) {
    _InjectedContextParameter? contextParameter;
    if (parameters.isNotEmpty &&
        parameters.first.isRequiredPositional &&
        checker.isAssignableFromType(parameters.first.type)) {
      contextParameter = _InjectedContextParameter(
        parameter: parameters.first,
        name: parameters.first.displayName,
        isNamed: false,
      );
    }

    for (final parameter in parameters.skip(
      contextParameter == null ? 0 : 1,
    )) {
      if (!checker.isAssignableFromType(parameter.type)) {
        continue;
      }
      if (contextParameter != null) {
        throw InvalidGenerationSourceError(
          '$annotationLabel ${element.displayName} may declare at most one '
          '$contextTypeLabel parameter.',
          element: element,
        );
      }
      if (!parameter.isNamed || parameter.isRequiredNamed) {
        throw InvalidGenerationSourceError(
          '$annotationLabel ${element.displayName} must declare '
          '$contextTypeLabel as the first positional parameter or an '
          'optional named parameter.',
          element: element,
        );
      }
      contextParameter = _InjectedContextParameter(
        parameter: parameter,
        name: parameter.displayName,
        isNamed: true,
      );
    }

    return contextParameter;
  }

  static String _taskResultTypeCode(DartType returnType) {
    final valueType = _extractAsyncValueType(returnType);
    if (valueType is VoidType || valueType is NeverType) {
      return 'Object?';
    }
    if (valueType.isDartCoreNull) {
      return 'Object?';
    }
    return _typeCode(valueType);
  }

  static String _workflowResultTypeCode(DartType returnType) {
    final valueType = _extractAsyncValueType(returnType);
    if (valueType is VoidType || valueType is NeverType) {
      return 'Object?';
    }
    if (valueType.isDartCoreNull) {
      return 'Object?';
    }
    return _typeCode(valueType);
  }

  static String? _taskResultPayloadCodecTypeCode(DartType returnType) {
    final valueType = _extractAsyncValueType(returnType);
    if (valueType is VoidType || valueType is NeverType) {
      return null;
    }
    if (valueType.isDartCoreNull) {
      return null;
    }
    return _payloadCodecTypeCode(valueType);
  }

  static String? _workflowResultPayloadCodecTypeCode(DartType returnType) {
    final valueType = _extractAsyncValueType(returnType);
    if (valueType is VoidType || valueType is NeverType) {
      return null;
    }
    if (valueType.isDartCoreNull) {
      return null;
    }
    return _payloadCodecTypeCode(valueType);
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

  static String? _payloadCodecTypeCode(DartType type) {
    if (type is! InterfaceType) return null;
    if (type.isDartCoreMap || type.isDartCoreList || type.isDartCoreSet) {
      return null;
    }
    if (type.element.typeParameters.isNotEmpty) {
      return null;
    }
    final toJson = type.element.methods.where(
      (method) =>
          method.name == 'toJson' &&
          !method.isStatic &&
          method.formalParameters.isEmpty &&
          _isStringKeyedMapLike(method.returnType),
    );
    if (toJson.isEmpty) {
      return null;
    }
    final fromJsonConstructor = type.element.constructors.where(
      (constructor) =>
          constructor.name == 'fromJson' &&
          constructor.formalParameters.length == 1 &&
          constructor.formalParameters.first.isRequiredPositional &&
          _isStringKeyedMapLike(constructor.formalParameters.first.type),
    );
    if (fromJsonConstructor.isEmpty) {
      return null;
    }
    return _typeCode(type);
  }

  static bool _isStringKeyedMapLike(DartType type) {
    if (type is! InterfaceType) return false;
    if (!type.isDartCoreMap) return false;
    if (type.typeArguments.length != 2) return false;
    final keyType = type.typeArguments[0];
    return keyType.isDartCoreString;
  }

  static String _typeCode(DartType type) => type.getDisplayString();

  static DartType _extractStepValueType(DartType returnType) {
    return _extractAsyncValueType(returnType);
  }

  static DartType _extractAsyncValueType(DartType returnType) {
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
    required this.resultTypeCode,
    required this.resultPayloadCodecTypeCode,
    this.starterNameOverride,
    this.nameFieldOverride,
    this.version,
    this.description,
    this.metadata,
  }) : kind = WorkflowKind.flow,
       runMethod = null,
       runContextParameterName = null,
       runContextIsNamed = false,
       runValueParameters = const [];

  _WorkflowInfo.script({
    required this.name,
    required this.importAlias,
    required this.className,
    required this.steps,
    required this.runMethod,
    required this.runContextParameterName,
    required this.runContextIsNamed,
    required this.runValueParameters,
    required this.resultTypeCode,
    required this.resultPayloadCodecTypeCode,
    this.starterNameOverride,
    this.nameFieldOverride,
    this.version,
    this.description,
    this.metadata,
  }) : kind = WorkflowKind.script;

  final String name;
  final WorkflowKind kind;
  final String importAlias;
  final String className;
  final List<_WorkflowStepInfo> steps;
  final String resultTypeCode;
  final String? resultPayloadCodecTypeCode;
  final String? runMethod;
  final String? runContextParameterName;
  final bool runContextIsNamed;
  final List<_ValueParameterInfo> runValueParameters;
  final String? starterNameOverride;
  final String? nameFieldOverride;
  final String? version;
  final String? description;
  final DartObject? metadata;
}

class _WorkflowStepInfo {
  const _WorkflowStepInfo({
    required this.name,
    required this.method,
    required this.flowContextParameterName,
    required this.flowContextIsNamed,
    required this.scriptStepContextParameterName,
    required this.scriptStepContextIsNamed,
    required this.valueParameters,
    required this.returnTypeCode,
    required this.stepValueTypeCode,
    required this.stepValuePayloadCodecTypeCode,
    required this.autoVersion,
    required this.title,
    required this.kind,
    required this.taskNames,
    required this.metadata,
  });

  final String name;
  final String method;
  final String? flowContextParameterName;
  final bool flowContextIsNamed;
  final String? scriptStepContextParameterName;
  final bool scriptStepContextIsNamed;
  final List<_ValueParameterInfo> valueParameters;
  final String? returnTypeCode;
  final String? stepValueTypeCode;
  final String? stepValuePayloadCodecTypeCode;
  final bool autoVersion;
  final String? title;
  final DartObject? kind;
  final DartObject? taskNames;
  final DartObject? metadata;

  bool get acceptsFlowContext => flowContextParameterName != null;

  bool get acceptsScriptStepContext => scriptStepContextParameterName != null;
}

void _ensureUniqueWorkflowStepNames(
  ClassElement classElement,
  Iterable<_WorkflowStepInfo> steps, {
  required String label,
}) {
  final namesByMethod = <String, List<String>>{};
  for (final step in steps) {
    namesByMethod.putIfAbsent(step.name, () => <String>[]).add(step.method);
  }

  final duplicates = namesByMethod.entries
      .where((entry) => entry.value.length > 1)
      .toList(growable: false);
  if (duplicates.isEmpty) {
    return;
  }

  final details = duplicates
      .map((entry) => '"${entry.key}" from ${entry.value.join(', ')}')
      .join('; ');
  throw InvalidGenerationSourceError(
    'Workflow ${classElement.displayName} defines duplicate $label names: '
    '$details.',
    element: classElement,
  );
}

Future<void> _diagnoseScriptCheckpointPatterns(
  BuildStep buildStep,
  ClassElement classElement,
  MethodElement runMethod,
  List<_WorkflowStepInfo> steps, {
  required bool runAcceptsScriptContext,
}) async {
  if (!runAcceptsScriptContext || steps.isEmpty) {
    return;
  }

  final astNode = await buildStep.resolver.astNodeFor(
    runMethod.firstFragment,
    resolve: true,
  );
  if (astNode is! MethodDeclaration) {
    return;
  }

  final stepsByMethod = {for (final step in steps) step.method: step};
  final manualSteps = _ManualScriptStepVisitor(stepsByMethod.keys.toSet())
    ..visitMethodDeclaration(astNode);

  for (final invocation in manualSteps.invocations) {
    final duplicateStep = invocation.stepName == null
        ? null
        : _findStepByName(steps, invocation.stepName!);
    if (duplicateStep != null) {
      throw InvalidGenerationSourceError(
        'Workflow ${classElement.displayName} defines manual checkpoint '
        '"${invocation.stepName}" that conflicts with annotated checkpoint '
        '"${duplicateStep.name}" on ${duplicateStep.method}.',
        element: runMethod,
      );
    }

    for (final methodName in invocation.annotatedMethodCalls) {
      final step = stepsByMethod[methodName];
      if (step == null || step.acceptsScriptStepContext) {
        continue;
      }
      final wrapperName = invocation.stepName ?? '<dynamic>';
      log.warning(
        'Workflow ${classElement.displayName} wraps annotated checkpoint '
        '"${step.name}" inside manual script.step("$wrapperName"). '
        'Call ${step.method}(...) directly from run(...) to avoid nested '
        'checkpoints.',
      );
    }
  }
}

_WorkflowStepInfo? _findStepByName(
  Iterable<_WorkflowStepInfo> steps,
  String stepName,
) {
  for (final step in steps) {
    if (step.name == stepName) {
      return step;
    }
  }
  return null;
}

class _ManualScriptStepVisitor extends RecursiveAstVisitor<void> {
  _ManualScriptStepVisitor(this.annotatedMethodNames);

  final Set<String> annotatedMethodNames;
  final List<_ManualScriptInvocation> invocations = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'step' && node.argumentList.arguments.length >= 2) {
      final nameArg = node.argumentList.arguments.first;
      final callbackArg = node.argumentList.arguments[1];
      final callback = callbackArg is FunctionExpression ? callbackArg : null;
      if (callback != null) {
        final collector = _AnnotatedMethodCallCollector(annotatedMethodNames);
        callback.body.accept(collector);
        invocations.add(
          _ManualScriptInvocation(
            stepName: nameArg is StringLiteral ? nameArg.stringValue : null,
            annotatedMethodCalls: collector.calls,
          ),
        );
      }
    }
    super.visitMethodInvocation(node);
  }
}

class _AnnotatedMethodCallCollector extends RecursiveAstVisitor<void> {
  _AnnotatedMethodCallCollector(this.annotatedMethodNames);

  final Set<String> annotatedMethodNames;
  final Set<String> calls = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final isWorkflowMethodTarget =
        target == null || target is ThisExpression || target is SuperExpression;
    if (isWorkflowMethodTarget &&
        annotatedMethodNames.contains(node.methodName.name)) {
      calls.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}

class _ManualScriptInvocation {
  const _ManualScriptInvocation({
    required this.stepName,
    required this.annotatedMethodCalls,
  });

  final String? stepName;
  final Set<String> annotatedMethodCalls;
}

class _TaskInfo {
  const _TaskInfo({
    required this.name,
    required this.importAlias,
    required this.function,
    required this.adapterName,
    required this.taskContextParameterName,
    required this.taskContextIsNamed,
    required this.valueParameters,
    required this.usesLegacyMapArgs,
    required this.resultTypeCode,
    required this.resultPayloadCodecTypeCode,
    required this.options,
    required this.metadata,
    required this.runInIsolate,
  });

  final String name;
  final String importAlias;
  final String function;
  final String? adapterName;
  final String? taskContextParameterName;
  final bool taskContextIsNamed;
  final List<_ValueParameterInfo> valueParameters;
  final bool usesLegacyMapArgs;
  final String resultTypeCode;
  final String? resultPayloadCodecTypeCode;
  final DartObject? options;
  final DartObject? metadata;
  final bool runInIsolate;

  bool get acceptsTaskContext => taskContextParameterName != null;
}

class _FlowStepBinding {
  const _FlowStepBinding({
    required this.contextParameterName,
    required this.contextIsNamed,
    required this.valueParameters,
    required this.stepValueTypeCode,
    required this.stepValuePayloadCodecTypeCode,
  });

  final String? contextParameterName;
  final bool contextIsNamed;
  final List<_ValueParameterInfo> valueParameters;
  final String stepValueTypeCode;
  final String? stepValuePayloadCodecTypeCode;
}

class _RunBinding {
  const _RunBinding({
    required this.contextParameterName,
    required this.contextIsNamed,
    required this.valueParameters,
    required this.resultTypeCode,
    required this.resultPayloadCodecTypeCode,
  });

  final String? contextParameterName;
  final bool contextIsNamed;
  final List<_ValueParameterInfo> valueParameters;
  final String resultTypeCode;
  final String? resultPayloadCodecTypeCode;
}

class _ScriptStepBinding {
  const _ScriptStepBinding({
    required this.contextParameterName,
    required this.contextIsNamed,
    required this.valueParameters,
    required this.returnTypeCode,
    required this.stepValueTypeCode,
    required this.stepValuePayloadCodecTypeCode,
  });

  final String? contextParameterName;
  final bool contextIsNamed;
  final List<_ValueParameterInfo> valueParameters;
  final String returnTypeCode;
  final String stepValueTypeCode;
  final String? stepValuePayloadCodecTypeCode;
}

class _TaskBinding {
  const _TaskBinding({
    required this.contextParameterName,
    required this.contextIsNamed,
    required this.valueParameters,
    required this.usesLegacyMapArgs,
    required this.resultTypeCode,
    required this.resultPayloadCodecTypeCode,
  });

  final String? contextParameterName;
  final bool contextIsNamed;
  final List<_ValueParameterInfo> valueParameters;
  final bool usesLegacyMapArgs;
  final String resultTypeCode;
  final String? resultPayloadCodecTypeCode;
}

class _ValueParameterInfo {
  const _ValueParameterInfo({
    required this.name,
    required this.typeCode,
    required this.payloadCodecTypeCode,
  });

  final String name;
  final String typeCode;
  final String? payloadCodecTypeCode;
}

class _InjectedContextParameter {
  const _InjectedContextParameter({
    required this.parameter,
    required this.name,
    required this.isNamed,
  });

  final FormalParameterElement parameter;
  final String name;
  final bool isNamed;
}

class _RegistryEmitter {
  _RegistryEmitter({
    required this.workflows,
    required this.tasks,
  }) : payloadCodecSymbols = _payloadCodecSymbolsFor(workflows, tasks);

  final List<_WorkflowInfo> workflows;
  final List<_TaskInfo> tasks;
  final Map<String, String> payloadCodecSymbols;

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

  static Map<String, String> _payloadCodecSymbolsFor(
    List<_WorkflowInfo> workflows,
    List<_TaskInfo> tasks,
  ) {
    final orderedTypes = <String>[];
    void addType(String? typeCode) {
      if (typeCode == null || orderedTypes.contains(typeCode)) return;
      orderedTypes.add(typeCode);
    }

    for (final workflow in workflows) {
      addType(workflow.resultPayloadCodecTypeCode);
      for (final parameter in workflow.runValueParameters) {
        addType(parameter.payloadCodecTypeCode);
      }
      for (final step in workflow.steps) {
        addType(step.stepValuePayloadCodecTypeCode);
        for (final parameter in step.valueParameters) {
          addType(parameter.payloadCodecTypeCode);
        }
      }
    }
    for (final task in tasks) {
      for (final parameter in task.valueParameters) {
        addType(parameter.payloadCodecTypeCode);
      }
      addType(task.resultPayloadCodecTypeCode);
    }

    final result = <String, String>{};
    final used = <String>{};
    for (final typeCode in orderedTypes) {
      var candidate = _lowerCamelStatic(_pascalIdentifierStatic(typeCode));
      if (candidate.isEmpty) {
        candidate = 'payloadCodec';
      }
      if (used.contains(candidate)) {
        final base = candidate;
        var suffix = 2;
        while (used.contains(candidate)) {
          candidate = '$base$suffix';
          suffix += 1;
        }
      }
      used.add(candidate);
      result[typeCode] = candidate;
    }
    return result;
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

    _emitPayloadCodecs(buffer);
    _emitWorkflows(buffer);
    _emitWorkflowStartHelpers(buffer);
    _emitGeneratedHelpers(buffer);
    _emitTaskAdapters(buffer);
    _emitTaskDefinitions(buffer);
    _emitTasks(buffer);
    _emitManifest(buffer);
    _emitModule(buffer);
    return buffer.toString();
  }

  void _emitPayloadCodecs(StringBuffer buffer) {
    if (payloadCodecSymbols.isEmpty) {
      return;
    }
    buffer.writeln('Map<String, Object?> _stemPayloadMap(');
    buffer.writeln('  Object? value,');
    buffer.writeln('  String typeName,');
    buffer.writeln(') {');
    buffer.writeln('  if (value is Map<String, Object?>) {');
    buffer.writeln('    return Map<String, Object?>.from(value);');
    buffer.writeln('  }');
    buffer.writeln('  if (value is Map) {');
    buffer.writeln('    final result = <String, Object?>{};');
    buffer.writeln('    value.forEach((key, entry) {');
    buffer.writeln('      if (key is! String) {');
    buffer.writeln(
      r"        throw StateError('$typeName payload must use string keys.');",
    );
    buffer.writeln('      }');
    buffer.writeln('      result[key] = entry;');
    buffer.writeln('    });');
    buffer.writeln('    return result;');
    buffer.writeln('  }');
    buffer.writeln(
      r"  throw StateError('$typeName payload must decode to Map<String, Object?>, got ${value.runtimeType}.');",
    );
    buffer.writeln('}');
    buffer.writeln();

    buffer.writeln('abstract final class StemPayloadCodecs {');
    for (final entry in payloadCodecSymbols.entries) {
      final typeCode = entry.key;
      final symbol = entry.value;
      buffer.writeln('  static final PayloadCodec<$typeCode> $symbol =');
      buffer.writeln('      PayloadCodec<$typeCode>(');
      buffer.writeln('        encode: (value) => value.toJson(),');
      buffer.writeln(
        '        decode: (payload) => $typeCode.fromJson('
        '          _stemPayloadMap(payload, ${_string(typeCode)}),'
        '        ),',
      );
      buffer.writeln('      );');
    }
    buffer.writeln('}');
    buffer.writeln();
  }

  void _emitWorkflows(StringBuffer buffer) {
    buffer.writeln('final List<Flow> _stemFlows = <Flow>[');
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
      if (workflow.resultPayloadCodecTypeCode != null) {
        final codecField =
            payloadCodecSymbols[workflow.resultPayloadCodecTypeCode]!;
        buffer.writeln('    resultCodec: StemPayloadCodecs.$codecField,');
      }
      buffer.writeln('    build: (flow) {');
      buffer.writeln(
        '      final impl = ${_qualify(workflow.importAlias, workflow.className)}();',
      );
      for (final step in workflow.steps) {
        final stepArgs = step.valueParameters
            .map((param) => _decodeArg('ctx.params', param))
            .toList(growable: false);
        final invocationArgs = _invocationArgs(
          positional: [
            if (step.acceptsFlowContext && !step.flowContextIsNamed) 'ctx',
            ...stepArgs,
          ],
          named: {
            if (step.acceptsFlowContext && step.flowContextIsNamed)
              step.flowContextParameterName!: 'ctx',
          },
        );
        buffer.writeln('      flow.step<${step.stepValueTypeCode}>(');
        buffer.writeln('        ${_string(step.name)},');
        buffer.writeln(
          '        (ctx) => impl.${step.method}($invocationArgs),',
        );
        if (step.autoVersion) {
          buffer.writeln('        autoVersion: true,');
        }
        if (step.stepValuePayloadCodecTypeCode != null) {
          final codecField =
              payloadCodecSymbols[step.stepValuePayloadCodecTypeCode]!;
          buffer.writeln('        valueCodec: StemPayloadCodecs.$codecField,');
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
        final signature = _methodSignature(
          positional: [
            if (step.acceptsScriptStepContext && !step.scriptStepContextIsNamed)
              'WorkflowScriptStepContext ${step.scriptStepContextParameterName!}',
            ...step.valueParameters.map(
              (parameter) => '${parameter.typeCode} ${parameter.name}',
            ),
          ],
          named: [
            if (step.acceptsScriptStepContext && step.scriptStepContextIsNamed)
              'WorkflowScriptStepContext? ${step.scriptStepContextParameterName!}',
          ],
        );
        final invocationArgs = _invocationArgs(
          positional: [
            if (step.acceptsScriptStepContext && !step.scriptStepContextIsNamed)
              'context',
            ...step.valueParameters.map((parameter) => parameter.name),
          ],
          named: {
            if (step.acceptsScriptStepContext && step.scriptStepContextIsNamed)
              step.scriptStepContextParameterName!: 'context',
          },
        );
        buffer.writeln('  @override');
        buffer.writeln(
          '  ${step.returnTypeCode} ${step.method}($signature) {',
        );
        buffer.writeln('    return _script.step<${step.stepValueTypeCode}>(');
        buffer.writeln('      ${_string(step.name)},');
        buffer.writeln(
          '      (context) => super.${step.method}($invocationArgs),',
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
      'final List<WorkflowScript> _stemScripts = <WorkflowScript>[',
    );
    for (final workflow in scriptWorkflows) {
      final proxyClass = scriptProxyClassNames[workflow];
      buffer.writeln('  WorkflowScript(');
      buffer.writeln('    name: ${_string(workflow.name)},');
      if (workflow.steps.isNotEmpty) {
        buffer.writeln('    checkpoints: [');
        for (final step in workflow.steps) {
          if (step.stepValuePayloadCodecTypeCode != null) {
            buffer.writeln(
              '      WorkflowCheckpoint.typed<${step.stepValueTypeCode}>(',
            );
          } else {
            buffer.writeln('      WorkflowCheckpoint(');
          }
          buffer.writeln('        name: ${_string(step.name)},');
          if (step.autoVersion) {
            buffer.writeln('        autoVersion: true,');
          }
          if (step.stepValuePayloadCodecTypeCode != null) {
            final codecField =
                payloadCodecSymbols[step.stepValuePayloadCodecTypeCode]!;
            buffer.writeln(
              '        valueCodec: StemPayloadCodecs.$codecField,',
            );
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
      if (workflow.resultPayloadCodecTypeCode != null) {
        final codecField =
            payloadCodecSymbols[workflow.resultPayloadCodecTypeCode]!;
        buffer.writeln('    resultCodec: StemPayloadCodecs.$codecField,');
      }
      if (proxyClass != null) {
        final runArgs = _invocationArgs(
          positional: [
            if (workflow.runContextParameterName != null &&
                !workflow.runContextIsNamed)
              'script',
            ...workflow.runValueParameters.map(
              (parameter) => _decodeArg('script.params', parameter),
            ),
          ],
          named: {
            if (workflow.runContextParameterName != null &&
                workflow.runContextIsNamed)
              workflow.runContextParameterName!: 'script',
          },
        );
        buffer.writeln(
          '    run: (script) => $proxyClass(script).${workflow.runMethod}($runArgs),',
        );
      } else {
        final runArgs = _invocationArgs(
          positional: [
            if (workflow.runContextParameterName != null &&
                !workflow.runContextIsNamed)
              'script',
            ...workflow.runValueParameters.map(
              (parameter) => _decodeArg('script.params', parameter),
            ),
          ],
          named: {
            if (workflow.runContextParameterName != null &&
                workflow.runContextIsNamed)
              workflow.runContextParameterName!: 'script',
          },
        );
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
    final fieldNames = _fieldNamesForWorkflows(
      workflows,
      symbolNames,
    );

    buffer.writeln('abstract final class StemWorkflowDefinitions {');
    for (final workflow in workflows) {
      final fieldName = fieldNames[workflow]!;
      final helperSuffix = symbolNames[workflow]!;
      final argsTypeCode = _workflowArgsTypeCode(workflow);
      final isNoArgsScript =
          workflow.kind == WorkflowKind.script &&
          workflow.runValueParameters.isEmpty;
      final refType =
          isNoArgsScript
              ? 'NoArgsWorkflowRef<${workflow.resultTypeCode}>'
              : 'WorkflowRef<$argsTypeCode, ${workflow.resultTypeCode}>';
      final constructorType =
          isNoArgsScript
              ? 'NoArgsWorkflowRef<${workflow.resultTypeCode}>'
              : 'WorkflowRef<$argsTypeCode, ${workflow.resultTypeCode}>';
      buffer.writeln('  static final $refType $fieldName = $constructorType(');
      buffer.writeln('    name: ${_string(workflow.name)},');
      if (workflow.kind == WorkflowKind.script) {
        if (workflow.runValueParameters.isNotEmpty) {
          buffer.writeln('    encodeParams: (params) => <String, Object?>{');
          for (final parameter in workflow.runValueParameters) {
            buffer.writeln(
              '      ${_string(parameter.name)}: '
              '${_encodeValueExpression('params.${parameter.name}', parameter)},',
            );
          }
          buffer.writeln('    },');
        }
      } else {
        buffer.writeln('    encodeParams: (params) => params,');
      }
      if (workflow.resultPayloadCodecTypeCode != null) {
        final codecField =
            payloadCodecSymbols[workflow.resultPayloadCodecTypeCode]!;
        buffer.writeln(
          '    decodeResult: StemPayloadCodecs.$codecField.decode,',
        );
      }
      buffer.writeln('  );');
      if (isNoArgsScript) {
        final startArgs = _methodSignature(
          positional: ['WorkflowCaller caller'],
          named: [
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
          ],
        );
        buffer.writeln(
          '  static Future<String> start$helperSuffix($startArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.startWith(caller, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy);',
        );
        buffer.writeln('  }');
        final startWithContextArgs = _methodSignature(
          positional: ['WorkflowChildCallerContext context'],
          named: [
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
          ],
        );
        buffer.writeln(
          '  static Future<String> start$helperSuffix'
          'WithContext($startWithContextArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.startWithContext(context, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy);',
        );
        buffer.writeln('  }');
        final startAndWaitArgs = _methodSignature(
          positional: ['WorkflowCaller caller'],
          named: [
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
            'Duration pollInterval = const Duration(milliseconds: 100)',
            'Duration? timeout',
          ],
        );
        buffer.writeln(
          '  static Future<WorkflowResult<${workflow.resultTypeCode}>?> startAndWait$helperSuffix($startAndWaitArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.startAndWaitWith(caller, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy, pollInterval: pollInterval, timeout: timeout);',
        );
        buffer.writeln('  }');
        final startAndWaitWithContextArgs = _methodSignature(
          positional: ['WorkflowChildCallerContext context'],
          named: [
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
            'Duration pollInterval = const Duration(milliseconds: 100)',
            'Duration? timeout',
          ],
        );
        buffer.writeln(
          '  static Future<WorkflowResult<${workflow.resultTypeCode}>?> startAndWait$helperSuffix'
          'WithContext($startAndWaitWithContextArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.startAndWaitWithContext(context, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy, pollInterval: pollInterval, timeout: timeout);',
        );
        buffer.writeln('  }');
      } else {
        final parameters = workflow.kind == WorkflowKind.script
            ? workflow.runValueParameters
            : workflow.steps.first.valueParameters;
        final callParams = workflow.kind == WorkflowKind.script
            ? '(${parameters.map((parameter) => '${parameter.name}: ${parameter.name}').join(', ')})'
            : '<String, Object?>{${parameters.map((parameter) => '${_string(parameter.name)}: ${_encodeValueExpression(parameter.name, parameter)}').join(', ')}}';
        final startArgs = _methodSignature(
          positional: ['WorkflowCaller caller'],
          named: [
            ...parameters.map(
              (parameter) => 'required ${parameter.typeCode} ${parameter.name}',
            ),
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
          ],
        );
        buffer.writeln(
          '  static Future<String> start$helperSuffix($startArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.call($callParams, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy).startWith(caller);',
        );
        buffer.writeln('  }');
        final startWithContextArgs = _methodSignature(
          positional: ['WorkflowChildCallerContext context'],
          named: [
            ...parameters.map(
              (parameter) => 'required ${parameter.typeCode} ${parameter.name}',
            ),
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
          ],
        );
        buffer.writeln(
          '  static Future<String> start$helperSuffix'
          'WithContext($startWithContextArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.call($callParams, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy).startWithContext(context);',
        );
        buffer.writeln('  }');
        final startAndWaitArgs = _methodSignature(
          positional: ['WorkflowCaller caller'],
          named: [
            ...parameters.map(
              (parameter) => 'required ${parameter.typeCode} ${parameter.name}',
            ),
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
            'Duration pollInterval = const Duration(milliseconds: 100)',
            'Duration? timeout',
          ],
        );
        buffer.writeln(
          '  static Future<WorkflowResult<${workflow.resultTypeCode}>?> startAndWait$helperSuffix($startAndWaitArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.call($callParams, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy).startAndWaitWith(caller, pollInterval: pollInterval, timeout: timeout);',
        );
        buffer.writeln('  }');
        final startAndWaitWithContextArgs = _methodSignature(
          positional: ['WorkflowChildCallerContext context'],
          named: [
            ...parameters.map(
              (parameter) => 'required ${parameter.typeCode} ${parameter.name}',
            ),
            'String? parentRunId',
            'Duration? ttl',
            'WorkflowCancellationPolicy? cancellationPolicy',
            'Duration pollInterval = const Duration(milliseconds: 100)',
            'Duration? timeout',
          ],
        );
        buffer.writeln(
          '  static Future<WorkflowResult<${workflow.resultTypeCode}>?> startAndWait$helperSuffix'
          'WithContext($startAndWaitWithContextArgs) {',
        );
        buffer.writeln(
          '    return $fieldName.call($callParams, parentRunId: parentRunId, ttl: ttl, cancellationPolicy: cancellationPolicy).startAndWaitWithContext(context, pollInterval: pollInterval, timeout: timeout);',
        );
        buffer.writeln('  }');
      }
      buffer.writeln(
        '  static Future<WorkflowResult<${workflow.resultTypeCode}>?> waitFor$helperSuffix('
        '${_methodSignature(positional: ['WorkflowCaller caller', 'String runId'], named: ['Duration pollInterval = const Duration(milliseconds: 100)', 'Duration? timeout'])}) {',
      );
      buffer.writeln(
        '    return $fieldName.waitForWith(caller, runId, pollInterval: pollInterval, timeout: timeout);',
      );
      buffer.writeln('  }');
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
      final candidates = _workflowSymbolCandidates(
        workflowName: workflow.name,
        starterNameOverride: workflow.starterNameOverride,
      );
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

  Map<_WorkflowInfo, String> _fieldNamesForWorkflows(
    List<_WorkflowInfo> values,
    Map<_WorkflowInfo, String> symbolNames,
  ) {
    final result = <_WorkflowInfo, String>{};
    final used = <String>{};
    for (final workflow in values) {
      final candidateList = <String>[
        if (workflow.nameFieldOverride != null &&
            workflow.nameFieldOverride!.trim().isNotEmpty)
          _lowerCamelIdentifier(workflow.nameFieldOverride!),
        _lowerCamel(symbolNames[workflow]!),
      ];
      var chosen = candidateList.firstWhere(
        (candidate) => candidate.isNotEmpty && !used.contains(candidate),
        orElse: () => candidateList.last,
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

  Map<_TaskInfo, String> _symbolNamesForTasks(List<_TaskInfo> values) {
    final result = <_TaskInfo, String>{};
    final used = <String>{};
    for (final task in values) {
      final candidates = _taskSymbolCandidates(task);
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
      result[task] = chosen;
    }
    return result;
  }

  List<String> _taskSymbolCandidates(_TaskInfo task) {
    final byName = task.name
        .split('.')
        .map(_pascalIdentifier)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (byName.isNotEmpty) {
      return [
        byName.join(),
        _pascalIdentifier(task.function),
      ];
    }
    return [_pascalIdentifier(task.function)];
  }

  List<String> _workflowSymbolCandidates({
    required String workflowName,
    String? starterNameOverride,
  }) {
    if (starterNameOverride != null && starterNameOverride.trim().isNotEmpty) {
      final override = _starterSuffix(starterNameOverride);
      if (override.isNotEmpty) {
        return [override];
      }
    }
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

  String _starterSuffix(String value) {
    final trimmed = value.trim();
    final match = RegExp(
      '^start(?=[A-Z0-9_])',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final stripped = match == null ? trimmed : trimmed.substring(match.end);
    return _pascalIdentifier(stripped);
  }

  String _pascalIdentifier(String value) {
    return _pascalIdentifierStatic(value);
  }

  static String _pascalIdentifierStatic(String value) {
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
    return _lowerCamelStatic(value);
  }

  static String _lowerCamelStatic(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toLowerCase()}${value.substring(1)}';
  }

  String _lowerCamelIdentifier(String value) {
    final pascal = _pascalIdentifier(value);
    return _lowerCamel(pascal);
  }

  String _invocationArgs({
    List<String> positional = const [],
    Map<String, String> named = const {},
  }) {
    final parts = <String>[
      ...positional.where((part) => part.isNotEmpty),
      ...named.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}: ${entry.value}'),
    ];
    return parts.join(', ');
  }

  String _methodSignature({
    List<String> positional = const [],
    List<String> named = const [],
  }) {
    final parts = <String>[
      ...positional.where((part) => part.isNotEmpty),
    ];
    if (named.isNotEmpty) {
      parts.add('{${named.join(', ')}}');
    }
    return parts.join(', ');
  }

  void _emitTasks(StringBuffer buffer) {
    buffer.writeln(
      'final List<TaskHandler<Object?>> _stemTasks = <TaskHandler<Object?>>[',
    );
    for (final task in tasks) {
      final entrypoint = task.adapterName ?? _qualify(task.importAlias, task.function);
      final metadataCode = _taskMetadataCode(task);
      buffer.writeln('  FunctionTaskHandler<Object?>(');
      buffer.writeln('    name: ${_string(task.name)},');
      buffer.writeln('    entrypoint: $entrypoint,');
      if (task.options != null) {
        buffer.writeln('    options: ${_dartObjectToCode(task.options!)},');
      }
      if (metadataCode != null) {
        buffer.writeln('    metadata: $metadataCode,');
      }
      if (!task.runInIsolate) {
        buffer.writeln('    runInIsolate: false,');
      }
      buffer.writeln('  ),');
    }
    buffer.writeln('];');
    buffer.writeln();
  }

  void _emitTaskDefinitions(StringBuffer buffer) {
    if (tasks.isEmpty) {
      return;
    }
    final symbolNames = _symbolNamesForTasks(tasks);
    buffer.writeln('abstract final class StemTaskDefinitions {');
    for (final task in tasks) {
      final symbol = _lowerCamel(symbolNames[task]!);
      final argsTypeCode = _taskArgsTypeCode(task);
      final usesNoArgsDefinition =
          !task.usesLegacyMapArgs && task.valueParameters.isEmpty;
      if (usesNoArgsDefinition) {
        buffer.writeln(
          '  static final NoArgsTaskDefinition<${task.resultTypeCode}> $symbol = NoArgsTaskDefinition<${task.resultTypeCode}>(',
        );
      } else {
        buffer.writeln(
          '  static final TaskDefinition<$argsTypeCode, ${task.resultTypeCode}> $symbol = TaskDefinition<$argsTypeCode, ${task.resultTypeCode}>(',
        );
      }
      buffer.writeln('    name: ${_string(task.name)},');
      if (task.usesLegacyMapArgs) {
        buffer.writeln('    encodeArgs: (args) => args,');
      } else if (task.valueParameters.isNotEmpty) {
        buffer.writeln('    encodeArgs: (args) => <String, Object?>{');
        for (final parameter in task.valueParameters) {
          buffer.writeln(
            '      ${_string(parameter.name)}: '
            '${_encodeValueExpression('args.${parameter.name}', parameter)},',
          );
        }
        buffer.writeln('    },');
      }
      if (task.options != null) {
        buffer.writeln('    defaultOptions: ${_dartObjectToCode(task.options!)},');
      }
      if (task.metadata != null) {
        buffer.writeln('    metadata: ${_dartObjectToCode(task.metadata!)},');
      }
      if (task.resultPayloadCodecTypeCode != null) {
        final codecField =
            payloadCodecSymbols[task.resultPayloadCodecTypeCode]!;
        buffer.writeln(
          '    decodeResult: StemPayloadCodecs.$codecField.decode,',
        );
      }
      buffer.writeln('  );');
      if (!task.usesLegacyMapArgs) {
        final helperSuffix = _pascalIdentifier(symbol);
        final businessArgs = _methodSignature(
          positional: ['TaskEnqueuer enqueuer'],
          named: [
            ...task.valueParameters.map(
              (parameter) => 'required ${parameter.typeCode} ${parameter.name}',
            ),
            'Map<String, String> headers = const {}',
            'TaskOptions? options',
            'DateTime? notBefore',
            'Map<String, Object?>? meta',
            'TaskEnqueueOptions? enqueueOptions',
          ],
        );
        if (usesNoArgsDefinition) {
          buffer.writeln(
            '  static Future<String> enqueue$helperSuffix($businessArgs) {',
          );
          buffer.writeln(
            '    return $symbol.enqueueWith(enqueuer, headers: headers, options: options, notBefore: notBefore, meta: meta, enqueueOptions: enqueueOptions);',
          );
        } else {
          final callArgs = _invocationArgs(
            positional: [
              '(${task.valueParameters.map((parameter) => '${parameter.name}: ${parameter.name}').join(', ')})',
            ],
            named: {
              'headers': 'headers',
              'options': 'options',
              'notBefore': 'notBefore',
              'meta': 'meta',
              'enqueueOptions': 'enqueueOptions',
            },
          );
          buffer.writeln(
            '  static Future<String> enqueue$helperSuffix($businessArgs) {',
          );
          buffer.writeln(
            '    return $symbol.call($callArgs).enqueueWith(enqueuer, enqueueOptions: enqueueOptions);',
          );
        }
        buffer.writeln('  }');
        final waitArgs = _methodSignature(
          positional: ['Stem stem'],
          named: [
            ...task.valueParameters.map(
              (parameter) => 'required ${parameter.typeCode} ${parameter.name}',
            ),
            'Map<String, String> headers = const {}',
            'TaskOptions? options',
            'DateTime? notBefore',
            'Map<String, Object?>? meta',
            'TaskEnqueueOptions? enqueueOptions',
            'Duration? timeout',
          ],
        );
        buffer.writeln(
          '  static Future<TaskResult<${task.resultTypeCode}>?> enqueueAndWait$helperSuffix($waitArgs) async {',
        );
        buffer.writeln('    final taskId = await enqueue$helperSuffix(');
        buffer.writeln('      stem,');
        for (final parameter in task.valueParameters) {
          buffer.writeln('      ${parameter.name}: ${parameter.name},');
        }
        buffer.writeln('      headers: headers,');
        buffer.writeln('      options: options,');
        buffer.writeln('      notBefore: notBefore,');
        buffer.writeln('      meta: meta,');
        buffer.writeln('      enqueueOptions: enqueueOptions,');
        buffer.writeln('    );');
        buffer.writeln(
          '    return $symbol.waitFor(stem, taskId, timeout: timeout);',
        );
        buffer.writeln('  }');
      }
    }
    buffer.writeln('}');
    buffer.writeln();
  }

  void _emitTaskAdapters(StringBuffer buffer) {
    final adaptedTasks = tasks
        .where((task) => task.adapterName != null)
        .toList(growable: false);
    if (adaptedTasks.isEmpty) {
      return;
    }
    for (final task in adaptedTasks) {
      final adapterName = task.adapterName!;
      final callArgs = _invocationArgs(
        positional: [
          if (task.acceptsTaskContext && !task.taskContextIsNamed) 'context',
          if (task.usesLegacyMapArgs)
            'args'
          else
          ...task.valueParameters.map((param) => _decodeArg('args', param)),
        ],
        named: {
          if (task.acceptsTaskContext && task.taskContextIsNamed)
            task.taskContextParameterName!: 'context',
        },
      );
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
      'final List<WorkflowManifestEntry> _stemWorkflowManifest = <WorkflowManifestEntry>[',
    );
    buffer.writeln(
      '  ..._stemFlows.map((flow) => flow.definition.toManifestEntry()),',
    );
    buffer.writeln(
      '  ..._stemScripts.map((script) => script.definition.toManifestEntry()),',
    );
    buffer.writeln('];');
    buffer.writeln();
  }

  void _emitModule(StringBuffer buffer) {
    buffer.writeln('final StemModule stemModule = StemModule(');
    buffer.writeln('  flows: _stemFlows,');
    buffer.writeln('  scripts: _stemScripts,');
    buffer.writeln('  tasks: _stemTasks,');
    buffer.writeln('  workflowManifest: _stemWorkflowManifest,');
    buffer.writeln(');');
    buffer.writeln();
  }

  String? _taskMetadataCode(_TaskInfo task) {
    final resultCodecTypeCode = task.resultPayloadCodecTypeCode;
    if (task.metadata == null && resultCodecTypeCode == null) {
      return null;
    }
    if (resultCodecTypeCode == null) {
      return _dartObjectToCode(task.metadata!);
    }
    final codecField = payloadCodecSymbols[resultCodecTypeCode]!;
    final metadata = task.metadata;
    if (metadata == null) {
      return [
        'TaskMetadata(',
        'resultEncoder: CodecTaskPayloadEncoder<${task.resultTypeCode}>(',
        'idValue: ${_string('stem.generated.${task.name}.result')}, ',
        'codec: StemPayloadCodecs.$codecField, ',
        '), ',
        ')',
      ].join();
    }
    final reader = ConstantReader(metadata);
    final fields = <String>[];
    final description = StemRegistryBuilder._stringOrNull(
      reader.peek('description'),
    );
    if (description != null) {
      fields.add('description: ${_string(description)}');
    }
    final tags = StemRegistryBuilder._objectOrNull(reader.peek('tags'));
    if (tags != null) {
      fields.add('tags: ${_dartObjectToCode(tags)}');
    }
    final idempotentReader = reader.peek('idempotent');
    if (idempotentReader != null && !idempotentReader.isNull) {
      fields.add('idempotent: ${idempotentReader.boolValue}');
    }
    final attributes = StemRegistryBuilder._objectOrNull(
      reader.peek('attributes'),
    );
    if (attributes != null) {
      fields.add('attributes: ${_dartObjectToCode(attributes)}');
    }
    final argsEncoder = StemRegistryBuilder._objectOrNull(
      reader.peek('argsEncoder'),
    );
    if (argsEncoder != null) {
      fields.add('argsEncoder: ${_dartObjectToCode(argsEncoder)}');
    }
    fields.add(
      [
        'resultEncoder: CodecTaskPayloadEncoder<${task.resultTypeCode}>(',
        'idValue: ${_string('stem.generated.${task.name}.result')}, ',
        'codec: StemPayloadCodecs.$codecField, ',
        ')',
      ].join(),
    );
    return 'TaskMetadata(${fields.join(', ')})';
  }

  String _decodeArg(String sourceMap, _ValueParameterInfo parameter) {
    final codecTypeCode = parameter.payloadCodecTypeCode;
    if (codecTypeCode != null) {
      final codecField = payloadCodecSymbols[codecTypeCode]!;
      return [
        'StemPayloadCodecs.$codecField.decode(',
        '_stemRequireArg($sourceMap, ${_string(parameter.name)}),',
        ')',
      ].join();
    }
    return '(_stemRequireArg($sourceMap, ${_string(parameter.name)}) '
        'as ${parameter.typeCode})';
  }

  String _encodeValueExpression(String expression, _ValueParameterInfo parameter) {
    final codecTypeCode = parameter.payloadCodecTypeCode;
    if (codecTypeCode == null) {
      return expression;
    }
    final codecField = payloadCodecSymbols[codecTypeCode]!;
    return 'StemPayloadCodecs.$codecField.encode($expression)';
  }

  String _taskArgsTypeCode(
    _TaskInfo task,
  ) {
    if (task.usesLegacyMapArgs) {
      return 'Map<String, Object?>';
    }
    if (task.valueParameters.isEmpty) {
      return '()';
    }
    final fields = task.valueParameters
        .map((parameter) => '${parameter.typeCode} ${parameter.name}')
        .join(', ');
    return '({$fields})';
  }

  String _workflowArgsTypeCode(_WorkflowInfo workflow) {
    if (workflow.kind != WorkflowKind.script) {
      return 'Map<String, Object?>';
    }
    if (workflow.runValueParameters.isEmpty) {
      return '()';
    }
    final fields = workflow.runValueParameters
        .map((parameter) => '${parameter.typeCode} ${parameter.name}')
        .join(', ');
    return '({$fields})';
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
