// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_revoke_entry.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemRevokeEntryTaskIdField = FieldDefinition(
  name: 'taskId',
  columnName: 'task_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
);

const FieldDefinition _$StemRevokeEntryNamespaceField = FieldDefinition(
  name: 'namespace',
  columnName: 'namespace',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemRevokeEntryTerminateField = FieldDefinition(
  name: 'terminate',
  columnName: 'terminate',
  dartType: 'bool',
  resolvedType: 'bool',
  isNullable: false,
);

const FieldDefinition _$StemRevokeEntryReasonField = FieldDefinition(
  name: 'reason',
  columnName: 'reason',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemRevokeEntryRequestedByField = FieldDefinition(
  name: 'requestedBy',
  columnName: 'requested_by',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemRevokeEntryIssuedAtField = FieldDefinition(
  name: 'issuedAt',
  columnName: 'issued_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

const FieldDefinition _$StemRevokeEntryExpiresAtField = FieldDefinition(
  name: 'expiresAt',
  columnName: 'expires_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemRevokeEntryVersionField = FieldDefinition(
  name: 'version',
  columnName: 'version',
  dartType: 'int',
  resolvedType: 'int',
  isNullable: false,
);

const FieldDefinition _$StemRevokeEntryUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

Map<String, Object?> _encodeStemRevokeEntryUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemRevokeEntry;
  return <String, Object?>{
    'task_id': registry.encodeField(_$StemRevokeEntryTaskIdField, m.taskId),
    'namespace': registry.encodeField(
      _$StemRevokeEntryNamespaceField,
      m.namespace,
    ),
    'terminate': registry.encodeField(
      _$StemRevokeEntryTerminateField,
      m.terminate,
    ),
    'reason': registry.encodeField(_$StemRevokeEntryReasonField, m.reason),
    'requested_by': registry.encodeField(
      _$StemRevokeEntryRequestedByField,
      m.requestedBy,
    ),
    'issued_at': registry.encodeField(
      _$StemRevokeEntryIssuedAtField,
      m.issuedAt,
    ),
    'expires_at': registry.encodeField(
      _$StemRevokeEntryExpiresAtField,
      m.expiresAt,
    ),
    'version': registry.encodeField(_$StemRevokeEntryVersionField, m.version),
    'updated_at': registry.encodeField(
      _$StemRevokeEntryUpdatedAtField,
      m.updatedAt,
    ),
  };
}

const ModelDefinition<$StemRevokeEntry> _$StemRevokeEntryDefinition =
    ModelDefinition(
      modelName: 'StemRevokeEntry',
      tableName: 'stem_revokes',
      fields: [
        _$StemRevokeEntryTaskIdField,
        _$StemRevokeEntryNamespaceField,
        _$StemRevokeEntryTerminateField,
        _$StemRevokeEntryReasonField,
        _$StemRevokeEntryRequestedByField,
        _$StemRevokeEntryIssuedAtField,
        _$StemRevokeEntryExpiresAtField,
        _$StemRevokeEntryVersionField,
        _$StemRevokeEntryUpdatedAtField,
      ],
      softDeleteColumn: 'deleted_at',
      untrackedToMap: _encodeStemRevokeEntryUntracked,
      codec: _$StemRevokeEntryCodec(),
    );

extension StemRevokeEntryOrmDefinition on StemRevokeEntry {
  static ModelDefinition<$StemRevokeEntry> get definition =>
      _$StemRevokeEntryDefinition;
}

class StemRevokeEntries {
  const StemRevokeEntries._();

  /// Starts building a query for [$StemRevokeEntry].
  ///
  /// {@macro ormed.query}
  static Query<$StemRevokeEntry> query([String? connection]) =>
      Model.query<$StemRevokeEntry>(connection: connection);

  static Future<$StemRevokeEntry?> find(Object id, {String? connection}) =>
      Model.find<$StemRevokeEntry>(id, connection: connection);

  static Future<$StemRevokeEntry> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemRevokeEntry>(id, connection: connection);

  static Future<List<$StemRevokeEntry>> all({String? connection}) =>
      Model.all<$StemRevokeEntry>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemRevokeEntry>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemRevokeEntry>(connection: connection);

  static Query<$StemRevokeEntry> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemRevokeEntry>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemRevokeEntry> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemRevokeEntry>(column, values, connection: connection);

  static Query<$StemRevokeEntry> orderBy(
    String column, {
    String direction = 'asc',
    String? connection,
  }) => Model.orderBy<$StemRevokeEntry>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemRevokeEntry> limit(int count, {String? connection}) =>
      Model.limit<$StemRevokeEntry>(count, connection: connection);

  /// Creates a [Repository] for [$StemRevokeEntry].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemRevokeEntry> repo([String? connection]) =>
      Model.repository<$StemRevokeEntry>(connection: connection);
}

class StemRevokeEntryModelFactory {
  const StemRevokeEntryModelFactory._();

  static ModelDefinition<$StemRevokeEntry> get definition =>
      _$StemRevokeEntryDefinition;

  static ModelCodec<$StemRevokeEntry> get codec => definition.codec;

  static StemRevokeEntry fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemRevokeEntry model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemRevokeEntry> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemRevokeEntry>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemRevokeEntry> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemRevokeEntry>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemRevokeEntryCodec extends ModelCodec<$StemRevokeEntry> {
  const _$StemRevokeEntryCodec();
  @override
  Map<String, Object?> encode(
    $StemRevokeEntry model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'task_id': registry.encodeField(
        _$StemRevokeEntryTaskIdField,
        model.taskId,
      ),
      'namespace': registry.encodeField(
        _$StemRevokeEntryNamespaceField,
        model.namespace,
      ),
      'terminate': registry.encodeField(
        _$StemRevokeEntryTerminateField,
        model.terminate,
      ),
      'reason': registry.encodeField(
        _$StemRevokeEntryReasonField,
        model.reason,
      ),
      'requested_by': registry.encodeField(
        _$StemRevokeEntryRequestedByField,
        model.requestedBy,
      ),
      'issued_at': registry.encodeField(
        _$StemRevokeEntryIssuedAtField,
        model.issuedAt,
      ),
      'expires_at': registry.encodeField(
        _$StemRevokeEntryExpiresAtField,
        model.expiresAt,
      ),
      'version': registry.encodeField(
        _$StemRevokeEntryVersionField,
        model.version,
      ),
      'updated_at': registry.encodeField(
        _$StemRevokeEntryUpdatedAtField,
        model.updatedAt,
      ),
    };
  }

  @override
  $StemRevokeEntry decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final stemRevokeEntryTaskIdValue =
        registry.decodeField<String>(
          _$StemRevokeEntryTaskIdField,
          data['task_id'],
        ) ??
        (throw StateError('Field taskId on StemRevokeEntry cannot be null.'));
    final stemRevokeEntryNamespaceValue =
        registry.decodeField<String>(
          _$StemRevokeEntryNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemRevokeEntry cannot be null.',
        ));
    final stemRevokeEntryTerminateValue =
        registry.decodeField<bool>(
          _$StemRevokeEntryTerminateField,
          data['terminate'],
        ) ??
        (throw StateError(
          'Field terminate on StemRevokeEntry cannot be null.',
        ));
    final stemRevokeEntryReasonValue = registry.decodeField<String?>(
      _$StemRevokeEntryReasonField,
      data['reason'],
    );
    final stemRevokeEntryRequestedByValue = registry.decodeField<String?>(
      _$StemRevokeEntryRequestedByField,
      data['requested_by'],
    );
    final stemRevokeEntryIssuedAtValue =
        registry.decodeField<DateTime>(
          _$StemRevokeEntryIssuedAtField,
          data['issued_at'],
        ) ??
        (throw StateError('Field issuedAt on StemRevokeEntry cannot be null.'));
    final stemRevokeEntryExpiresAtValue = registry.decodeField<DateTime?>(
      _$StemRevokeEntryExpiresAtField,
      data['expires_at'],
    );
    final stemRevokeEntryVersionValue =
        registry.decodeField<int>(
          _$StemRevokeEntryVersionField,
          data['version'],
        ) ??
        (throw StateError('Field version on StemRevokeEntry cannot be null.'));
    final stemRevokeEntryUpdatedAtValue =
        registry.decodeField<DateTime>(
          _$StemRevokeEntryUpdatedAtField,
          data['updated_at'],
        ) ??
        (throw StateError(
          'Field updatedAt on StemRevokeEntry cannot be null.',
        ));
    final model = $StemRevokeEntry(
      taskId: stemRevokeEntryTaskIdValue,
      namespace: stemRevokeEntryNamespaceValue,
      terminate: stemRevokeEntryTerminateValue,
      reason: stemRevokeEntryReasonValue,
      requestedBy: stemRevokeEntryRequestedByValue,
      issuedAt: stemRevokeEntryIssuedAtValue,
      expiresAt: stemRevokeEntryExpiresAtValue,
      version: stemRevokeEntryVersionValue,
      updatedAt: stemRevokeEntryUpdatedAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'task_id': stemRevokeEntryTaskIdValue,
      'namespace': stemRevokeEntryNamespaceValue,
      'terminate': stemRevokeEntryTerminateValue,
      'reason': stemRevokeEntryReasonValue,
      'requested_by': stemRevokeEntryRequestedByValue,
      'issued_at': stemRevokeEntryIssuedAtValue,
      'expires_at': stemRevokeEntryExpiresAtValue,
      'version': stemRevokeEntryVersionValue,
      'updated_at': stemRevokeEntryUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemRevokeEntry].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemRevokeEntryInsertDto implements InsertDto<$StemRevokeEntry> {
  const StemRevokeEntryInsertDto({
    this.taskId,
    this.namespace,
    this.terminate,
    this.reason,
    this.requestedBy,
    this.issuedAt,
    this.expiresAt,
    this.version,
    this.updatedAt,
  });
  final String? taskId;
  final String? namespace;
  final bool? terminate;
  final String? reason;
  final String? requestedBy;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final int? version;
  final DateTime? updatedAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (taskId != null) 'task_id': taskId,
      if (namespace != null) 'namespace': namespace,
      if (terminate != null) 'terminate': terminate,
      if (reason != null) 'reason': reason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  static const _StemRevokeEntryInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryInsertDtoCopyWithSentinel();
  StemRevokeEntryInsertDto copyWith({
    Object? taskId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
  }) {
    return StemRevokeEntryInsertDto(
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as bool?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class _StemRevokeEntryInsertDtoCopyWithSentinel {
  const _StemRevokeEntryInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemRevokeEntry].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemRevokeEntryUpdateDto implements UpdateDto<$StemRevokeEntry> {
  const StemRevokeEntryUpdateDto({
    this.taskId,
    this.namespace,
    this.terminate,
    this.reason,
    this.requestedBy,
    this.issuedAt,
    this.expiresAt,
    this.version,
    this.updatedAt,
  });
  final String? taskId;
  final String? namespace;
  final bool? terminate;
  final String? reason;
  final String? requestedBy;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final int? version;
  final DateTime? updatedAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (taskId != null) 'task_id': taskId,
      if (namespace != null) 'namespace': namespace,
      if (terminate != null) 'terminate': terminate,
      if (reason != null) 'reason': reason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  static const _StemRevokeEntryUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryUpdateDtoCopyWithSentinel();
  StemRevokeEntryUpdateDto copyWith({
    Object? taskId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
  }) {
    return StemRevokeEntryUpdateDto(
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as bool?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class _StemRevokeEntryUpdateDtoCopyWithSentinel {
  const _StemRevokeEntryUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemRevokeEntry].
///
/// All fields are nullable; intended for subset SELECTs.
class StemRevokeEntryPartial implements PartialEntity<$StemRevokeEntry> {
  const StemRevokeEntryPartial({
    this.taskId,
    this.namespace,
    this.terminate,
    this.reason,
    this.requestedBy,
    this.issuedAt,
    this.expiresAt,
    this.version,
    this.updatedAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemRevokeEntryPartial.fromRow(Map<String, Object?> row) {
    return StemRevokeEntryPartial(
      taskId: row['task_id'] as String?,
      namespace: row['namespace'] as String?,
      terminate: row['terminate'] as bool?,
      reason: row['reason'] as String?,
      requestedBy: row['requested_by'] as String?,
      issuedAt: row['issued_at'] as DateTime?,
      expiresAt: row['expires_at'] as DateTime?,
      version: row['version'] as int?,
      updatedAt: row['updated_at'] as DateTime?,
    );
  }

  final String? taskId;
  final String? namespace;
  final bool? terminate;
  final String? reason;
  final String? requestedBy;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final int? version;
  final DateTime? updatedAt;

  @override
  $StemRevokeEntry toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final taskIdValue = taskId;
    if (taskIdValue == null) {
      throw StateError('Missing required field: taskId');
    }
    final namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final terminateValue = terminate;
    if (terminateValue == null) {
      throw StateError('Missing required field: terminate');
    }
    final issuedAtValue = issuedAt;
    if (issuedAtValue == null) {
      throw StateError('Missing required field: issuedAt');
    }
    final versionValue = version;
    if (versionValue == null) {
      throw StateError('Missing required field: version');
    }
    final updatedAtValue = updatedAt;
    if (updatedAtValue == null) {
      throw StateError('Missing required field: updatedAt');
    }
    return $StemRevokeEntry(
      taskId: taskIdValue,
      namespace: namespaceValue,
      terminate: terminateValue,
      reason: reason,
      requestedBy: requestedBy,
      issuedAt: issuedAtValue,
      expiresAt: expiresAt,
      version: versionValue,
      updatedAt: updatedAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (taskId != null) 'task_id': taskId,
      if (namespace != null) 'namespace': namespace,
      if (terminate != null) 'terminate': terminate,
      if (reason != null) 'reason': reason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  static const _StemRevokeEntryPartialCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryPartialCopyWithSentinel();
  StemRevokeEntryPartial copyWith({
    Object? taskId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
  }) {
    return StemRevokeEntryPartial(
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as bool?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class _StemRevokeEntryPartialCopyWithSentinel {
  const _StemRevokeEntryPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemRevokeEntry].
///
/// This class extends the user-defined [StemRevokeEntry] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemRevokeEntry extends StemRevokeEntry
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemRevokeEntry].
  $StemRevokeEntry({
    required String taskId,
    required String namespace,
    required bool terminate,
    required DateTime issuedAt,
    required int version,
    required DateTime updatedAt,
    String? reason,
    String? requestedBy,
    DateTime? expiresAt,
  }) : super.new(
         taskId: taskId,
         namespace: namespace,
         terminate: terminate,
         reason: reason,
         requestedBy: requestedBy,
         issuedAt: issuedAt,
         expiresAt: expiresAt,
         version: version,
         updatedAt: updatedAt,
       ) {
    _attachOrmRuntimeMetadata({
      'task_id': taskId,
      'namespace': namespace,
      'terminate': terminate,
      'reason': reason,
      'requested_by': requestedBy,
      'issued_at': issuedAt,
      'expires_at': expiresAt,
      'version': version,
      'updated_at': updatedAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemRevokeEntry.fromModel(StemRevokeEntry model) {
    return $StemRevokeEntry(
      taskId: model.taskId,
      namespace: model.namespace,
      terminate: model.terminate,
      reason: model.reason,
      requestedBy: model.requestedBy,
      issuedAt: model.issuedAt,
      expiresAt: model.expiresAt,
      version: model.version,
      updatedAt: model.updatedAt,
    );
  }

  $StemRevokeEntry copyWith({
    String? taskId,
    String? namespace,
    bool? terminate,
    String? reason,
    String? requestedBy,
    DateTime? issuedAt,
    DateTime? expiresAt,
    int? version,
    DateTime? updatedAt,
  }) {
    return $StemRevokeEntry(
      taskId: taskId ?? this.taskId,
      namespace: namespace ?? this.namespace,
      terminate: terminate ?? this.terminate,
      reason: reason ?? this.reason,
      requestedBy: requestedBy ?? this.requestedBy,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Tracked getter for [taskId].
  @override
  String get taskId => getAttribute<String>('task_id') ?? super.taskId;

  /// Tracked setter for [taskId].
  set taskId(String value) => setAttribute('task_id', value);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [terminate].
  @override
  bool get terminate => getAttribute<bool>('terminate') ?? super.terminate;

  /// Tracked setter for [terminate].
  set terminate(bool value) => setAttribute('terminate', value);

  /// Tracked getter for [reason].
  @override
  String? get reason => getAttribute<String?>('reason') ?? super.reason;

  /// Tracked setter for [reason].
  set reason(String? value) => setAttribute('reason', value);

  /// Tracked getter for [requestedBy].
  @override
  String? get requestedBy =>
      getAttribute<String?>('requested_by') ?? super.requestedBy;

  /// Tracked setter for [requestedBy].
  set requestedBy(String? value) => setAttribute('requested_by', value);

  /// Tracked getter for [issuedAt].
  @override
  DateTime get issuedAt =>
      getAttribute<DateTime>('issued_at') ?? super.issuedAt;

  /// Tracked setter for [issuedAt].
  set issuedAt(DateTime value) => setAttribute('issued_at', value);

  /// Tracked getter for [expiresAt].
  @override
  DateTime? get expiresAt =>
      getAttribute<DateTime?>('expires_at') ?? super.expiresAt;

  /// Tracked setter for [expiresAt].
  set expiresAt(DateTime? value) => setAttribute('expires_at', value);

  /// Tracked getter for [version].
  @override
  int get version => getAttribute<int>('version') ?? super.version;

  /// Tracked setter for [version].
  set version(int value) => setAttribute('version', value);

  /// Tracked getter for [updatedAt].
  @override
  DateTime get updatedAt =>
      getAttribute<DateTime>('updated_at') ?? super.updatedAt;

  /// Tracked setter for [updatedAt].
  set updatedAt(DateTime value) => setAttribute('updated_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemRevokeEntryDefinition);
  }
}

extension StemRevokeEntryOrmExtension on StemRevokeEntry {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemRevokeEntry;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemRevokeEntry toTracked() {
    return $StemRevokeEntry.fromModel(this);
  }
}

void registerStemRevokeEntryEventHandlers(EventBus bus) {
  // No event handlers registered for StemRevokeEntry.
}
