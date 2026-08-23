// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_worker_heartbeat.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemWorkerHeartbeatWorkerIdField = FieldDefinition(
  name: 'workerId',
  columnName: 'worker_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatNamespaceField = FieldDefinition(
  name: 'namespace',
  columnName: 'namespace',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatTimestampField = FieldDefinition(
  name: 'timestamp',
  columnName: 'timestamp',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatIsolateCountField = FieldDefinition(
  name: 'isolateCount',
  columnName: 'isolate_count',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatInflightField = FieldDefinition(
  name: 'inflight',
  columnName: 'inflight',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatQueuesField = FieldDefinition(
  name: 'queues',
  columnName: 'queues',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
  codecType: 'json',
);

const FieldDefinition _$StemWorkerHeartbeatLastLeaseRenewalField =
    FieldDefinition(
      name: 'lastLeaseRenewal',
      columnName: 'last_lease_renewal',
      dartType: 'DateTime',
      resolvedType: 'DateTime?',
      isPrimaryKey: false,
      isNullable: true,
      isUnique: false,
      isIndexed: false,
      autoIncrement: false,
    );

const FieldDefinition _$StemWorkerHeartbeatVersionField = FieldDefinition(
  name: 'version',
  columnName: 'version',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatExtrasField = FieldDefinition(
  name: 'extras',
  columnName: 'extras',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
  codecType: 'json',
);

const FieldDefinition _$StemWorkerHeartbeatExpiresAtField = FieldDefinition(
  name: 'expiresAt',
  columnName: 'expires_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatDeletedAtField = FieldDefinition(
  name: 'deletedAt',
  columnName: 'deleted_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkerHeartbeatCreatedAtField = FieldDefinition(
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

const FieldDefinition _$StemWorkerHeartbeatUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeStemWorkerHeartbeatUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemWorkerHeartbeat;
  return <String, Object?>{
    'worker_id': registry.encodeField(
      _$StemWorkerHeartbeatWorkerIdField,
      m.workerId,
    ),
    'namespace': registry.encodeField(
      _$StemWorkerHeartbeatNamespaceField,
      m.namespace,
    ),
    'timestamp': registry.encodeField(
      _$StemWorkerHeartbeatTimestampField,
      m.timestamp,
    ),
    'isolate_count': registry.encodeField(
      _$StemWorkerHeartbeatIsolateCountField,
      m.isolateCount,
    ),
    'inflight': registry.encodeField(
      _$StemWorkerHeartbeatInflightField,
      m.inflight,
    ),
    'queues': registry.encodeField(_$StemWorkerHeartbeatQueuesField, m.queues),
    'last_lease_renewal': registry.encodeField(
      _$StemWorkerHeartbeatLastLeaseRenewalField,
      m.lastLeaseRenewal,
    ),
    'version': registry.encodeField(
      _$StemWorkerHeartbeatVersionField,
      m.version,
    ),
    'extras': registry.encodeField(_$StemWorkerHeartbeatExtrasField, m.extras),
    'expires_at': registry.encodeField(
      _$StemWorkerHeartbeatExpiresAtField,
      m.expiresAt,
    ),
  };
}

final ModelDefinition<$StemWorkerHeartbeat> _$StemWorkerHeartbeatDefinition =
    ModelDefinition(
      modelName: 'StemWorkerHeartbeat',
      tableName: 'stem_worker_heartbeats',
      fields: const [
        _$StemWorkerHeartbeatWorkerIdField,
        _$StemWorkerHeartbeatNamespaceField,
        _$StemWorkerHeartbeatTimestampField,
        _$StemWorkerHeartbeatIsolateCountField,
        _$StemWorkerHeartbeatInflightField,
        _$StemWorkerHeartbeatQueuesField,
        _$StemWorkerHeartbeatLastLeaseRenewalField,
        _$StemWorkerHeartbeatVersionField,
        _$StemWorkerHeartbeatExtrasField,
        _$StemWorkerHeartbeatExpiresAtField,
        _$StemWorkerHeartbeatDeletedAtField,
        _$StemWorkerHeartbeatCreatedAtField,
        _$StemWorkerHeartbeatUpdatedAtField,
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
        fieldOverrides: const {
          'queues': FieldAttributeMetadata(cast: 'json'),
          'extras': FieldAttributeMetadata(cast: 'json'),
        },
        softDeletes: false,
        softDeleteColumn: 'deleted_at',
      ),
      untrackedToMap: _encodeStemWorkerHeartbeatUntracked,
      codec: _$StemWorkerHeartbeatCodec(),
    );

extension StemWorkerHeartbeatOrmDefinition on StemWorkerHeartbeat {
  static ModelDefinition<$StemWorkerHeartbeat> get definition =>
      _$StemWorkerHeartbeatDefinition;
}

class StemWorkerHeartbeats {
  const StemWorkerHeartbeats._();

  /// Starts building a query for [$StemWorkerHeartbeat].
  ///
  /// {@macro ormed.query}
  static Query<$StemWorkerHeartbeat> query([String? connection]) =>
      Model.query<$StemWorkerHeartbeat>(connection: connection);

  static Future<$StemWorkerHeartbeat?> find(Object id, {String? connection}) =>
      Model.find<$StemWorkerHeartbeat>(id, connection: connection);

  static Future<$StemWorkerHeartbeat> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemWorkerHeartbeat>(id, connection: connection);

  static Future<List<$StemWorkerHeartbeat>> all({String? connection}) =>
      Model.all<$StemWorkerHeartbeat>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemWorkerHeartbeat>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemWorkerHeartbeat>(connection: connection);

  static Query<$StemWorkerHeartbeat> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemWorkerHeartbeat>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemWorkerHeartbeat> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemWorkerHeartbeat>(
    column,
    values,
    connection: connection,
  );

  static Query<$StemWorkerHeartbeat> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemWorkerHeartbeat>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemWorkerHeartbeat> limit(int count, {String? connection}) =>
      Model.limit<$StemWorkerHeartbeat>(count, connection: connection);

  /// Creates a [Repository] for [$StemWorkerHeartbeat].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemWorkerHeartbeat> repo([String? connection]) =>
      Model.repository<$StemWorkerHeartbeat>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemWorkerHeartbeat fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkerHeartbeatDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemWorkerHeartbeat model, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkerHeartbeatDefinition.toMap(model, registry: registry);
}

class StemWorkerHeartbeatModelFactory {
  const StemWorkerHeartbeatModelFactory._();

  static ModelDefinition<$StemWorkerHeartbeat> get definition =>
      _$StemWorkerHeartbeatDefinition;

  static ModelCodec<$StemWorkerHeartbeat> get codec => definition.codec;

  static StemWorkerHeartbeat fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemWorkerHeartbeat model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemWorkerHeartbeat> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemWorkerHeartbeat>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemWorkerHeartbeat> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<StemWorkerHeartbeat>(
    generatorProvider: generatorProvider,
  );
}

class _$StemWorkerHeartbeatCodec extends ModelCodec<$StemWorkerHeartbeat> {
  const _$StemWorkerHeartbeatCodec();
  @override
  Map<String, Object?> encode(
    $StemWorkerHeartbeat model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'worker_id': registry.encodeField(
        _$StemWorkerHeartbeatWorkerIdField,
        model.workerId,
      ),
      'namespace': registry.encodeField(
        _$StemWorkerHeartbeatNamespaceField,
        model.namespace,
      ),
      'timestamp': registry.encodeField(
        _$StemWorkerHeartbeatTimestampField,
        model.timestamp,
      ),
      'isolate_count': registry.encodeField(
        _$StemWorkerHeartbeatIsolateCountField,
        model.isolateCount,
      ),
      'inflight': registry.encodeField(
        _$StemWorkerHeartbeatInflightField,
        model.inflight,
      ),
      'queues': registry.encodeField(
        _$StemWorkerHeartbeatQueuesField,
        model.queues,
      ),
      'last_lease_renewal': registry.encodeField(
        _$StemWorkerHeartbeatLastLeaseRenewalField,
        model.lastLeaseRenewal,
      ),
      'version': registry.encodeField(
        _$StemWorkerHeartbeatVersionField,
        model.version,
      ),
      'extras': registry.encodeField(
        _$StemWorkerHeartbeatExtrasField,
        model.extras,
      ),
      'expires_at': registry.encodeField(
        _$StemWorkerHeartbeatExpiresAtField,
        model.expiresAt,
      ),
      if (model.hasAttribute('deleted_at'))
        'deleted_at': registry.encodeField(
          _$StemWorkerHeartbeatDeletedAtField,
          model.getAttribute<DateTime?>('deleted_at'),
        ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemWorkerHeartbeatCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemWorkerHeartbeatUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemWorkerHeartbeat decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemWorkerHeartbeatWorkerIdValue =
        registry.decodeField<String>(
          _$StemWorkerHeartbeatWorkerIdField,
          data['worker_id'],
        ) ??
        (throw StateError(
          'Field workerId on StemWorkerHeartbeat cannot be null.',
        ));
    final String stemWorkerHeartbeatNamespaceValue =
        registry.decodeField<String>(
          _$StemWorkerHeartbeatNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemWorkerHeartbeat cannot be null.',
        ));
    final DateTime stemWorkerHeartbeatTimestampValue =
        registry.decodeField<DateTime>(
          _$StemWorkerHeartbeatTimestampField,
          data['timestamp'],
        ) ??
        (throw StateError(
          'Field timestamp on StemWorkerHeartbeat cannot be null.',
        ));
    final int stemWorkerHeartbeatIsolateCountValue =
        registry.decodeField<int>(
          _$StemWorkerHeartbeatIsolateCountField,
          data['isolate_count'],
        ) ??
        (throw StateError(
          'Field isolateCount on StemWorkerHeartbeat cannot be null.',
        ));
    final int stemWorkerHeartbeatInflightValue =
        registry.decodeField<int>(
          _$StemWorkerHeartbeatInflightField,
          data['inflight'],
        ) ??
        (throw StateError(
          'Field inflight on StemWorkerHeartbeat cannot be null.',
        ));
    final Map<String, Object?> stemWorkerHeartbeatQueuesValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemWorkerHeartbeatQueuesField,
          data['queues'],
        ) ??
        (throw StateError(
          'Field queues on StemWorkerHeartbeat cannot be null.',
        ));
    final DateTime? stemWorkerHeartbeatLastLeaseRenewalValue = registry
        .decodeField<DateTime?>(
          _$StemWorkerHeartbeatLastLeaseRenewalField,
          data['last_lease_renewal'],
        );
    final String stemWorkerHeartbeatVersionValue =
        registry.decodeField<String>(
          _$StemWorkerHeartbeatVersionField,
          data['version'],
        ) ??
        (throw StateError(
          'Field version on StemWorkerHeartbeat cannot be null.',
        ));
    final Map<String, Object?> stemWorkerHeartbeatExtrasValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemWorkerHeartbeatExtrasField,
          data['extras'],
        ) ??
        (throw StateError(
          'Field extras on StemWorkerHeartbeat cannot be null.',
        ));
    final DateTime stemWorkerHeartbeatExpiresAtValue =
        registry.decodeField<DateTime>(
          _$StemWorkerHeartbeatExpiresAtField,
          data['expires_at'],
        ) ??
        (throw StateError(
          'Field expiresAt on StemWorkerHeartbeat cannot be null.',
        ));
    final DateTime? stemWorkerHeartbeatDeletedAtValue = registry
        .decodeField<DateTime?>(
          _$StemWorkerHeartbeatDeletedAtField,
          data['deleted_at'],
        );
    final DateTime? stemWorkerHeartbeatCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemWorkerHeartbeatCreatedAtField,
          data['created_at'],
        );
    final DateTime? stemWorkerHeartbeatUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemWorkerHeartbeatUpdatedAtField,
          data['updated_at'],
        );
    final model = $StemWorkerHeartbeat(
      workerId: stemWorkerHeartbeatWorkerIdValue,
      namespace: stemWorkerHeartbeatNamespaceValue,
      timestamp: stemWorkerHeartbeatTimestampValue,
      isolateCount: stemWorkerHeartbeatIsolateCountValue,
      inflight: stemWorkerHeartbeatInflightValue,
      queues: stemWorkerHeartbeatQueuesValue,
      version: stemWorkerHeartbeatVersionValue,
      extras: stemWorkerHeartbeatExtrasValue,
      expiresAt: stemWorkerHeartbeatExpiresAtValue,
      lastLeaseRenewal: stemWorkerHeartbeatLastLeaseRenewalValue,
    );
    model._attachOrmRuntimeMetadata({
      'worker_id': stemWorkerHeartbeatWorkerIdValue,
      'namespace': stemWorkerHeartbeatNamespaceValue,
      'timestamp': stemWorkerHeartbeatTimestampValue,
      'isolate_count': stemWorkerHeartbeatIsolateCountValue,
      'inflight': stemWorkerHeartbeatInflightValue,
      'queues': stemWorkerHeartbeatQueuesValue,
      'last_lease_renewal': stemWorkerHeartbeatLastLeaseRenewalValue,
      'version': stemWorkerHeartbeatVersionValue,
      'extras': stemWorkerHeartbeatExtrasValue,
      'expires_at': stemWorkerHeartbeatExpiresAtValue,
      if (data.containsKey('deleted_at'))
        'deleted_at': stemWorkerHeartbeatDeletedAtValue,
      if (data.containsKey('created_at'))
        'created_at': stemWorkerHeartbeatCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': stemWorkerHeartbeatUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemWorkerHeartbeat].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemWorkerHeartbeatInsertDto implements InsertDto<$StemWorkerHeartbeat> {
  const StemWorkerHeartbeatInsertDto({
    this.workerId,
    this.namespace,
    this.timestamp,
    this.isolateCount,
    this.inflight,
    this.queues,
    this.lastLeaseRenewal,
    this.version,
    this.extras,
    this.expiresAt,
  });
  final String? workerId;
  final String? namespace;
  final DateTime? timestamp;
  final int? isolateCount;
  final int? inflight;
  final Map<String, Object?>? queues;
  final DateTime? lastLeaseRenewal;
  final String? version;
  final Map<String, Object?>? extras;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (workerId != null) 'worker_id': workerId,
      if (namespace != null) 'namespace': namespace,
      if (timestamp != null) 'timestamp': timestamp,
      if (isolateCount != null) 'isolate_count': isolateCount,
      if (inflight != null) 'inflight': inflight,
      if (queues != null) 'queues': queues,
      if (lastLeaseRenewal != null) 'last_lease_renewal': lastLeaseRenewal,
      if (version != null) 'version': version,
      if (extras != null) 'extras': extras,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemWorkerHeartbeatInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkerHeartbeatInsertDtoCopyWithSentinel();
  StemWorkerHeartbeatInsertDto copyWith({
    Object? workerId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? timestamp = _copyWithSentinel,
    Object? isolateCount = _copyWithSentinel,
    Object? inflight = _copyWithSentinel,
    Object? queues = _copyWithSentinel,
    Object? lastLeaseRenewal = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? extras = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemWorkerHeartbeatInsertDto(
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      timestamp: identical(timestamp, _copyWithSentinel)
          ? this.timestamp
          : timestamp as DateTime?,
      isolateCount: identical(isolateCount, _copyWithSentinel)
          ? this.isolateCount
          : isolateCount as int?,
      inflight: identical(inflight, _copyWithSentinel)
          ? this.inflight
          : inflight as int?,
      queues: identical(queues, _copyWithSentinel)
          ? this.queues
          : queues as Map<String, Object?>?,
      lastLeaseRenewal: identical(lastLeaseRenewal, _copyWithSentinel)
          ? this.lastLeaseRenewal
          : lastLeaseRenewal as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as String?,
      extras: identical(extras, _copyWithSentinel)
          ? this.extras
          : extras as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemWorkerHeartbeatInsertDtoCopyWithSentinel {
  const _StemWorkerHeartbeatInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemWorkerHeartbeat].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemWorkerHeartbeatUpdateDto implements UpdateDto<$StemWorkerHeartbeat> {
  const StemWorkerHeartbeatUpdateDto({
    this.workerId,
    this.namespace,
    this.timestamp,
    this.isolateCount,
    this.inflight,
    this.queues,
    this.lastLeaseRenewal,
    this.version,
    this.extras,
    this.expiresAt,
  });
  final String? workerId;
  final String? namespace;
  final DateTime? timestamp;
  final int? isolateCount;
  final int? inflight;
  final Map<String, Object?>? queues;
  final DateTime? lastLeaseRenewal;
  final String? version;
  final Map<String, Object?>? extras;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (workerId != null) 'worker_id': workerId,
      if (namespace != null) 'namespace': namespace,
      if (timestamp != null) 'timestamp': timestamp,
      if (isolateCount != null) 'isolate_count': isolateCount,
      if (inflight != null) 'inflight': inflight,
      if (queues != null) 'queues': queues,
      if (lastLeaseRenewal != null) 'last_lease_renewal': lastLeaseRenewal,
      if (version != null) 'version': version,
      if (extras != null) 'extras': extras,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemWorkerHeartbeatUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkerHeartbeatUpdateDtoCopyWithSentinel();
  StemWorkerHeartbeatUpdateDto copyWith({
    Object? workerId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? timestamp = _copyWithSentinel,
    Object? isolateCount = _copyWithSentinel,
    Object? inflight = _copyWithSentinel,
    Object? queues = _copyWithSentinel,
    Object? lastLeaseRenewal = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? extras = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemWorkerHeartbeatUpdateDto(
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      timestamp: identical(timestamp, _copyWithSentinel)
          ? this.timestamp
          : timestamp as DateTime?,
      isolateCount: identical(isolateCount, _copyWithSentinel)
          ? this.isolateCount
          : isolateCount as int?,
      inflight: identical(inflight, _copyWithSentinel)
          ? this.inflight
          : inflight as int?,
      queues: identical(queues, _copyWithSentinel)
          ? this.queues
          : queues as Map<String, Object?>?,
      lastLeaseRenewal: identical(lastLeaseRenewal, _copyWithSentinel)
          ? this.lastLeaseRenewal
          : lastLeaseRenewal as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as String?,
      extras: identical(extras, _copyWithSentinel)
          ? this.extras
          : extras as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemWorkerHeartbeatUpdateDtoCopyWithSentinel {
  const _StemWorkerHeartbeatUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemWorkerHeartbeat].
///
/// All fields are nullable; intended for subset SELECTs.
class StemWorkerHeartbeatPartial
    implements PartialEntity<$StemWorkerHeartbeat> {
  const StemWorkerHeartbeatPartial({
    this.workerId,
    this.namespace,
    this.timestamp,
    this.isolateCount,
    this.inflight,
    this.queues,
    this.lastLeaseRenewal,
    this.version,
    this.extras,
    this.expiresAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemWorkerHeartbeatPartial.fromRow(Map<String, Object?> row) {
    return StemWorkerHeartbeatPartial(
      workerId: row['worker_id'] as String?,
      namespace: row['namespace'] as String?,
      timestamp: row['timestamp'] as DateTime?,
      isolateCount: row['isolate_count'] as int?,
      inflight: row['inflight'] as int?,
      queues: row['queues'] as Map<String, Object?>?,
      lastLeaseRenewal: row['last_lease_renewal'] as DateTime?,
      version: row['version'] as String?,
      extras: row['extras'] as Map<String, Object?>?,
      expiresAt: row['expires_at'] as DateTime?,
    );
  }

  final String? workerId;
  final String? namespace;
  final DateTime? timestamp;
  final int? isolateCount;
  final int? inflight;
  final Map<String, Object?>? queues;
  final DateTime? lastLeaseRenewal;
  final String? version;
  final Map<String, Object?>? extras;
  final DateTime? expiresAt;

  @override
  $StemWorkerHeartbeat toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? workerIdValue = workerId;
    if (workerIdValue == null) {
      throw StateError('Missing required field: workerId');
    }
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final DateTime? timestampValue = timestamp;
    if (timestampValue == null) {
      throw StateError('Missing required field: timestamp');
    }
    final int? isolateCountValue = isolateCount;
    if (isolateCountValue == null) {
      throw StateError('Missing required field: isolateCount');
    }
    final int? inflightValue = inflight;
    if (inflightValue == null) {
      throw StateError('Missing required field: inflight');
    }
    final Map<String, Object?>? queuesValue = queues;
    if (queuesValue == null) {
      throw StateError('Missing required field: queues');
    }
    final String? versionValue = version;
    if (versionValue == null) {
      throw StateError('Missing required field: version');
    }
    final Map<String, Object?>? extrasValue = extras;
    if (extrasValue == null) {
      throw StateError('Missing required field: extras');
    }
    final DateTime? expiresAtValue = expiresAt;
    if (expiresAtValue == null) {
      throw StateError('Missing required field: expiresAt');
    }
    return $StemWorkerHeartbeat(
      workerId: workerIdValue,
      namespace: namespaceValue,
      timestamp: timestampValue,
      isolateCount: isolateCountValue,
      inflight: inflightValue,
      queues: queuesValue,
      lastLeaseRenewal: lastLeaseRenewal,
      version: versionValue,
      extras: extrasValue,
      expiresAt: expiresAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (workerId != null) 'worker_id': workerId,
      if (namespace != null) 'namespace': namespace,
      if (timestamp != null) 'timestamp': timestamp,
      if (isolateCount != null) 'isolate_count': isolateCount,
      if (inflight != null) 'inflight': inflight,
      if (queues != null) 'queues': queues,
      if (lastLeaseRenewal != null) 'last_lease_renewal': lastLeaseRenewal,
      if (version != null) 'version': version,
      if (extras != null) 'extras': extras,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemWorkerHeartbeatPartialCopyWithSentinel _copyWithSentinel =
      _StemWorkerHeartbeatPartialCopyWithSentinel();
  StemWorkerHeartbeatPartial copyWith({
    Object? workerId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? timestamp = _copyWithSentinel,
    Object? isolateCount = _copyWithSentinel,
    Object? inflight = _copyWithSentinel,
    Object? queues = _copyWithSentinel,
    Object? lastLeaseRenewal = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? extras = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemWorkerHeartbeatPartial(
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      timestamp: identical(timestamp, _copyWithSentinel)
          ? this.timestamp
          : timestamp as DateTime?,
      isolateCount: identical(isolateCount, _copyWithSentinel)
          ? this.isolateCount
          : isolateCount as int?,
      inflight: identical(inflight, _copyWithSentinel)
          ? this.inflight
          : inflight as int?,
      queues: identical(queues, _copyWithSentinel)
          ? this.queues
          : queues as Map<String, Object?>?,
      lastLeaseRenewal: identical(lastLeaseRenewal, _copyWithSentinel)
          ? this.lastLeaseRenewal
          : lastLeaseRenewal as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as String?,
      extras: identical(extras, _copyWithSentinel)
          ? this.extras
          : extras as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemWorkerHeartbeatPartialCopyWithSentinel {
  const _StemWorkerHeartbeatPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemWorkerHeartbeat].
///
/// This class extends the user-defined [StemWorkerHeartbeat] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemWorkerHeartbeat extends StemWorkerHeartbeat
    with ModelAttributes, TimestampsTZImpl, SoftDeletesTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemWorkerHeartbeat].
  $StemWorkerHeartbeat({
    required String workerId,
    required String namespace,
    required DateTime timestamp,
    required int isolateCount,
    required int inflight,
    required Map<String, Object?> queues,
    required String version,
    required Map<String, Object?> extras,
    required DateTime expiresAt,
    DateTime? lastLeaseRenewal,
  }) : super(
         workerId: workerId,
         namespace: namespace,
         timestamp: timestamp,
         isolateCount: isolateCount,
         inflight: inflight,
         queues: queues,
         version: version,
         extras: extras,
         expiresAt: expiresAt,
         lastLeaseRenewal: lastLeaseRenewal,
       ) {
    _attachOrmRuntimeMetadata({
      'worker_id': workerId,
      'namespace': namespace,
      'timestamp': timestamp,
      'isolate_count': isolateCount,
      'inflight': inflight,
      'queues': queues,
      'last_lease_renewal': lastLeaseRenewal,
      'version': version,
      'extras': extras,
      'expires_at': expiresAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemWorkerHeartbeat.fromModel(StemWorkerHeartbeat model) {
    return $StemWorkerHeartbeat(
      workerId: model.workerId,
      namespace: model.namespace,
      timestamp: model.timestamp,
      isolateCount: model.isolateCount,
      inflight: model.inflight,
      queues: model.queues,
      lastLeaseRenewal: model.lastLeaseRenewal,
      version: model.version,
      extras: model.extras,
      expiresAt: model.expiresAt,
    );
  }

  $StemWorkerHeartbeat copyWith({
    String? workerId,
    String? namespace,
    DateTime? timestamp,
    int? isolateCount,
    int? inflight,
    Map<String, Object?>? queues,
    DateTime? lastLeaseRenewal,
    String? version,
    Map<String, Object?>? extras,
    DateTime? expiresAt,
  }) {
    return $StemWorkerHeartbeat(
      workerId: workerId ?? this.workerId,
      namespace: namespace ?? this.namespace,
      timestamp: timestamp ?? this.timestamp,
      isolateCount: isolateCount ?? this.isolateCount,
      inflight: inflight ?? this.inflight,
      queues: queues ?? this.queues,
      lastLeaseRenewal: lastLeaseRenewal ?? this.lastLeaseRenewal,
      version: version ?? this.version,
      extras: extras ?? this.extras,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemWorkerHeartbeat fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkerHeartbeatDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkerHeartbeatDefinition.toMap(this, registry: registry);

  /// Tracked getter for [workerId].
  @override
  String get workerId => getAttribute<String>('worker_id') ?? super.workerId;

  /// Tracked setter for [workerId].
  set workerId(String value) => setAttribute('worker_id', value);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [timestamp].
  @override
  DateTime get timestamp =>
      getAttribute<DateTime>('timestamp') ?? super.timestamp;

  /// Tracked setter for [timestamp].
  set timestamp(DateTime value) => setAttribute('timestamp', value);

  /// Tracked getter for [isolateCount].
  @override
  int get isolateCount =>
      getAttribute<int>('isolate_count') ?? super.isolateCount;

  /// Tracked setter for [isolateCount].
  set isolateCount(int value) => setAttribute('isolate_count', value);

  /// Tracked getter for [inflight].
  @override
  int get inflight => getAttribute<int>('inflight') ?? super.inflight;

  /// Tracked setter for [inflight].
  set inflight(int value) => setAttribute('inflight', value);

  /// Tracked getter for [queues].
  @override
  Map<String, Object?> get queues =>
      getAttribute<Map<String, Object?>>('queues') ?? super.queues;

  /// Tracked setter for [queues].
  set queues(Map<String, Object?> value) => setAttribute('queues', value);

  /// Tracked getter for [lastLeaseRenewal].
  @override
  DateTime? get lastLeaseRenewal =>
      getAttribute<DateTime?>('last_lease_renewal') ?? super.lastLeaseRenewal;

  /// Tracked setter for [lastLeaseRenewal].
  set lastLeaseRenewal(DateTime? value) =>
      setAttribute('last_lease_renewal', value);

  /// Tracked getter for [version].
  @override
  String get version => getAttribute<String>('version') ?? super.version;

  /// Tracked setter for [version].
  set version(String value) => setAttribute('version', value);

  /// Tracked getter for [extras].
  @override
  Map<String, Object?> get extras =>
      getAttribute<Map<String, Object?>>('extras') ?? super.extras;

  /// Tracked setter for [extras].
  set extras(Map<String, Object?> value) => setAttribute('extras', value);

  /// Tracked getter for [expiresAt].
  @override
  DateTime get expiresAt =>
      getAttribute<DateTime>('expires_at') ?? super.expiresAt;

  /// Tracked setter for [expiresAt].
  set expiresAt(DateTime value) => setAttribute('expires_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemWorkerHeartbeatDefinition);
  }
}

class _StemWorkerHeartbeatCopyWithSentinel {
  const _StemWorkerHeartbeatCopyWithSentinel();
}

extension StemWorkerHeartbeatOrmExtension on StemWorkerHeartbeat {
  static const _StemWorkerHeartbeatCopyWithSentinel _copyWithSentinel =
      _StemWorkerHeartbeatCopyWithSentinel();
  StemWorkerHeartbeat copyWith({
    Object? workerId = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? timestamp = _copyWithSentinel,
    Object? isolateCount = _copyWithSentinel,
    Object? inflight = _copyWithSentinel,
    Object? queues = _copyWithSentinel,
    Object? version = _copyWithSentinel,
    Object? extras = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? lastLeaseRenewal = _copyWithSentinel,
  }) {
    return StemWorkerHeartbeat(
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      timestamp: identical(timestamp, _copyWithSentinel)
          ? this.timestamp
          : timestamp as DateTime,
      isolateCount: identical(isolateCount, _copyWithSentinel)
          ? this.isolateCount
          : isolateCount as int,
      inflight: identical(inflight, _copyWithSentinel)
          ? this.inflight
          : inflight as int,
      queues: identical(queues, _copyWithSentinel)
          ? this.queues
          : queues as Map<String, Object?>,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as String,
      extras: identical(extras, _copyWithSentinel)
          ? this.extras
          : extras as Map<String, Object?>,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime,
      lastLeaseRenewal: identical(lastLeaseRenewal, _copyWithSentinel)
          ? this.lastLeaseRenewal
          : lastLeaseRenewal as DateTime?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkerHeartbeatDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemWorkerHeartbeat fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkerHeartbeatDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemWorkerHeartbeat;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemWorkerHeartbeat toTracked() {
    return $StemWorkerHeartbeat.fromModel(this);
  }
}

extension StemWorkerHeartbeatPredicateFields
    on PredicateBuilder<StemWorkerHeartbeat> {
  PredicateField<StemWorkerHeartbeat, String> get workerId =>
      PredicateField<StemWorkerHeartbeat, String>(this, 'workerId');
  PredicateField<StemWorkerHeartbeat, String> get namespace =>
      PredicateField<StemWorkerHeartbeat, String>(this, 'namespace');
  PredicateField<StemWorkerHeartbeat, DateTime> get timestamp =>
      PredicateField<StemWorkerHeartbeat, DateTime>(this, 'timestamp');
  PredicateField<StemWorkerHeartbeat, int> get isolateCount =>
      PredicateField<StemWorkerHeartbeat, int>(this, 'isolateCount');
  PredicateField<StemWorkerHeartbeat, int> get inflight =>
      PredicateField<StemWorkerHeartbeat, int>(this, 'inflight');
  PredicateField<StemWorkerHeartbeat, Map<String, Object?>> get queues =>
      PredicateField<StemWorkerHeartbeat, Map<String, Object?>>(this, 'queues');
  PredicateField<StemWorkerHeartbeat, DateTime?> get lastLeaseRenewal =>
      PredicateField<StemWorkerHeartbeat, DateTime?>(this, 'lastLeaseRenewal');
  PredicateField<StemWorkerHeartbeat, String> get version =>
      PredicateField<StemWorkerHeartbeat, String>(this, 'version');
  PredicateField<StemWorkerHeartbeat, Map<String, Object?>> get extras =>
      PredicateField<StemWorkerHeartbeat, Map<String, Object?>>(this, 'extras');
  PredicateField<StemWorkerHeartbeat, DateTime> get expiresAt =>
      PredicateField<StemWorkerHeartbeat, DateTime>(this, 'expiresAt');
}

void registerStemWorkerHeartbeatEventHandlers(EventBus bus) {
  // No event handlers registered for StemWorkerHeartbeat.
}
