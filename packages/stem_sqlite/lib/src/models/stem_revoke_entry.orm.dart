// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_revoke_entry.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemRevokeEntryNamespaceField = FieldDefinition(
  name: 'namespace',
  columnName: 'namespace',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryTaskIdField = FieldDefinition(
  name: 'taskId',
  columnName: 'task_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryVersionField = FieldDefinition(
  name: 'version',
  columnName: 'version',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryIssuedAtField = FieldDefinition(
  name: 'issuedAt',
  columnName: 'issued_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryTerminateField = FieldDefinition(
  name: 'terminate',
  columnName: 'terminate',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryReasonField = FieldDefinition(
  name: 'reason',
  columnName: 'reason',
  dartType: 'String',
  resolvedType: 'String?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryRequestedByField = FieldDefinition(
  name: 'requestedBy',
  columnName: 'requested_by',
  dartType: 'String',
  resolvedType: 'String?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryExpiresAtField = FieldDefinition(
  name: 'expiresAt',
  columnName: 'expires_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemRevokeEntryUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeStemRevokeEntryUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemRevokeEntry;
  return <String, Object?>{
    'namespace': registry.encodeField(
      _$StemRevokeEntryNamespaceField,
      m.namespace,
    ),
    'task_id': registry.encodeField(_$StemRevokeEntryTaskIdField, m.taskId),
    'version': registry.encodeField(_$StemRevokeEntryVersionField, m.version),
    'issued_at': registry.encodeField(
      _$StemRevokeEntryIssuedAtField,
      m.issuedAt,
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
    'expires_at': registry.encodeField(
      _$StemRevokeEntryExpiresAtField,
      m.expiresAt,
    ),
  };
}

final ModelDefinition<$StemRevokeEntry> _$StemRevokeEntryDefinition =
    ModelDefinition(
      modelName: 'StemRevokeEntry',
      tableName: 'stem_revokes',
      fields: const [
        _$StemRevokeEntryNamespaceField,
        _$StemRevokeEntryTaskIdField,
        _$StemRevokeEntryVersionField,
        _$StemRevokeEntryIssuedAtField,
        _$StemRevokeEntryTerminateField,
        _$StemRevokeEntryReasonField,
        _$StemRevokeEntryRequestedByField,
        _$StemRevokeEntryExpiresAtField,
        _$StemRevokeEntryCreatedAtField,
        _$StemRevokeEntryUpdatedAtField,
      ],
      relations: const [],
      softDeleteColumn: 'deleted_at',
      metadata: ModelAttributesMetadata(
        hidden: const <String>[],
        visible: const <String>[],
        fillable: const <String>[],
        guarded: const <String>[],
        casts: const <String, String>{},
        appends: const <String>[],
        touches: const <String>[],
        timestamps: true,
        softDeletes: false,
        softDeleteColumn: 'deleted_at',
      ),
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
    String direction = "asc",
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

  /// Builds a tracked model from a column/value map.
  static $StemRevokeEntry fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemRevokeEntryDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemRevokeEntry model, {
    ValueCodecRegistry? registry,
  }) => _$StemRevokeEntryDefinition.toMap(model, registry: registry);
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
  }) => ModelFactoryRegistry.factoryFor<StemRevokeEntry>(
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
      'namespace': registry.encodeField(
        _$StemRevokeEntryNamespaceField,
        model.namespace,
      ),
      'task_id': registry.encodeField(
        _$StemRevokeEntryTaskIdField,
        model.taskId,
      ),
      'version': registry.encodeField(
        _$StemRevokeEntryVersionField,
        model.version,
      ),
      'issued_at': registry.encodeField(
        _$StemRevokeEntryIssuedAtField,
        model.issuedAt,
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
      'expires_at': registry.encodeField(
        _$StemRevokeEntryExpiresAtField,
        model.expiresAt,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemRevokeEntryCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemRevokeEntryUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemRevokeEntry decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemRevokeEntryNamespaceValue =
        registry.decodeField<String>(
          _$StemRevokeEntryNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemRevokeEntry cannot be null.',
        ));
    final String stemRevokeEntryTaskIdValue =
        registry.decodeField<String>(
          _$StemRevokeEntryTaskIdField,
          data['task_id'],
        ) ??
        (throw StateError('Field taskId on StemRevokeEntry cannot be null.'));
    final int stemRevokeEntryVersionValue =
        registry.decodeField<int>(
          _$StemRevokeEntryVersionField,
          data['version'],
        ) ??
        (throw StateError('Field version on StemRevokeEntry cannot be null.'));
    final DateTime stemRevokeEntryIssuedAtValue =
        registry.decodeField<DateTime>(
          _$StemRevokeEntryIssuedAtField,
          data['issued_at'],
        ) ??
        (throw StateError('Field issuedAt on StemRevokeEntry cannot be null.'));
    final int stemRevokeEntryTerminateValue =
        registry.decodeField<int>(
          _$StemRevokeEntryTerminateField,
          data['terminate'],
        ) ??
        (throw StateError(
          'Field terminate on StemRevokeEntry cannot be null.',
        ));
    final String? stemRevokeEntryReasonValue = registry.decodeField<String?>(
      _$StemRevokeEntryReasonField,
      data['reason'],
    );
    final String? stemRevokeEntryRequestedByValue = registry
        .decodeField<String?>(
          _$StemRevokeEntryRequestedByField,
          data['requested_by'],
        );
    final DateTime? stemRevokeEntryExpiresAtValue = registry
        .decodeField<DateTime?>(
          _$StemRevokeEntryExpiresAtField,
          data['expires_at'],
        );
    final DateTime? stemRevokeEntryCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemRevokeEntryCreatedAtField,
          data['created_at'],
        );
    final DateTime? stemRevokeEntryUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemRevokeEntryUpdatedAtField,
          data['updated_at'],
        );
    final model = $StemRevokeEntry(
      namespace: stemRevokeEntryNamespaceValue,
      taskId: stemRevokeEntryTaskIdValue,
      version: stemRevokeEntryVersionValue,
      issuedAt: stemRevokeEntryIssuedAtValue,
      terminate: stemRevokeEntryTerminateValue,
      reason: stemRevokeEntryReasonValue,
      requestedBy: stemRevokeEntryRequestedByValue,
      expiresAt: stemRevokeEntryExpiresAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'namespace': stemRevokeEntryNamespaceValue,
      'task_id': stemRevokeEntryTaskIdValue,
      'version': stemRevokeEntryVersionValue,
      'issued_at': stemRevokeEntryIssuedAtValue,
      'terminate': stemRevokeEntryTerminateValue,
      'reason': stemRevokeEntryReasonValue,
      'requested_by': stemRevokeEntryRequestedByValue,
      'expires_at': stemRevokeEntryExpiresAtValue,
      if (data.containsKey('created_at'))
        'created_at': stemRevokeEntryCreatedAtValue,
      if (data.containsKey('updated_at'))
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
    this.namespace,
    this.taskId,
    this.version,
    this.issuedAt,
    this.terminate,
    this.reason,
    this.requestedBy,
    this.expiresAt,
  });
  final String? namespace;
  final String? taskId;
  final int? version;
  final DateTime? issuedAt;
  final int? terminate;
  final String? reason;
  final String? requestedBy;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (namespace != null) 'namespace': namespace,
      if (taskId != null) 'task_id': taskId,
      if (version != null) 'version': version,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (terminate != null) 'terminate': terminate,
      if (reason != null) 'reason': reason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemRevokeEntryInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryInsertDtoCopyWithSentinel();
  StemRevokeEntryInsertDto copyWith({
    Object? namespace = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemRevokeEntryInsertDto(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime?,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as int?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
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
    this.namespace,
    this.taskId,
    this.version,
    this.issuedAt,
    this.terminate,
    this.reason,
    this.requestedBy,
    this.expiresAt,
  });
  final String? namespace;
  final String? taskId;
  final int? version;
  final DateTime? issuedAt;
  final int? terminate;
  final String? reason;
  final String? requestedBy;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (namespace != null) 'namespace': namespace,
      if (taskId != null) 'task_id': taskId,
      if (version != null) 'version': version,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (terminate != null) 'terminate': terminate,
      if (reason != null) 'reason': reason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemRevokeEntryUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryUpdateDtoCopyWithSentinel();
  StemRevokeEntryUpdateDto copyWith({
    Object? namespace = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemRevokeEntryUpdateDto(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime?,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as int?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
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
    this.namespace,
    this.taskId,
    this.version,
    this.issuedAt,
    this.terminate,
    this.reason,
    this.requestedBy,
    this.expiresAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemRevokeEntryPartial.fromRow(Map<String, Object?> row) {
    return StemRevokeEntryPartial(
      namespace: row['namespace'] as String?,
      taskId: row['task_id'] as String?,
      version: row['version'] as int?,
      issuedAt: row['issued_at'] as DateTime?,
      terminate: row['terminate'] as int?,
      reason: row['reason'] as String?,
      requestedBy: row['requested_by'] as String?,
      expiresAt: row['expires_at'] as DateTime?,
    );
  }

  final String? namespace;
  final String? taskId;
  final int? version;
  final DateTime? issuedAt;
  final int? terminate;
  final String? reason;
  final String? requestedBy;
  final DateTime? expiresAt;

  @override
  $StemRevokeEntry toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final String? taskIdValue = taskId;
    if (taskIdValue == null) {
      throw StateError('Missing required field: taskId');
    }
    final int? versionValue = version;
    if (versionValue == null) {
      throw StateError('Missing required field: version');
    }
    final DateTime? issuedAtValue = issuedAt;
    if (issuedAtValue == null) {
      throw StateError('Missing required field: issuedAt');
    }
    final int? terminateValue = terminate;
    if (terminateValue == null) {
      throw StateError('Missing required field: terminate');
    }
    return $StemRevokeEntry(
      namespace: namespaceValue,
      taskId: taskIdValue,
      version: versionValue,
      issuedAt: issuedAtValue,
      terminate: terminateValue,
      reason: reason,
      requestedBy: requestedBy,
      expiresAt: expiresAt,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (namespace != null) 'namespace': namespace,
      if (taskId != null) 'task_id': taskId,
      if (version != null) 'version': version,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (terminate != null) 'terminate': terminate,
      if (reason != null) 'reason': reason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemRevokeEntryPartialCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryPartialCopyWithSentinel();
  StemRevokeEntryPartial copyWith({
    Object? namespace = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemRevokeEntryPartial(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime?,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as int?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
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
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemRevokeEntry].
  $StemRevokeEntry({
    required String namespace,
    required String taskId,
    required int version,
    required DateTime issuedAt,
    required int terminate,
    String? reason,
    String? requestedBy,
    DateTime? expiresAt,
  }) : super(
         namespace: namespace,
         taskId: taskId,
         version: version,
         issuedAt: issuedAt,
         terminate: terminate,
         reason: reason,
         requestedBy: requestedBy,
         expiresAt: expiresAt,
       ) {
    _attachOrmRuntimeMetadata({
      'namespace': namespace,
      'task_id': taskId,
      'version': version,
      'issued_at': issuedAt,
      'terminate': terminate,
      'reason': reason,
      'requested_by': requestedBy,
      'expires_at': expiresAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemRevokeEntry.fromModel(StemRevokeEntry model) {
    return $StemRevokeEntry(
      namespace: model.namespace,
      taskId: model.taskId,
      version: model.version,
      issuedAt: model.issuedAt,
      terminate: model.terminate,
      reason: model.reason,
      requestedBy: model.requestedBy,
      expiresAt: model.expiresAt,
    );
  }

  $StemRevokeEntry copyWith({
    String? namespace,
    String? taskId,
    int? version,
    DateTime? issuedAt,
    int? terminate,
    String? reason,
    String? requestedBy,
    DateTime? expiresAt,
  }) {
    return $StemRevokeEntry(
      namespace: namespace ?? this.namespace,
      taskId: taskId ?? this.taskId,
      version: version ?? this.version,
      issuedAt: issuedAt ?? this.issuedAt,
      terminate: terminate ?? this.terminate,
      reason: reason ?? this.reason,
      requestedBy: requestedBy ?? this.requestedBy,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemRevokeEntry fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemRevokeEntryDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemRevokeEntryDefinition.toMap(this, registry: registry);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [taskId].
  @override
  String get taskId => getAttribute<String>('task_id') ?? super.taskId;

  /// Tracked setter for [taskId].
  set taskId(String value) => setAttribute('task_id', value);

  /// Tracked getter for [version].
  @override
  int get version => getAttribute<int>('version') ?? super.version;

  /// Tracked setter for [version].
  set version(int value) => setAttribute('version', value);

  /// Tracked getter for [issuedAt].
  @override
  DateTime get issuedAt =>
      getAttribute<DateTime>('issued_at') ?? super.issuedAt;

  /// Tracked setter for [issuedAt].
  set issuedAt(DateTime value) => setAttribute('issued_at', value);

  /// Tracked getter for [terminate].
  @override
  int get terminate => getAttribute<int>('terminate') ?? super.terminate;

  /// Tracked setter for [terminate].
  set terminate(int value) => setAttribute('terminate', value);

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

  /// Tracked getter for [expiresAt].
  @override
  DateTime? get expiresAt =>
      getAttribute<DateTime?>('expires_at') ?? super.expiresAt;

  /// Tracked setter for [expiresAt].
  set expiresAt(DateTime? value) => setAttribute('expires_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemRevokeEntryDefinition);
  }
}

class _StemRevokeEntryCopyWithSentinel {
  const _StemRevokeEntryCopyWithSentinel();
}

extension StemRevokeEntryOrmExtension on StemRevokeEntry {
  static const _StemRevokeEntryCopyWithSentinel _copyWithSentinel =
      _StemRevokeEntryCopyWithSentinel();
  StemRevokeEntry copyWith({
    Object? namespace = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? issuedAt = _copyWithSentinel,
    Object? terminate = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? requestedBy = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemRevokeEntry(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int,
      issuedAt: identical(issuedAt, _copyWithSentinel)
          ? this.issuedAt
          : issuedAt as DateTime,
      terminate: identical(terminate, _copyWithSentinel)
          ? this.terminate
          : terminate as int,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      requestedBy: identical(requestedBy, _copyWithSentinel)
          ? this.requestedBy
          : requestedBy as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemRevokeEntryDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemRevokeEntry fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemRevokeEntryDefinition.fromMap(data, registry: registry);

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

extension StemRevokeEntryPredicateFields on PredicateBuilder<StemRevokeEntry> {
  PredicateField<StemRevokeEntry, String> get namespace =>
      PredicateField<StemRevokeEntry, String>(this, 'namespace');
  PredicateField<StemRevokeEntry, String> get taskId =>
      PredicateField<StemRevokeEntry, String>(this, 'taskId');
  PredicateField<StemRevokeEntry, int> get version =>
      PredicateField<StemRevokeEntry, int>(this, 'version');
  PredicateField<StemRevokeEntry, DateTime> get issuedAt =>
      PredicateField<StemRevokeEntry, DateTime>(this, 'issuedAt');
  PredicateField<StemRevokeEntry, int> get terminate =>
      PredicateField<StemRevokeEntry, int>(this, 'terminate');
  PredicateField<StemRevokeEntry, String?> get reason =>
      PredicateField<StemRevokeEntry, String?>(this, 'reason');
  PredicateField<StemRevokeEntry, String?> get requestedBy =>
      PredicateField<StemRevokeEntry, String?>(this, 'requestedBy');
  PredicateField<StemRevokeEntry, DateTime?> get expiresAt =>
      PredicateField<StemRevokeEntry, DateTime?>(this, 'expiresAt');
}

void registerStemRevokeEntryEventHandlers(EventBus bus) {
  // No event handlers registered for StemRevokeEntry.
}
