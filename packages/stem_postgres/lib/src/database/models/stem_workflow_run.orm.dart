// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_workflow_run.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemWorkflowRunIdField = FieldDefinition(
  name: 'id',
  columnName: 'id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
);

const FieldDefinition _$StemWorkflowRunWorkflowField = FieldDefinition(
  name: 'workflow',
  columnName: 'workflow',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemWorkflowRunStatusField = FieldDefinition(
  name: 'status',
  columnName: 'status',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemWorkflowRunParamsField = FieldDefinition(
  name: 'params',
  columnName: 'params',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemWorkflowRunResultField = FieldDefinition(
  name: 'result',
  columnName: 'result',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemWorkflowRunWaitTopicField = FieldDefinition(
  name: 'waitTopic',
  columnName: 'wait_topic',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemWorkflowRunResumeAtField = FieldDefinition(
  name: 'resumeAt',
  columnName: 'resume_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemWorkflowRunLastErrorField = FieldDefinition(
  name: 'lastError',
  columnName: 'last_error',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemWorkflowRunSuspensionDataField = FieldDefinition(
  name: 'suspensionData',
  columnName: 'suspension_data',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemWorkflowRunCancellationPolicyField =
    FieldDefinition(
      name: 'cancellationPolicy',
      columnName: 'cancellation_policy',
      dartType: 'String',
      resolvedType: 'String?',
      isNullable: true,
    );

const FieldDefinition _$StemWorkflowRunCancellationDataField = FieldDefinition(
  name: 'cancellationData',
  columnName: 'cancellation_data',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemWorkflowRunCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

const FieldDefinition _$StemWorkflowRunUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

Map<String, Object?> _encodeStemWorkflowRunUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemWorkflowRun;
  return <String, Object?>{
    'id': registry.encodeField(_$StemWorkflowRunIdField, m.id),
    'workflow': registry.encodeField(
      _$StemWorkflowRunWorkflowField,
      m.workflow,
    ),
    'status': registry.encodeField(_$StemWorkflowRunStatusField, m.status),
    'params': registry.encodeField(_$StemWorkflowRunParamsField, m.params),
    'result': registry.encodeField(_$StemWorkflowRunResultField, m.result),
    'wait_topic': registry.encodeField(
      _$StemWorkflowRunWaitTopicField,
      m.waitTopic,
    ),
    'resume_at': registry.encodeField(
      _$StemWorkflowRunResumeAtField,
      m.resumeAt,
    ),
    'last_error': registry.encodeField(
      _$StemWorkflowRunLastErrorField,
      m.lastError,
    ),
    'suspension_data': registry.encodeField(
      _$StemWorkflowRunSuspensionDataField,
      m.suspensionData,
    ),
    'cancellation_policy': registry.encodeField(
      _$StemWorkflowRunCancellationPolicyField,
      m.cancellationPolicy,
    ),
    'cancellation_data': registry.encodeField(
      _$StemWorkflowRunCancellationDataField,
      m.cancellationData,
    ),
    'created_at': registry.encodeField(
      _$StemWorkflowRunCreatedAtField,
      m.createdAt,
    ),
    'updated_at': registry.encodeField(
      _$StemWorkflowRunUpdatedAtField,
      m.updatedAt,
    ),
  };
}

const ModelDefinition<$StemWorkflowRun> _$StemWorkflowRunDefinition =
    ModelDefinition(
      modelName: 'StemWorkflowRun',
      tableName: 'stem_workflow_runs',
      fields: [
        _$StemWorkflowRunIdField,
        _$StemWorkflowRunWorkflowField,
        _$StemWorkflowRunStatusField,
        _$StemWorkflowRunParamsField,
        _$StemWorkflowRunResultField,
        _$StemWorkflowRunWaitTopicField,
        _$StemWorkflowRunResumeAtField,
        _$StemWorkflowRunLastErrorField,
        _$StemWorkflowRunSuspensionDataField,
        _$StemWorkflowRunCancellationPolicyField,
        _$StemWorkflowRunCancellationDataField,
        _$StemWorkflowRunCreatedAtField,
        _$StemWorkflowRunUpdatedAtField,
      ],
      softDeleteColumn: 'deleted_at',
      untrackedToMap: _encodeStemWorkflowRunUntracked,
      codec: _$StemWorkflowRunCodec(),
    );

extension StemWorkflowRunOrmDefinition on StemWorkflowRun {
  static ModelDefinition<$StemWorkflowRun> get definition =>
      _$StemWorkflowRunDefinition;
}

class StemWorkflowRuns {
  const StemWorkflowRuns._();

  /// Starts building a query for [$StemWorkflowRun].
  ///
  /// {@macro ormed.query}
  static Query<$StemWorkflowRun> query([String? connection]) =>
      Model.query<$StemWorkflowRun>(connection: connection);

  static Future<$StemWorkflowRun?> find(Object id, {String? connection}) =>
      Model.find<$StemWorkflowRun>(id, connection: connection);

  static Future<$StemWorkflowRun> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemWorkflowRun>(id, connection: connection);

  static Future<List<$StemWorkflowRun>> all({String? connection}) =>
      Model.all<$StemWorkflowRun>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemWorkflowRun>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemWorkflowRun>(connection: connection);

  static Query<$StemWorkflowRun> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemWorkflowRun>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemWorkflowRun> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemWorkflowRun>(column, values, connection: connection);

  static Query<$StemWorkflowRun> orderBy(
    String column, {
    String direction = 'asc',
    String? connection,
  }) => Model.orderBy<$StemWorkflowRun>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemWorkflowRun> limit(int count, {String? connection}) =>
      Model.limit<$StemWorkflowRun>(count, connection: connection);

  /// Creates a [Repository] for [$StemWorkflowRun].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemWorkflowRun> repo([String? connection]) =>
      Model.repository<$StemWorkflowRun>(connection: connection);
}

class StemWorkflowRunModelFactory {
  const StemWorkflowRunModelFactory._();

  static ModelDefinition<$StemWorkflowRun> get definition =>
      _$StemWorkflowRunDefinition;

  static ModelCodec<$StemWorkflowRun> get codec => definition.codec;

  static StemWorkflowRun fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemWorkflowRun model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemWorkflowRun> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemWorkflowRun>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemWorkflowRun> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemWorkflowRun>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemWorkflowRunCodec extends ModelCodec<$StemWorkflowRun> {
  const _$StemWorkflowRunCodec();
  @override
  Map<String, Object?> encode(
    $StemWorkflowRun model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemWorkflowRunIdField, model.id),
      'workflow': registry.encodeField(
        _$StemWorkflowRunWorkflowField,
        model.workflow,
      ),
      'status': registry.encodeField(
        _$StemWorkflowRunStatusField,
        model.status,
      ),
      'params': registry.encodeField(
        _$StemWorkflowRunParamsField,
        model.params,
      ),
      'result': registry.encodeField(
        _$StemWorkflowRunResultField,
        model.result,
      ),
      'wait_topic': registry.encodeField(
        _$StemWorkflowRunWaitTopicField,
        model.waitTopic,
      ),
      'resume_at': registry.encodeField(
        _$StemWorkflowRunResumeAtField,
        model.resumeAt,
      ),
      'last_error': registry.encodeField(
        _$StemWorkflowRunLastErrorField,
        model.lastError,
      ),
      'suspension_data': registry.encodeField(
        _$StemWorkflowRunSuspensionDataField,
        model.suspensionData,
      ),
      'cancellation_policy': registry.encodeField(
        _$StemWorkflowRunCancellationPolicyField,
        model.cancellationPolicy,
      ),
      'cancellation_data': registry.encodeField(
        _$StemWorkflowRunCancellationDataField,
        model.cancellationData,
      ),
      'created_at': registry.encodeField(
        _$StemWorkflowRunCreatedAtField,
        model.createdAt,
      ),
      'updated_at': registry.encodeField(
        _$StemWorkflowRunUpdatedAtField,
        model.updatedAt,
      ),
    };
  }

  @override
  $StemWorkflowRun decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final stemWorkflowRunIdValue =
        registry.decodeField<String>(_$StemWorkflowRunIdField, data['id']) ??
        (throw StateError('Field id on StemWorkflowRun cannot be null.'));
    final stemWorkflowRunWorkflowValue =
        registry.decodeField<String>(
          _$StemWorkflowRunWorkflowField,
          data['workflow'],
        ) ??
        (throw StateError('Field workflow on StemWorkflowRun cannot be null.'));
    final stemWorkflowRunStatusValue =
        registry.decodeField<String>(
          _$StemWorkflowRunStatusField,
          data['status'],
        ) ??
        (throw StateError('Field status on StemWorkflowRun cannot be null.'));
    final stemWorkflowRunParamsValue =
        registry.decodeField<String>(
          _$StemWorkflowRunParamsField,
          data['params'],
        ) ??
        (throw StateError('Field params on StemWorkflowRun cannot be null.'));
    final stemWorkflowRunResultValue = registry.decodeField<String?>(
      _$StemWorkflowRunResultField,
      data['result'],
    );
    final stemWorkflowRunWaitTopicValue = registry.decodeField<String?>(
      _$StemWorkflowRunWaitTopicField,
      data['wait_topic'],
    );
    final stemWorkflowRunResumeAtValue = registry.decodeField<DateTime?>(
      _$StemWorkflowRunResumeAtField,
      data['resume_at'],
    );
    final stemWorkflowRunLastErrorValue = registry.decodeField<String?>(
      _$StemWorkflowRunLastErrorField,
      data['last_error'],
    );
    final stemWorkflowRunSuspensionDataValue = registry.decodeField<String?>(
      _$StemWorkflowRunSuspensionDataField,
      data['suspension_data'],
    );
    final stemWorkflowRunCancellationPolicyValue = registry
        .decodeField<String?>(
          _$StemWorkflowRunCancellationPolicyField,
          data['cancellation_policy'],
        );
    final stemWorkflowRunCancellationDataValue = registry.decodeField<String?>(
      _$StemWorkflowRunCancellationDataField,
      data['cancellation_data'],
    );
    final stemWorkflowRunCreatedAtValue =
        registry.decodeField<DateTime>(
          _$StemWorkflowRunCreatedAtField,
          data['created_at'],
        ) ??
        (throw StateError(
          'Field createdAt on StemWorkflowRun cannot be null.',
        ));
    final stemWorkflowRunUpdatedAtValue =
        registry.decodeField<DateTime>(
          _$StemWorkflowRunUpdatedAtField,
          data['updated_at'],
        ) ??
        (throw StateError(
          'Field updatedAt on StemWorkflowRun cannot be null.',
        ));
    final model = $StemWorkflowRun(
      id: stemWorkflowRunIdValue,
      workflow: stemWorkflowRunWorkflowValue,
      status: stemWorkflowRunStatusValue,
      params: stemWorkflowRunParamsValue,
      result: stemWorkflowRunResultValue,
      waitTopic: stemWorkflowRunWaitTopicValue,
      resumeAt: stemWorkflowRunResumeAtValue,
      lastError: stemWorkflowRunLastErrorValue,
      suspensionData: stemWorkflowRunSuspensionDataValue,
      cancellationPolicy: stemWorkflowRunCancellationPolicyValue,
      cancellationData: stemWorkflowRunCancellationDataValue,
      createdAt: stemWorkflowRunCreatedAtValue,
      updatedAt: stemWorkflowRunUpdatedAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemWorkflowRunIdValue,
      'workflow': stemWorkflowRunWorkflowValue,
      'status': stemWorkflowRunStatusValue,
      'params': stemWorkflowRunParamsValue,
      'result': stemWorkflowRunResultValue,
      'wait_topic': stemWorkflowRunWaitTopicValue,
      'resume_at': stemWorkflowRunResumeAtValue,
      'last_error': stemWorkflowRunLastErrorValue,
      'suspension_data': stemWorkflowRunSuspensionDataValue,
      'cancellation_policy': stemWorkflowRunCancellationPolicyValue,
      'cancellation_data': stemWorkflowRunCancellationDataValue,
      'created_at': stemWorkflowRunCreatedAtValue,
      'updated_at': stemWorkflowRunUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemWorkflowRun].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemWorkflowRunInsertDto implements InsertDto<$StemWorkflowRun> {
  const StemWorkflowRunInsertDto({
    this.id,
    this.workflow,
    this.status,
    this.params,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
    this.cancellationPolicy,
    this.cancellationData,
    this.createdAt,
    this.updatedAt,
  });
  final String? id;
  final String? workflow;
  final String? status;
  final String? params;
  final String? result;
  final String? waitTopic;
  final DateTime? resumeAt;
  final String? lastError;
  final String? suspensionData;
  final String? cancellationPolicy;
  final String? cancellationData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (workflow != null) 'workflow': workflow,
      if (status != null) 'status': status,
      if (params != null) 'params': params,
      if (result != null) 'result': result,
      if (waitTopic != null) 'wait_topic': waitTopic,
      if (resumeAt != null) 'resume_at': resumeAt,
      if (lastError != null) 'last_error': lastError,
      if (suspensionData != null) 'suspension_data': suspensionData,
      if (cancellationPolicy != null) 'cancellation_policy': cancellationPolicy,
      if (cancellationData != null) 'cancellation_data': cancellationData,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  static const _StemWorkflowRunInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowRunInsertDtoCopyWithSentinel();
  StemWorkflowRunInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? workflow = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? params = _copyWithSentinel,
    Object? result = _copyWithSentinel,
    Object? waitTopic = _copyWithSentinel,
    Object? resumeAt = _copyWithSentinel,
    Object? lastError = _copyWithSentinel,
    Object? suspensionData = _copyWithSentinel,
    Object? cancellationPolicy = _copyWithSentinel,
    Object? cancellationData = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
  }) {
    return StemWorkflowRunInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      workflow: identical(workflow, _copyWithSentinel)
          ? this.workflow
          : workflow as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
      params: identical(params, _copyWithSentinel)
          ? this.params
          : params as String?,
      result: identical(result, _copyWithSentinel)
          ? this.result
          : result as String?,
      waitTopic: identical(waitTopic, _copyWithSentinel)
          ? this.waitTopic
          : waitTopic as String?,
      resumeAt: identical(resumeAt, _copyWithSentinel)
          ? this.resumeAt
          : resumeAt as DateTime?,
      lastError: identical(lastError, _copyWithSentinel)
          ? this.lastError
          : lastError as String?,
      suspensionData: identical(suspensionData, _copyWithSentinel)
          ? this.suspensionData
          : suspensionData as String?,
      cancellationPolicy: identical(cancellationPolicy, _copyWithSentinel)
          ? this.cancellationPolicy
          : cancellationPolicy as String?,
      cancellationData: identical(cancellationData, _copyWithSentinel)
          ? this.cancellationData
          : cancellationData as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class _StemWorkflowRunInsertDtoCopyWithSentinel {
  const _StemWorkflowRunInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemWorkflowRun].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemWorkflowRunUpdateDto implements UpdateDto<$StemWorkflowRun> {
  const StemWorkflowRunUpdateDto({
    this.id,
    this.workflow,
    this.status,
    this.params,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
    this.cancellationPolicy,
    this.cancellationData,
    this.createdAt,
    this.updatedAt,
  });
  final String? id;
  final String? workflow;
  final String? status;
  final String? params;
  final String? result;
  final String? waitTopic;
  final DateTime? resumeAt;
  final String? lastError;
  final String? suspensionData;
  final String? cancellationPolicy;
  final String? cancellationData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (workflow != null) 'workflow': workflow,
      if (status != null) 'status': status,
      if (params != null) 'params': params,
      if (result != null) 'result': result,
      if (waitTopic != null) 'wait_topic': waitTopic,
      if (resumeAt != null) 'resume_at': resumeAt,
      if (lastError != null) 'last_error': lastError,
      if (suspensionData != null) 'suspension_data': suspensionData,
      if (cancellationPolicy != null) 'cancellation_policy': cancellationPolicy,
      if (cancellationData != null) 'cancellation_data': cancellationData,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  static const _StemWorkflowRunUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowRunUpdateDtoCopyWithSentinel();
  StemWorkflowRunUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? workflow = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? params = _copyWithSentinel,
    Object? result = _copyWithSentinel,
    Object? waitTopic = _copyWithSentinel,
    Object? resumeAt = _copyWithSentinel,
    Object? lastError = _copyWithSentinel,
    Object? suspensionData = _copyWithSentinel,
    Object? cancellationPolicy = _copyWithSentinel,
    Object? cancellationData = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
  }) {
    return StemWorkflowRunUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      workflow: identical(workflow, _copyWithSentinel)
          ? this.workflow
          : workflow as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
      params: identical(params, _copyWithSentinel)
          ? this.params
          : params as String?,
      result: identical(result, _copyWithSentinel)
          ? this.result
          : result as String?,
      waitTopic: identical(waitTopic, _copyWithSentinel)
          ? this.waitTopic
          : waitTopic as String?,
      resumeAt: identical(resumeAt, _copyWithSentinel)
          ? this.resumeAt
          : resumeAt as DateTime?,
      lastError: identical(lastError, _copyWithSentinel)
          ? this.lastError
          : lastError as String?,
      suspensionData: identical(suspensionData, _copyWithSentinel)
          ? this.suspensionData
          : suspensionData as String?,
      cancellationPolicy: identical(cancellationPolicy, _copyWithSentinel)
          ? this.cancellationPolicy
          : cancellationPolicy as String?,
      cancellationData: identical(cancellationData, _copyWithSentinel)
          ? this.cancellationData
          : cancellationData as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class _StemWorkflowRunUpdateDtoCopyWithSentinel {
  const _StemWorkflowRunUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemWorkflowRun].
///
/// All fields are nullable; intended for subset SELECTs.
class StemWorkflowRunPartial implements PartialEntity<$StemWorkflowRun> {
  const StemWorkflowRunPartial({
    this.id,
    this.workflow,
    this.status,
    this.params,
    this.result,
    this.waitTopic,
    this.resumeAt,
    this.lastError,
    this.suspensionData,
    this.cancellationPolicy,
    this.cancellationData,
    this.createdAt,
    this.updatedAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemWorkflowRunPartial.fromRow(Map<String, Object?> row) {
    return StemWorkflowRunPartial(
      id: row['id'] as String?,
      workflow: row['workflow'] as String?,
      status: row['status'] as String?,
      params: row['params'] as String?,
      result: row['result'] as String?,
      waitTopic: row['wait_topic'] as String?,
      resumeAt: row['resume_at'] as DateTime?,
      lastError: row['last_error'] as String?,
      suspensionData: row['suspension_data'] as String?,
      cancellationPolicy: row['cancellation_policy'] as String?,
      cancellationData: row['cancellation_data'] as String?,
      createdAt: row['created_at'] as DateTime?,
      updatedAt: row['updated_at'] as DateTime?,
    );
  }

  final String? id;
  final String? workflow;
  final String? status;
  final String? params;
  final String? result;
  final String? waitTopic;
  final DateTime? resumeAt;
  final String? lastError;
  final String? suspensionData;
  final String? cancellationPolicy;
  final String? cancellationData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  $StemWorkflowRun toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final workflowValue = workflow;
    if (workflowValue == null) {
      throw StateError('Missing required field: workflow');
    }
    final statusValue = status;
    if (statusValue == null) {
      throw StateError('Missing required field: status');
    }
    final paramsValue = params;
    if (paramsValue == null) {
      throw StateError('Missing required field: params');
    }
    final createdAtValue = createdAt;
    if (createdAtValue == null) {
      throw StateError('Missing required field: createdAt');
    }
    final updatedAtValue = updatedAt;
    if (updatedAtValue == null) {
      throw StateError('Missing required field: updatedAt');
    }
    return $StemWorkflowRun(
      id: idValue,
      workflow: workflowValue,
      status: statusValue,
      params: paramsValue,
      result: result,
      waitTopic: waitTopic,
      resumeAt: resumeAt,
      lastError: lastError,
      suspensionData: suspensionData,
      cancellationPolicy: cancellationPolicy,
      cancellationData: cancellationData,
      createdAt: createdAtValue,
      updatedAt: updatedAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (workflow != null) 'workflow': workflow,
      if (status != null) 'status': status,
      if (params != null) 'params': params,
      if (result != null) 'result': result,
      if (waitTopic != null) 'wait_topic': waitTopic,
      if (resumeAt != null) 'resume_at': resumeAt,
      if (lastError != null) 'last_error': lastError,
      if (suspensionData != null) 'suspension_data': suspensionData,
      if (cancellationPolicy != null) 'cancellation_policy': cancellationPolicy,
      if (cancellationData != null) 'cancellation_data': cancellationData,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  static const _StemWorkflowRunPartialCopyWithSentinel _copyWithSentinel =
      _StemWorkflowRunPartialCopyWithSentinel();
  StemWorkflowRunPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? workflow = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? params = _copyWithSentinel,
    Object? result = _copyWithSentinel,
    Object? waitTopic = _copyWithSentinel,
    Object? resumeAt = _copyWithSentinel,
    Object? lastError = _copyWithSentinel,
    Object? suspensionData = _copyWithSentinel,
    Object? cancellationPolicy = _copyWithSentinel,
    Object? cancellationData = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
  }) {
    return StemWorkflowRunPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      workflow: identical(workflow, _copyWithSentinel)
          ? this.workflow
          : workflow as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
      params: identical(params, _copyWithSentinel)
          ? this.params
          : params as String?,
      result: identical(result, _copyWithSentinel)
          ? this.result
          : result as String?,
      waitTopic: identical(waitTopic, _copyWithSentinel)
          ? this.waitTopic
          : waitTopic as String?,
      resumeAt: identical(resumeAt, _copyWithSentinel)
          ? this.resumeAt
          : resumeAt as DateTime?,
      lastError: identical(lastError, _copyWithSentinel)
          ? this.lastError
          : lastError as String?,
      suspensionData: identical(suspensionData, _copyWithSentinel)
          ? this.suspensionData
          : suspensionData as String?,
      cancellationPolicy: identical(cancellationPolicy, _copyWithSentinel)
          ? this.cancellationPolicy
          : cancellationPolicy as String?,
      cancellationData: identical(cancellationData, _copyWithSentinel)
          ? this.cancellationData
          : cancellationData as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class _StemWorkflowRunPartialCopyWithSentinel {
  const _StemWorkflowRunPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemWorkflowRun].
///
/// This class extends the user-defined [StemWorkflowRun] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemWorkflowRun extends StemWorkflowRun
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemWorkflowRun].
  $StemWorkflowRun({
    required String id,
    required String workflow,
    required String status,
    required String params,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? result,
    String? waitTopic,
    DateTime? resumeAt,
    String? lastError,
    String? suspensionData,
    String? cancellationPolicy,
    String? cancellationData,
  }) : super.new(
         id: id,
         workflow: workflow,
         status: status,
         params: params,
         result: result,
         waitTopic: waitTopic,
         resumeAt: resumeAt,
         lastError: lastError,
         suspensionData: suspensionData,
         cancellationPolicy: cancellationPolicy,
         cancellationData: cancellationData,
         createdAt: createdAt,
         updatedAt: updatedAt,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'workflow': workflow,
      'status': status,
      'params': params,
      'result': result,
      'wait_topic': waitTopic,
      'resume_at': resumeAt,
      'last_error': lastError,
      'suspension_data': suspensionData,
      'cancellation_policy': cancellationPolicy,
      'cancellation_data': cancellationData,
      'created_at': createdAt,
      'updated_at': updatedAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemWorkflowRun.fromModel(StemWorkflowRun model) {
    return $StemWorkflowRun(
      id: model.id,
      workflow: model.workflow,
      status: model.status,
      params: model.params,
      result: model.result,
      waitTopic: model.waitTopic,
      resumeAt: model.resumeAt,
      lastError: model.lastError,
      suspensionData: model.suspensionData,
      cancellationPolicy: model.cancellationPolicy,
      cancellationData: model.cancellationData,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
    );
  }

  $StemWorkflowRun copyWith({
    String? id,
    String? workflow,
    String? status,
    String? params,
    String? result,
    String? waitTopic,
    DateTime? resumeAt,
    String? lastError,
    String? suspensionData,
    String? cancellationPolicy,
    String? cancellationData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return $StemWorkflowRun(
      id: id ?? this.id,
      workflow: workflow ?? this.workflow,
      status: status ?? this.status,
      params: params ?? this.params,
      result: result ?? this.result,
      waitTopic: waitTopic ?? this.waitTopic,
      resumeAt: resumeAt ?? this.resumeAt,
      lastError: lastError ?? this.lastError,
      suspensionData: suspensionData ?? this.suspensionData,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
      cancellationData: cancellationData ?? this.cancellationData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [workflow].
  @override
  String get workflow => getAttribute<String>('workflow') ?? super.workflow;

  /// Tracked setter for [workflow].
  set workflow(String value) => setAttribute('workflow', value);

  /// Tracked getter for [status].
  @override
  String get status => getAttribute<String>('status') ?? super.status;

  /// Tracked setter for [status].
  set status(String value) => setAttribute('status', value);

  /// Tracked getter for [params].
  @override
  String get params => getAttribute<String>('params') ?? super.params;

  /// Tracked setter for [params].
  set params(String value) => setAttribute('params', value);

  /// Tracked getter for [result].
  @override
  String? get result => getAttribute<String?>('result') ?? super.result;

  /// Tracked setter for [result].
  set result(String? value) => setAttribute('result', value);

  /// Tracked getter for [waitTopic].
  @override
  String? get waitTopic =>
      getAttribute<String?>('wait_topic') ?? super.waitTopic;

  /// Tracked setter for [waitTopic].
  set waitTopic(String? value) => setAttribute('wait_topic', value);

  /// Tracked getter for [resumeAt].
  @override
  DateTime? get resumeAt =>
      getAttribute<DateTime?>('resume_at') ?? super.resumeAt;

  /// Tracked setter for [resumeAt].
  set resumeAt(DateTime? value) => setAttribute('resume_at', value);

  /// Tracked getter for [lastError].
  @override
  String? get lastError =>
      getAttribute<String?>('last_error') ?? super.lastError;

  /// Tracked setter for [lastError].
  set lastError(String? value) => setAttribute('last_error', value);

  /// Tracked getter for [suspensionData].
  @override
  String? get suspensionData =>
      getAttribute<String?>('suspension_data') ?? super.suspensionData;

  /// Tracked setter for [suspensionData].
  set suspensionData(String? value) => setAttribute('suspension_data', value);

  /// Tracked getter for [cancellationPolicy].
  @override
  String? get cancellationPolicy =>
      getAttribute<String?>('cancellation_policy') ?? super.cancellationPolicy;

  /// Tracked setter for [cancellationPolicy].
  set cancellationPolicy(String? value) =>
      setAttribute('cancellation_policy', value);

  /// Tracked getter for [cancellationData].
  @override
  String? get cancellationData =>
      getAttribute<String?>('cancellation_data') ?? super.cancellationData;

  /// Tracked setter for [cancellationData].
  set cancellationData(String? value) =>
      setAttribute('cancellation_data', value);

  /// Tracked getter for [createdAt].
  @override
  DateTime get createdAt =>
      getAttribute<DateTime>('created_at') ?? super.createdAt;

  /// Tracked setter for [createdAt].
  set createdAt(DateTime value) => setAttribute('created_at', value);

  /// Tracked getter for [updatedAt].
  @override
  DateTime get updatedAt =>
      getAttribute<DateTime>('updated_at') ?? super.updatedAt;

  /// Tracked setter for [updatedAt].
  set updatedAt(DateTime value) => setAttribute('updated_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemWorkflowRunDefinition);
  }
}

extension StemWorkflowRunOrmExtension on StemWorkflowRun {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemWorkflowRun;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemWorkflowRun toTracked() {
    return $StemWorkflowRun.fromModel(this);
  }
}

void registerStemWorkflowRunEventHandlers(EventBus bus) {
  // No event handlers registered for StemWorkflowRun.
}
