// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class StemQueueJobs extends Table with TableInfo<StemQueueJobs, StemQueueJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StemQueueJobs(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _queueMeta = const VerificationMeta('queue');
  late final GeneratedColumn<String> queue = GeneratedColumn<String>(
    'queue',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _envelopeMeta = const VerificationMeta(
    'envelope',
  );
  late final GeneratedColumn<String> envelope = GeneratedColumn<String>(
    'envelope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _attemptMeta = const VerificationMeta(
    'attempt',
  );
  late final GeneratedColumn<int> attempt = GeneratedColumn<int>(
    'attempt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _maxRetriesMeta = const VerificationMeta(
    'maxRetries',
  );
  late final GeneratedColumn<int> maxRetries = GeneratedColumn<int>(
    'max_retries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _notBeforeMeta = const VerificationMeta(
    'notBefore',
  );
  late final GeneratedColumn<int> notBefore = GeneratedColumn<int>(
    'not_before',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lockedAtMeta = const VerificationMeta(
    'lockedAt',
  );
  late final GeneratedColumn<int> lockedAt = GeneratedColumn<int>(
    'locked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lockedUntilMeta = const VerificationMeta(
    'lockedUntil',
  );
  late final GeneratedColumn<int> lockedUntil = GeneratedColumn<int>(
    'locked_until',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lockedByMeta = const VerificationMeta(
    'lockedBy',
  );
  late final GeneratedColumn<String> lockedBy = GeneratedColumn<String>(
    'locked_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    queue,
    envelope,
    attempt,
    maxRetries,
    priority,
    notBefore,
    lockedAt,
    lockedUntil,
    lockedBy,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stem_queue_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<StemQueueJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('queue')) {
      context.handle(
        _queueMeta,
        queue.isAcceptableOrUnknown(data['queue']!, _queueMeta),
      );
    } else if (isInserting) {
      context.missing(_queueMeta);
    }
    if (data.containsKey('envelope')) {
      context.handle(
        _envelopeMeta,
        envelope.isAcceptableOrUnknown(data['envelope']!, _envelopeMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeMeta);
    }
    if (data.containsKey('attempt')) {
      context.handle(
        _attemptMeta,
        attempt.isAcceptableOrUnknown(data['attempt']!, _attemptMeta),
      );
    }
    if (data.containsKey('max_retries')) {
      context.handle(
        _maxRetriesMeta,
        maxRetries.isAcceptableOrUnknown(data['max_retries']!, _maxRetriesMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('not_before')) {
      context.handle(
        _notBeforeMeta,
        notBefore.isAcceptableOrUnknown(data['not_before']!, _notBeforeMeta),
      );
    }
    if (data.containsKey('locked_at')) {
      context.handle(
        _lockedAtMeta,
        lockedAt.isAcceptableOrUnknown(data['locked_at']!, _lockedAtMeta),
      );
    }
    if (data.containsKey('locked_until')) {
      context.handle(
        _lockedUntilMeta,
        lockedUntil.isAcceptableOrUnknown(
          data['locked_until']!,
          _lockedUntilMeta,
        ),
      );
    }
    if (data.containsKey('locked_by')) {
      context.handle(
        _lockedByMeta,
        lockedBy.isAcceptableOrUnknown(data['locked_by']!, _lockedByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StemQueueJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StemQueueJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      queue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue'],
      )!,
      envelope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope'],
      )!,
      attempt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt'],
      )!,
      maxRetries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_retries'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      notBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}not_before'],
      ),
      lockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}locked_at'],
      ),
      lockedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}locked_until'],
      ),
      lockedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locked_by'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  StemQueueJobs createAlias(String alias) {
    return StemQueueJobs(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StemQueueJob extends DataClass implements Insertable<StemQueueJob> {
  final String id;
  final String queue;
  final String envelope;
  final int attempt;
  final int maxRetries;
  final int priority;
  final int? notBefore;
  final int? lockedAt;
  final int? lockedUntil;
  final String? lockedBy;
  final int createdAt;
  final int updatedAt;
  const StemQueueJob({
    required this.id,
    required this.queue,
    required this.envelope,
    required this.attempt,
    required this.maxRetries,
    required this.priority,
    this.notBefore,
    this.lockedAt,
    this.lockedUntil,
    this.lockedBy,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['queue'] = Variable<String>(queue);
    map['envelope'] = Variable<String>(envelope);
    map['attempt'] = Variable<int>(attempt);
    map['max_retries'] = Variable<int>(maxRetries);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || notBefore != null) {
      map['not_before'] = Variable<int>(notBefore);
    }
    if (!nullToAbsent || lockedAt != null) {
      map['locked_at'] = Variable<int>(lockedAt);
    }
    if (!nullToAbsent || lockedUntil != null) {
      map['locked_until'] = Variable<int>(lockedUntil);
    }
    if (!nullToAbsent || lockedBy != null) {
      map['locked_by'] = Variable<String>(lockedBy);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  StemQueueJobsCompanion toCompanion(bool nullToAbsent) {
    return StemQueueJobsCompanion(
      id: Value(id),
      queue: Value(queue),
      envelope: Value(envelope),
      attempt: Value(attempt),
      maxRetries: Value(maxRetries),
      priority: Value(priority),
      notBefore: notBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(notBefore),
      lockedAt: lockedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedAt),
      lockedUntil: lockedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedUntil),
      lockedBy: lockedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedBy),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StemQueueJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StemQueueJob(
      id: serializer.fromJson<String>(json['id']),
      queue: serializer.fromJson<String>(json['queue']),
      envelope: serializer.fromJson<String>(json['envelope']),
      attempt: serializer.fromJson<int>(json['attempt']),
      maxRetries: serializer.fromJson<int>(json['max_retries']),
      priority: serializer.fromJson<int>(json['priority']),
      notBefore: serializer.fromJson<int?>(json['not_before']),
      lockedAt: serializer.fromJson<int?>(json['locked_at']),
      lockedUntil: serializer.fromJson<int?>(json['locked_until']),
      lockedBy: serializer.fromJson<String?>(json['locked_by']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'queue': serializer.toJson<String>(queue),
      'envelope': serializer.toJson<String>(envelope),
      'attempt': serializer.toJson<int>(attempt),
      'max_retries': serializer.toJson<int>(maxRetries),
      'priority': serializer.toJson<int>(priority),
      'not_before': serializer.toJson<int?>(notBefore),
      'locked_at': serializer.toJson<int?>(lockedAt),
      'locked_until': serializer.toJson<int?>(lockedUntil),
      'locked_by': serializer.toJson<String?>(lockedBy),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  StemQueueJob copyWith({
    String? id,
    String? queue,
    String? envelope,
    int? attempt,
    int? maxRetries,
    int? priority,
    Value<int?> notBefore = const Value.absent(),
    Value<int?> lockedAt = const Value.absent(),
    Value<int?> lockedUntil = const Value.absent(),
    Value<String?> lockedBy = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => StemQueueJob(
    id: id ?? this.id,
    queue: queue ?? this.queue,
    envelope: envelope ?? this.envelope,
    attempt: attempt ?? this.attempt,
    maxRetries: maxRetries ?? this.maxRetries,
    priority: priority ?? this.priority,
    notBefore: notBefore.present ? notBefore.value : this.notBefore,
    lockedAt: lockedAt.present ? lockedAt.value : this.lockedAt,
    lockedUntil: lockedUntil.present ? lockedUntil.value : this.lockedUntil,
    lockedBy: lockedBy.present ? lockedBy.value : this.lockedBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StemQueueJob copyWithCompanion(StemQueueJobsCompanion data) {
    return StemQueueJob(
      id: data.id.present ? data.id.value : this.id,
      queue: data.queue.present ? data.queue.value : this.queue,
      envelope: data.envelope.present ? data.envelope.value : this.envelope,
      attempt: data.attempt.present ? data.attempt.value : this.attempt,
      maxRetries: data.maxRetries.present
          ? data.maxRetries.value
          : this.maxRetries,
      priority: data.priority.present ? data.priority.value : this.priority,
      notBefore: data.notBefore.present ? data.notBefore.value : this.notBefore,
      lockedAt: data.lockedAt.present ? data.lockedAt.value : this.lockedAt,
      lockedUntil: data.lockedUntil.present
          ? data.lockedUntil.value
          : this.lockedUntil,
      lockedBy: data.lockedBy.present ? data.lockedBy.value : this.lockedBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StemQueueJob(')
          ..write('id: $id, ')
          ..write('queue: $queue, ')
          ..write('envelope: $envelope, ')
          ..write('attempt: $attempt, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('priority: $priority, ')
          ..write('notBefore: $notBefore, ')
          ..write('lockedAt: $lockedAt, ')
          ..write('lockedUntil: $lockedUntil, ')
          ..write('lockedBy: $lockedBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    queue,
    envelope,
    attempt,
    maxRetries,
    priority,
    notBefore,
    lockedAt,
    lockedUntil,
    lockedBy,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StemQueueJob &&
          other.id == this.id &&
          other.queue == this.queue &&
          other.envelope == this.envelope &&
          other.attempt == this.attempt &&
          other.maxRetries == this.maxRetries &&
          other.priority == this.priority &&
          other.notBefore == this.notBefore &&
          other.lockedAt == this.lockedAt &&
          other.lockedUntil == this.lockedUntil &&
          other.lockedBy == this.lockedBy &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StemQueueJobsCompanion extends UpdateCompanion<StemQueueJob> {
  final Value<String> id;
  final Value<String> queue;
  final Value<String> envelope;
  final Value<int> attempt;
  final Value<int> maxRetries;
  final Value<int> priority;
  final Value<int?> notBefore;
  final Value<int?> lockedAt;
  final Value<int?> lockedUntil;
  final Value<String?> lockedBy;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const StemQueueJobsCompanion({
    this.id = const Value.absent(),
    this.queue = const Value.absent(),
    this.envelope = const Value.absent(),
    this.attempt = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.priority = const Value.absent(),
    this.notBefore = const Value.absent(),
    this.lockedAt = const Value.absent(),
    this.lockedUntil = const Value.absent(),
    this.lockedBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StemQueueJobsCompanion.insert({
    required String id,
    required String queue,
    required String envelope,
    this.attempt = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.priority = const Value.absent(),
    this.notBefore = const Value.absent(),
    this.lockedAt = const Value.absent(),
    this.lockedUntil = const Value.absent(),
    this.lockedBy = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       queue = Value(queue),
       envelope = Value(envelope),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<StemQueueJob> custom({
    Expression<String>? id,
    Expression<String>? queue,
    Expression<String>? envelope,
    Expression<int>? attempt,
    Expression<int>? maxRetries,
    Expression<int>? priority,
    Expression<int>? notBefore,
    Expression<int>? lockedAt,
    Expression<int>? lockedUntil,
    Expression<String>? lockedBy,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (attempt != null) 'attempt': attempt,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (priority != null) 'priority': priority,
      if (notBefore != null) 'not_before': notBefore,
      if (lockedAt != null) 'locked_at': lockedAt,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (lockedBy != null) 'locked_by': lockedBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StemQueueJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? queue,
    Value<String>? envelope,
    Value<int>? attempt,
    Value<int>? maxRetries,
    Value<int>? priority,
    Value<int?>? notBefore,
    Value<int?>? lockedAt,
    Value<int?>? lockedUntil,
    Value<String?>? lockedBy,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return StemQueueJobsCompanion(
      id: id ?? this.id,
      queue: queue ?? this.queue,
      envelope: envelope ?? this.envelope,
      attempt: attempt ?? this.attempt,
      maxRetries: maxRetries ?? this.maxRetries,
      priority: priority ?? this.priority,
      notBefore: notBefore ?? this.notBefore,
      lockedAt: lockedAt ?? this.lockedAt,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      lockedBy: lockedBy ?? this.lockedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (queue.present) {
      map['queue'] = Variable<String>(queue.value);
    }
    if (envelope.present) {
      map['envelope'] = Variable<String>(envelope.value);
    }
    if (attempt.present) {
      map['attempt'] = Variable<int>(attempt.value);
    }
    if (maxRetries.present) {
      map['max_retries'] = Variable<int>(maxRetries.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (notBefore.present) {
      map['not_before'] = Variable<int>(notBefore.value);
    }
    if (lockedAt.present) {
      map['locked_at'] = Variable<int>(lockedAt.value);
    }
    if (lockedUntil.present) {
      map['locked_until'] = Variable<int>(lockedUntil.value);
    }
    if (lockedBy.present) {
      map['locked_by'] = Variable<String>(lockedBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StemQueueJobsCompanion(')
          ..write('id: $id, ')
          ..write('queue: $queue, ')
          ..write('envelope: $envelope, ')
          ..write('attempt: $attempt, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('priority: $priority, ')
          ..write('notBefore: $notBefore, ')
          ..write('lockedAt: $lockedAt, ')
          ..write('lockedUntil: $lockedUntil, ')
          ..write('lockedBy: $lockedBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StemDeadLetters extends Table
    with TableInfo<StemDeadLetters, StemDeadLetter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StemDeadLetters(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _queueMeta = const VerificationMeta('queue');
  late final GeneratedColumn<String> queue = GeneratedColumn<String>(
    'queue',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _envelopeMeta = const VerificationMeta(
    'envelope',
  );
  late final GeneratedColumn<String> envelope = GeneratedColumn<String>(
    'envelope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _deadAtMeta = const VerificationMeta('deadAt');
  late final GeneratedColumn<int> deadAt = GeneratedColumn<int>(
    'dead_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    queue,
    envelope,
    reason,
    meta,
    deadAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stem_dead_letters';
  @override
  VerificationContext validateIntegrity(
    Insertable<StemDeadLetter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('queue')) {
      context.handle(
        _queueMeta,
        queue.isAcceptableOrUnknown(data['queue']!, _queueMeta),
      );
    } else if (isInserting) {
      context.missing(_queueMeta);
    }
    if (data.containsKey('envelope')) {
      context.handle(
        _envelopeMeta,
        envelope.isAcceptableOrUnknown(data['envelope']!, _envelopeMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    }
    if (data.containsKey('dead_at')) {
      context.handle(
        _deadAtMeta,
        deadAt.isAcceptableOrUnknown(data['dead_at']!, _deadAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deadAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StemDeadLetter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StemDeadLetter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      queue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue'],
      )!,
      envelope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      ),
      deadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dead_at'],
      )!,
    );
  }

  @override
  StemDeadLetters createAlias(String alias) {
    return StemDeadLetters(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StemDeadLetter extends DataClass implements Insertable<StemDeadLetter> {
  final String id;
  final String queue;
  final String envelope;
  final String? reason;
  final String? meta;
  final int deadAt;
  const StemDeadLetter({
    required this.id,
    required this.queue,
    required this.envelope,
    this.reason,
    this.meta,
    required this.deadAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['queue'] = Variable<String>(queue);
    map['envelope'] = Variable<String>(envelope);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || meta != null) {
      map['meta'] = Variable<String>(meta);
    }
    map['dead_at'] = Variable<int>(deadAt);
    return map;
  }

  StemDeadLettersCompanion toCompanion(bool nullToAbsent) {
    return StemDeadLettersCompanion(
      id: Value(id),
      queue: Value(queue),
      envelope: Value(envelope),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      meta: meta == null && nullToAbsent ? const Value.absent() : Value(meta),
      deadAt: Value(deadAt),
    );
  }

  factory StemDeadLetter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StemDeadLetter(
      id: serializer.fromJson<String>(json['id']),
      queue: serializer.fromJson<String>(json['queue']),
      envelope: serializer.fromJson<String>(json['envelope']),
      reason: serializer.fromJson<String?>(json['reason']),
      meta: serializer.fromJson<String?>(json['meta']),
      deadAt: serializer.fromJson<int>(json['dead_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'queue': serializer.toJson<String>(queue),
      'envelope': serializer.toJson<String>(envelope),
      'reason': serializer.toJson<String?>(reason),
      'meta': serializer.toJson<String?>(meta),
      'dead_at': serializer.toJson<int>(deadAt),
    };
  }

  StemDeadLetter copyWith({
    String? id,
    String? queue,
    String? envelope,
    Value<String?> reason = const Value.absent(),
    Value<String?> meta = const Value.absent(),
    int? deadAt,
  }) => StemDeadLetter(
    id: id ?? this.id,
    queue: queue ?? this.queue,
    envelope: envelope ?? this.envelope,
    reason: reason.present ? reason.value : this.reason,
    meta: meta.present ? meta.value : this.meta,
    deadAt: deadAt ?? this.deadAt,
  );
  StemDeadLetter copyWithCompanion(StemDeadLettersCompanion data) {
    return StemDeadLetter(
      id: data.id.present ? data.id.value : this.id,
      queue: data.queue.present ? data.queue.value : this.queue,
      envelope: data.envelope.present ? data.envelope.value : this.envelope,
      reason: data.reason.present ? data.reason.value : this.reason,
      meta: data.meta.present ? data.meta.value : this.meta,
      deadAt: data.deadAt.present ? data.deadAt.value : this.deadAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StemDeadLetter(')
          ..write('id: $id, ')
          ..write('queue: $queue, ')
          ..write('envelope: $envelope, ')
          ..write('reason: $reason, ')
          ..write('meta: $meta, ')
          ..write('deadAt: $deadAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, queue, envelope, reason, meta, deadAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StemDeadLetter &&
          other.id == this.id &&
          other.queue == this.queue &&
          other.envelope == this.envelope &&
          other.reason == this.reason &&
          other.meta == this.meta &&
          other.deadAt == this.deadAt);
}

class StemDeadLettersCompanion extends UpdateCompanion<StemDeadLetter> {
  final Value<String> id;
  final Value<String> queue;
  final Value<String> envelope;
  final Value<String?> reason;
  final Value<String?> meta;
  final Value<int> deadAt;
  final Value<int> rowid;
  const StemDeadLettersCompanion({
    this.id = const Value.absent(),
    this.queue = const Value.absent(),
    this.envelope = const Value.absent(),
    this.reason = const Value.absent(),
    this.meta = const Value.absent(),
    this.deadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StemDeadLettersCompanion.insert({
    required String id,
    required String queue,
    required String envelope,
    this.reason = const Value.absent(),
    this.meta = const Value.absent(),
    required int deadAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       queue = Value(queue),
       envelope = Value(envelope),
       deadAt = Value(deadAt);
  static Insertable<StemDeadLetter> custom({
    Expression<String>? id,
    Expression<String>? queue,
    Expression<String>? envelope,
    Expression<String>? reason,
    Expression<String>? meta,
    Expression<int>? deadAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (reason != null) 'reason': reason,
      if (meta != null) 'meta': meta,
      if (deadAt != null) 'dead_at': deadAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StemDeadLettersCompanion copyWith({
    Value<String>? id,
    Value<String>? queue,
    Value<String>? envelope,
    Value<String?>? reason,
    Value<String?>? meta,
    Value<int>? deadAt,
    Value<int>? rowid,
  }) {
    return StemDeadLettersCompanion(
      id: id ?? this.id,
      queue: queue ?? this.queue,
      envelope: envelope ?? this.envelope,
      reason: reason ?? this.reason,
      meta: meta ?? this.meta,
      deadAt: deadAt ?? this.deadAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (queue.present) {
      map['queue'] = Variable<String>(queue.value);
    }
    if (envelope.present) {
      map['envelope'] = Variable<String>(envelope.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (deadAt.present) {
      map['dead_at'] = Variable<int>(deadAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StemDeadLettersCompanion(')
          ..write('id: $id, ')
          ..write('queue: $queue, ')
          ..write('envelope: $envelope, ')
          ..write('reason: $reason, ')
          ..write('meta: $meta, ')
          ..write('deadAt: $deadAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StemTaskResults extends Table
    with TableInfo<StemTaskResults, StemTaskResult> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StemTaskResults(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _attemptMeta = const VerificationMeta(
    'attempt',
  );
  late final GeneratedColumn<int> attempt = GeneratedColumn<int>(
    'attempt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'{}\'',
    defaultValue: const CustomExpression('\'{}\''),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    state,
    payload,
    error,
    attempt,
    meta,
    expiresAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stem_task_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<StemTaskResult> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('attempt')) {
      context.handle(
        _attemptMeta,
        attempt.isAcceptableOrUnknown(data['attempt']!, _attemptMeta),
      );
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StemTaskResult map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StemTaskResult(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      attempt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt'],
      )!,
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  StemTaskResults createAlias(String alias) {
    return StemTaskResults(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StemTaskResult extends DataClass implements Insertable<StemTaskResult> {
  final String id;
  final String state;
  final String? payload;
  final String? error;
  final int attempt;
  final String meta;
  final int expiresAt;
  final int createdAt;
  final int updatedAt;
  const StemTaskResult({
    required this.id,
    required this.state,
    this.payload,
    this.error,
    required this.attempt,
    required this.meta,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['attempt'] = Variable<int>(attempt);
    map['meta'] = Variable<String>(meta);
    map['expires_at'] = Variable<int>(expiresAt);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  StemTaskResultsCompanion toCompanion(bool nullToAbsent) {
    return StemTaskResultsCompanion(
      id: Value(id),
      state: Value(state),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      attempt: Value(attempt),
      meta: Value(meta),
      expiresAt: Value(expiresAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StemTaskResult.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StemTaskResult(
      id: serializer.fromJson<String>(json['id']),
      state: serializer.fromJson<String>(json['state']),
      payload: serializer.fromJson<String?>(json['payload']),
      error: serializer.fromJson<String?>(json['error']),
      attempt: serializer.fromJson<int>(json['attempt']),
      meta: serializer.fromJson<String>(json['meta']),
      expiresAt: serializer.fromJson<int>(json['expires_at']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'state': serializer.toJson<String>(state),
      'payload': serializer.toJson<String?>(payload),
      'error': serializer.toJson<String?>(error),
      'attempt': serializer.toJson<int>(attempt),
      'meta': serializer.toJson<String>(meta),
      'expires_at': serializer.toJson<int>(expiresAt),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  StemTaskResult copyWith({
    String? id,
    String? state,
    Value<String?> payload = const Value.absent(),
    Value<String?> error = const Value.absent(),
    int? attempt,
    String? meta,
    int? expiresAt,
    int? createdAt,
    int? updatedAt,
  }) => StemTaskResult(
    id: id ?? this.id,
    state: state ?? this.state,
    payload: payload.present ? payload.value : this.payload,
    error: error.present ? error.value : this.error,
    attempt: attempt ?? this.attempt,
    meta: meta ?? this.meta,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StemTaskResult copyWithCompanion(StemTaskResultsCompanion data) {
    return StemTaskResult(
      id: data.id.present ? data.id.value : this.id,
      state: data.state.present ? data.state.value : this.state,
      payload: data.payload.present ? data.payload.value : this.payload,
      error: data.error.present ? data.error.value : this.error,
      attempt: data.attempt.present ? data.attempt.value : this.attempt,
      meta: data.meta.present ? data.meta.value : this.meta,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StemTaskResult(')
          ..write('id: $id, ')
          ..write('state: $state, ')
          ..write('payload: $payload, ')
          ..write('error: $error, ')
          ..write('attempt: $attempt, ')
          ..write('meta: $meta, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    state,
    payload,
    error,
    attempt,
    meta,
    expiresAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StemTaskResult &&
          other.id == this.id &&
          other.state == this.state &&
          other.payload == this.payload &&
          other.error == this.error &&
          other.attempt == this.attempt &&
          other.meta == this.meta &&
          other.expiresAt == this.expiresAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StemTaskResultsCompanion extends UpdateCompanion<StemTaskResult> {
  final Value<String> id;
  final Value<String> state;
  final Value<String?> payload;
  final Value<String?> error;
  final Value<int> attempt;
  final Value<String> meta;
  final Value<int> expiresAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const StemTaskResultsCompanion({
    this.id = const Value.absent(),
    this.state = const Value.absent(),
    this.payload = const Value.absent(),
    this.error = const Value.absent(),
    this.attempt = const Value.absent(),
    this.meta = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StemTaskResultsCompanion.insert({
    required String id,
    required String state,
    this.payload = const Value.absent(),
    this.error = const Value.absent(),
    this.attempt = const Value.absent(),
    this.meta = const Value.absent(),
    required int expiresAt,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       state = Value(state),
       expiresAt = Value(expiresAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<StemTaskResult> custom({
    Expression<String>? id,
    Expression<String>? state,
    Expression<String>? payload,
    Expression<String>? error,
    Expression<int>? attempt,
    Expression<String>? meta,
    Expression<int>? expiresAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StemTaskResultsCompanion copyWith({
    Value<String>? id,
    Value<String>? state,
    Value<String?>? payload,
    Value<String?>? error,
    Value<int>? attempt,
    Value<String>? meta,
    Value<int>? expiresAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return StemTaskResultsCompanion(
      id: id ?? this.id,
      state: state ?? this.state,
      payload: payload ?? this.payload,
      error: error ?? this.error,
      attempt: attempt ?? this.attempt,
      meta: meta ?? this.meta,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (attempt.present) {
      map['attempt'] = Variable<int>(attempt.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StemTaskResultsCompanion(')
          ..write('id: $id, ')
          ..write('state: $state, ')
          ..write('payload: $payload, ')
          ..write('error: $error, ')
          ..write('attempt: $attempt, ')
          ..write('meta: $meta, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StemGroups extends Table with TableInfo<StemGroups, StemGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StemGroups(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _expectedMeta = const VerificationMeta(
    'expected',
  );
  late final GeneratedColumn<int> expected = GeneratedColumn<int>(
    'expected',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'{}\'',
    defaultValue: const CustomExpression('\'{}\''),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    expected,
    meta,
    expiresAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stem_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<StemGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('expected')) {
      context.handle(
        _expectedMeta,
        expected.isAcceptableOrUnknown(data['expected']!, _expectedMeta),
      );
    } else if (isInserting) {
      context.missing(_expectedMeta);
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StemGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StemGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      expected: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected'],
      )!,
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  StemGroups createAlias(String alias) {
    return StemGroups(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StemGroup extends DataClass implements Insertable<StemGroup> {
  final String id;
  final int expected;
  final String meta;
  final int expiresAt;
  final int createdAt;
  const StemGroup({
    required this.id,
    required this.expected,
    required this.meta,
    required this.expiresAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['expected'] = Variable<int>(expected);
    map['meta'] = Variable<String>(meta);
    map['expires_at'] = Variable<int>(expiresAt);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  StemGroupsCompanion toCompanion(bool nullToAbsent) {
    return StemGroupsCompanion(
      id: Value(id),
      expected: Value(expected),
      meta: Value(meta),
      expiresAt: Value(expiresAt),
      createdAt: Value(createdAt),
    );
  }

  factory StemGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StemGroup(
      id: serializer.fromJson<String>(json['id']),
      expected: serializer.fromJson<int>(json['expected']),
      meta: serializer.fromJson<String>(json['meta']),
      expiresAt: serializer.fromJson<int>(json['expires_at']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'expected': serializer.toJson<int>(expected),
      'meta': serializer.toJson<String>(meta),
      'expires_at': serializer.toJson<int>(expiresAt),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  StemGroup copyWith({
    String? id,
    int? expected,
    String? meta,
    int? expiresAt,
    int? createdAt,
  }) => StemGroup(
    id: id ?? this.id,
    expected: expected ?? this.expected,
    meta: meta ?? this.meta,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
  );
  StemGroup copyWithCompanion(StemGroupsCompanion data) {
    return StemGroup(
      id: data.id.present ? data.id.value : this.id,
      expected: data.expected.present ? data.expected.value : this.expected,
      meta: data.meta.present ? data.meta.value : this.meta,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StemGroup(')
          ..write('id: $id, ')
          ..write('expected: $expected, ')
          ..write('meta: $meta, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, expected, meta, expiresAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StemGroup &&
          other.id == this.id &&
          other.expected == this.expected &&
          other.meta == this.meta &&
          other.expiresAt == this.expiresAt &&
          other.createdAt == this.createdAt);
}

class StemGroupsCompanion extends UpdateCompanion<StemGroup> {
  final Value<String> id;
  final Value<int> expected;
  final Value<String> meta;
  final Value<int> expiresAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const StemGroupsCompanion({
    this.id = const Value.absent(),
    this.expected = const Value.absent(),
    this.meta = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StemGroupsCompanion.insert({
    required String id,
    required int expected,
    this.meta = const Value.absent(),
    required int expiresAt,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       expected = Value(expected),
       expiresAt = Value(expiresAt),
       createdAt = Value(createdAt);
  static Insertable<StemGroup> custom({
    Expression<String>? id,
    Expression<int>? expected,
    Expression<String>? meta,
    Expression<int>? expiresAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StemGroupsCompanion copyWith({
    Value<String>? id,
    Value<int>? expected,
    Value<String>? meta,
    Value<int>? expiresAt,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return StemGroupsCompanion(
      id: id ?? this.id,
      expected: expected ?? this.expected,
      meta: meta ?? this.meta,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (expected.present) {
      map['expected'] = Variable<int>(expected.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StemGroupsCompanion(')
          ..write('id: $id, ')
          ..write('expected: $expected, ')
          ..write('meta: $meta, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StemGroupResults extends Table
    with TableInfo<StemGroupResults, StemGroupResult> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StemGroupResults(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _attemptMeta = const VerificationMeta(
    'attempt',
  );
  late final GeneratedColumn<int> attempt = GeneratedColumn<int>(
    'attempt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'{}\'',
    defaultValue: const CustomExpression('\'{}\''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    taskId,
    state,
    payload,
    error,
    attempt,
    meta,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stem_group_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<StemGroupResult> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('attempt')) {
      context.handle(
        _attemptMeta,
        attempt.isAcceptableOrUnknown(data['attempt']!, _attemptMeta),
      );
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, taskId};
  @override
  StemGroupResult map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StemGroupResult(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      attempt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt'],
      )!,
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  StemGroupResults createAlias(String alias) {
    return StemGroupResults(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(group_id, task_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class StemGroupResult extends DataClass implements Insertable<StemGroupResult> {
  final String groupId;
  final String taskId;
  final String state;
  final String? payload;
  final String? error;
  final int attempt;
  final String meta;
  final int createdAt;
  const StemGroupResult({
    required this.groupId,
    required this.taskId,
    required this.state,
    this.payload,
    this.error,
    required this.attempt,
    required this.meta,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['task_id'] = Variable<String>(taskId);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['attempt'] = Variable<int>(attempt);
    map['meta'] = Variable<String>(meta);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  StemGroupResultsCompanion toCompanion(bool nullToAbsent) {
    return StemGroupResultsCompanion(
      groupId: Value(groupId),
      taskId: Value(taskId),
      state: Value(state),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      attempt: Value(attempt),
      meta: Value(meta),
      createdAt: Value(createdAt),
    );
  }

  factory StemGroupResult.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StemGroupResult(
      groupId: serializer.fromJson<String>(json['group_id']),
      taskId: serializer.fromJson<String>(json['task_id']),
      state: serializer.fromJson<String>(json['state']),
      payload: serializer.fromJson<String?>(json['payload']),
      error: serializer.fromJson<String?>(json['error']),
      attempt: serializer.fromJson<int>(json['attempt']),
      meta: serializer.fromJson<String>(json['meta']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'group_id': serializer.toJson<String>(groupId),
      'task_id': serializer.toJson<String>(taskId),
      'state': serializer.toJson<String>(state),
      'payload': serializer.toJson<String?>(payload),
      'error': serializer.toJson<String?>(error),
      'attempt': serializer.toJson<int>(attempt),
      'meta': serializer.toJson<String>(meta),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  StemGroupResult copyWith({
    String? groupId,
    String? taskId,
    String? state,
    Value<String?> payload = const Value.absent(),
    Value<String?> error = const Value.absent(),
    int? attempt,
    String? meta,
    int? createdAt,
  }) => StemGroupResult(
    groupId: groupId ?? this.groupId,
    taskId: taskId ?? this.taskId,
    state: state ?? this.state,
    payload: payload.present ? payload.value : this.payload,
    error: error.present ? error.value : this.error,
    attempt: attempt ?? this.attempt,
    meta: meta ?? this.meta,
    createdAt: createdAt ?? this.createdAt,
  );
  StemGroupResult copyWithCompanion(StemGroupResultsCompanion data) {
    return StemGroupResult(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      state: data.state.present ? data.state.value : this.state,
      payload: data.payload.present ? data.payload.value : this.payload,
      error: data.error.present ? data.error.value : this.error,
      attempt: data.attempt.present ? data.attempt.value : this.attempt,
      meta: data.meta.present ? data.meta.value : this.meta,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StemGroupResult(')
          ..write('groupId: $groupId, ')
          ..write('taskId: $taskId, ')
          ..write('state: $state, ')
          ..write('payload: $payload, ')
          ..write('error: $error, ')
          ..write('attempt: $attempt, ')
          ..write('meta: $meta, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    taskId,
    state,
    payload,
    error,
    attempt,
    meta,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StemGroupResult &&
          other.groupId == this.groupId &&
          other.taskId == this.taskId &&
          other.state == this.state &&
          other.payload == this.payload &&
          other.error == this.error &&
          other.attempt == this.attempt &&
          other.meta == this.meta &&
          other.createdAt == this.createdAt);
}

class StemGroupResultsCompanion extends UpdateCompanion<StemGroupResult> {
  final Value<String> groupId;
  final Value<String> taskId;
  final Value<String> state;
  final Value<String?> payload;
  final Value<String?> error;
  final Value<int> attempt;
  final Value<String> meta;
  final Value<int> createdAt;
  final Value<int> rowid;
  const StemGroupResultsCompanion({
    this.groupId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.state = const Value.absent(),
    this.payload = const Value.absent(),
    this.error = const Value.absent(),
    this.attempt = const Value.absent(),
    this.meta = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StemGroupResultsCompanion.insert({
    required String groupId,
    required String taskId,
    required String state,
    this.payload = const Value.absent(),
    this.error = const Value.absent(),
    this.attempt = const Value.absent(),
    this.meta = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       taskId = Value(taskId),
       state = Value(state),
       createdAt = Value(createdAt);
  static Insertable<StemGroupResult> custom({
    Expression<String>? groupId,
    Expression<String>? taskId,
    Expression<String>? state,
    Expression<String>? payload,
    Expression<String>? error,
    Expression<int>? attempt,
    Expression<String>? meta,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (taskId != null) 'task_id': taskId,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StemGroupResultsCompanion copyWith({
    Value<String>? groupId,
    Value<String>? taskId,
    Value<String>? state,
    Value<String?>? payload,
    Value<String?>? error,
    Value<int>? attempt,
    Value<String>? meta,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return StemGroupResultsCompanion(
      groupId: groupId ?? this.groupId,
      taskId: taskId ?? this.taskId,
      state: state ?? this.state,
      payload: payload ?? this.payload,
      error: error ?? this.error,
      attempt: attempt ?? this.attempt,
      meta: meta ?? this.meta,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (attempt.present) {
      map['attempt'] = Variable<int>(attempt.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StemGroupResultsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('taskId: $taskId, ')
          ..write('state: $state, ')
          ..write('payload: $payload, ')
          ..write('error: $error, ')
          ..write('attempt: $attempt, ')
          ..write('meta: $meta, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StemWorkerHeartbeats extends Table
    with TableInfo<StemWorkerHeartbeats, StemWorkerHeartbeat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StemWorkerHeartbeats(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workerIdMeta = const VerificationMeta(
    'workerId',
  );
  late final GeneratedColumn<String> workerId = GeneratedColumn<String>(
    'worker_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _namespaceMeta = const VerificationMeta(
    'namespace',
  );
  late final GeneratedColumn<String> namespace = GeneratedColumn<String>(
    'namespace',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _isolateCountMeta = const VerificationMeta(
    'isolateCount',
  );
  late final GeneratedColumn<int> isolateCount = GeneratedColumn<int>(
    'isolate_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _inflightMeta = const VerificationMeta(
    'inflight',
  );
  late final GeneratedColumn<int> inflight = GeneratedColumn<int>(
    'inflight',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _queuesMeta = const VerificationMeta('queues');
  late final GeneratedColumn<String> queues = GeneratedColumn<String>(
    'queues',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _lastLeaseRenewalMeta = const VerificationMeta(
    'lastLeaseRenewal',
  );
  late final GeneratedColumn<int> lastLeaseRenewal = GeneratedColumn<int>(
    'last_lease_renewal',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _extrasMeta = const VerificationMeta('extras');
  late final GeneratedColumn<String> extras = GeneratedColumn<String>(
    'extras',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'{}\'',
    defaultValue: const CustomExpression('\'{}\''),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    workerId,
    namespace,
    timestamp,
    isolateCount,
    inflight,
    queues,
    lastLeaseRenewal,
    version,
    extras,
    expiresAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stem_worker_heartbeats';
  @override
  VerificationContext validateIntegrity(
    Insertable<StemWorkerHeartbeat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('worker_id')) {
      context.handle(
        _workerIdMeta,
        workerId.isAcceptableOrUnknown(data['worker_id']!, _workerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workerIdMeta);
    }
    if (data.containsKey('namespace')) {
      context.handle(
        _namespaceMeta,
        namespace.isAcceptableOrUnknown(data['namespace']!, _namespaceMeta),
      );
    } else if (isInserting) {
      context.missing(_namespaceMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('isolate_count')) {
      context.handle(
        _isolateCountMeta,
        isolateCount.isAcceptableOrUnknown(
          data['isolate_count']!,
          _isolateCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isolateCountMeta);
    }
    if (data.containsKey('inflight')) {
      context.handle(
        _inflightMeta,
        inflight.isAcceptableOrUnknown(data['inflight']!, _inflightMeta),
      );
    } else if (isInserting) {
      context.missing(_inflightMeta);
    }
    if (data.containsKey('queues')) {
      context.handle(
        _queuesMeta,
        queues.isAcceptableOrUnknown(data['queues']!, _queuesMeta),
      );
    }
    if (data.containsKey('last_lease_renewal')) {
      context.handle(
        _lastLeaseRenewalMeta,
        lastLeaseRenewal.isAcceptableOrUnknown(
          data['last_lease_renewal']!,
          _lastLeaseRenewalMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('extras')) {
      context.handle(
        _extrasMeta,
        extras.isAcceptableOrUnknown(data['extras']!, _extrasMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workerId};
  @override
  StemWorkerHeartbeat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StemWorkerHeartbeat(
      workerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}worker_id'],
      )!,
      namespace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}namespace'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      isolateCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}isolate_count'],
      )!,
      inflight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}inflight'],
      )!,
      queues: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queues'],
      )!,
      lastLeaseRenewal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_lease_renewal'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      extras: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extras'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  StemWorkerHeartbeats createAlias(String alias) {
    return StemWorkerHeartbeats(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StemWorkerHeartbeat extends DataClass
    implements Insertable<StemWorkerHeartbeat> {
  final String workerId;
  final String namespace;
  final int timestamp;
  final int isolateCount;
  final int inflight;
  final String queues;
  final int? lastLeaseRenewal;
  final String version;
  final String extras;
  final int expiresAt;
  final int createdAt;
  const StemWorkerHeartbeat({
    required this.workerId,
    required this.namespace,
    required this.timestamp,
    required this.isolateCount,
    required this.inflight,
    required this.queues,
    this.lastLeaseRenewal,
    required this.version,
    required this.extras,
    required this.expiresAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['worker_id'] = Variable<String>(workerId);
    map['namespace'] = Variable<String>(namespace);
    map['timestamp'] = Variable<int>(timestamp);
    map['isolate_count'] = Variable<int>(isolateCount);
    map['inflight'] = Variable<int>(inflight);
    map['queues'] = Variable<String>(queues);
    if (!nullToAbsent || lastLeaseRenewal != null) {
      map['last_lease_renewal'] = Variable<int>(lastLeaseRenewal);
    }
    map['version'] = Variable<String>(version);
    map['extras'] = Variable<String>(extras);
    map['expires_at'] = Variable<int>(expiresAt);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  StemWorkerHeartbeatsCompanion toCompanion(bool nullToAbsent) {
    return StemWorkerHeartbeatsCompanion(
      workerId: Value(workerId),
      namespace: Value(namespace),
      timestamp: Value(timestamp),
      isolateCount: Value(isolateCount),
      inflight: Value(inflight),
      queues: Value(queues),
      lastLeaseRenewal: lastLeaseRenewal == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLeaseRenewal),
      version: Value(version),
      extras: Value(extras),
      expiresAt: Value(expiresAt),
      createdAt: Value(createdAt),
    );
  }

  factory StemWorkerHeartbeat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StemWorkerHeartbeat(
      workerId: serializer.fromJson<String>(json['worker_id']),
      namespace: serializer.fromJson<String>(json['namespace']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      isolateCount: serializer.fromJson<int>(json['isolate_count']),
      inflight: serializer.fromJson<int>(json['inflight']),
      queues: serializer.fromJson<String>(json['queues']),
      lastLeaseRenewal: serializer.fromJson<int?>(json['last_lease_renewal']),
      version: serializer.fromJson<String>(json['version']),
      extras: serializer.fromJson<String>(json['extras']),
      expiresAt: serializer.fromJson<int>(json['expires_at']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'worker_id': serializer.toJson<String>(workerId),
      'namespace': serializer.toJson<String>(namespace),
      'timestamp': serializer.toJson<int>(timestamp),
      'isolate_count': serializer.toJson<int>(isolateCount),
      'inflight': serializer.toJson<int>(inflight),
      'queues': serializer.toJson<String>(queues),
      'last_lease_renewal': serializer.toJson<int?>(lastLeaseRenewal),
      'version': serializer.toJson<String>(version),
      'extras': serializer.toJson<String>(extras),
      'expires_at': serializer.toJson<int>(expiresAt),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  StemWorkerHeartbeat copyWith({
    String? workerId,
    String? namespace,
    int? timestamp,
    int? isolateCount,
    int? inflight,
    String? queues,
    Value<int?> lastLeaseRenewal = const Value.absent(),
    String? version,
    String? extras,
    int? expiresAt,
    int? createdAt,
  }) => StemWorkerHeartbeat(
    workerId: workerId ?? this.workerId,
    namespace: namespace ?? this.namespace,
    timestamp: timestamp ?? this.timestamp,
    isolateCount: isolateCount ?? this.isolateCount,
    inflight: inflight ?? this.inflight,
    queues: queues ?? this.queues,
    lastLeaseRenewal: lastLeaseRenewal.present
        ? lastLeaseRenewal.value
        : this.lastLeaseRenewal,
    version: version ?? this.version,
    extras: extras ?? this.extras,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
  );
  StemWorkerHeartbeat copyWithCompanion(StemWorkerHeartbeatsCompanion data) {
    return StemWorkerHeartbeat(
      workerId: data.workerId.present ? data.workerId.value : this.workerId,
      namespace: data.namespace.present ? data.namespace.value : this.namespace,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      isolateCount: data.isolateCount.present
          ? data.isolateCount.value
          : this.isolateCount,
      inflight: data.inflight.present ? data.inflight.value : this.inflight,
      queues: data.queues.present ? data.queues.value : this.queues,
      lastLeaseRenewal: data.lastLeaseRenewal.present
          ? data.lastLeaseRenewal.value
          : this.lastLeaseRenewal,
      version: data.version.present ? data.version.value : this.version,
      extras: data.extras.present ? data.extras.value : this.extras,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StemWorkerHeartbeat(')
          ..write('workerId: $workerId, ')
          ..write('namespace: $namespace, ')
          ..write('timestamp: $timestamp, ')
          ..write('isolateCount: $isolateCount, ')
          ..write('inflight: $inflight, ')
          ..write('queues: $queues, ')
          ..write('lastLeaseRenewal: $lastLeaseRenewal, ')
          ..write('version: $version, ')
          ..write('extras: $extras, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workerId,
    namespace,
    timestamp,
    isolateCount,
    inflight,
    queues,
    lastLeaseRenewal,
    version,
    extras,
    expiresAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StemWorkerHeartbeat &&
          other.workerId == this.workerId &&
          other.namespace == this.namespace &&
          other.timestamp == this.timestamp &&
          other.isolateCount == this.isolateCount &&
          other.inflight == this.inflight &&
          other.queues == this.queues &&
          other.lastLeaseRenewal == this.lastLeaseRenewal &&
          other.version == this.version &&
          other.extras == this.extras &&
          other.expiresAt == this.expiresAt &&
          other.createdAt == this.createdAt);
}

class StemWorkerHeartbeatsCompanion
    extends UpdateCompanion<StemWorkerHeartbeat> {
  final Value<String> workerId;
  final Value<String> namespace;
  final Value<int> timestamp;
  final Value<int> isolateCount;
  final Value<int> inflight;
  final Value<String> queues;
  final Value<int?> lastLeaseRenewal;
  final Value<String> version;
  final Value<String> extras;
  final Value<int> expiresAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const StemWorkerHeartbeatsCompanion({
    this.workerId = const Value.absent(),
    this.namespace = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.isolateCount = const Value.absent(),
    this.inflight = const Value.absent(),
    this.queues = const Value.absent(),
    this.lastLeaseRenewal = const Value.absent(),
    this.version = const Value.absent(),
    this.extras = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StemWorkerHeartbeatsCompanion.insert({
    required String workerId,
    required String namespace,
    required int timestamp,
    required int isolateCount,
    required int inflight,
    this.queues = const Value.absent(),
    this.lastLeaseRenewal = const Value.absent(),
    required String version,
    this.extras = const Value.absent(),
    required int expiresAt,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : workerId = Value(workerId),
       namespace = Value(namespace),
       timestamp = Value(timestamp),
       isolateCount = Value(isolateCount),
       inflight = Value(inflight),
       version = Value(version),
       expiresAt = Value(expiresAt),
       createdAt = Value(createdAt);
  static Insertable<StemWorkerHeartbeat> custom({
    Expression<String>? workerId,
    Expression<String>? namespace,
    Expression<int>? timestamp,
    Expression<int>? isolateCount,
    Expression<int>? inflight,
    Expression<String>? queues,
    Expression<int>? lastLeaseRenewal,
    Expression<String>? version,
    Expression<String>? extras,
    Expression<int>? expiresAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
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
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StemWorkerHeartbeatsCompanion copyWith({
    Value<String>? workerId,
    Value<String>? namespace,
    Value<int>? timestamp,
    Value<int>? isolateCount,
    Value<int>? inflight,
    Value<String>? queues,
    Value<int?>? lastLeaseRenewal,
    Value<String>? version,
    Value<String>? extras,
    Value<int>? expiresAt,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return StemWorkerHeartbeatsCompanion(
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
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workerId.present) {
      map['worker_id'] = Variable<String>(workerId.value);
    }
    if (namespace.present) {
      map['namespace'] = Variable<String>(namespace.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (isolateCount.present) {
      map['isolate_count'] = Variable<int>(isolateCount.value);
    }
    if (inflight.present) {
      map['inflight'] = Variable<int>(inflight.value);
    }
    if (queues.present) {
      map['queues'] = Variable<String>(queues.value);
    }
    if (lastLeaseRenewal.present) {
      map['last_lease_renewal'] = Variable<int>(lastLeaseRenewal.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (extras.present) {
      map['extras'] = Variable<String>(extras.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StemWorkerHeartbeatsCompanion(')
          ..write('workerId: $workerId, ')
          ..write('namespace: $namespace, ')
          ..write('timestamp: $timestamp, ')
          ..write('isolateCount: $isolateCount, ')
          ..write('inflight: $inflight, ')
          ..write('queues: $queues, ')
          ..write('lastLeaseRenewal: $lastLeaseRenewal, ')
          ..write('version: $version, ')
          ..write('extras: $extras, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$StemSqliteDatabase extends GeneratedDatabase {
  _$StemSqliteDatabase(QueryExecutor e) : super(e);
  $StemSqliteDatabaseManager get managers => $StemSqliteDatabaseManager(this);
  late final StemQueueJobs stemQueueJobs = StemQueueJobs(this);
  late final Index stemQueueJobsQueuePriorityIdx = Index(
    'stem_queue_jobs_queue_priority_idx',
    'CREATE INDEX stem_queue_jobs_queue_priority_idx ON stem_queue_jobs (queue, priority DESC, created_at)',
  );
  late final Index stemQueueJobsNotBeforeIdx = Index(
    'stem_queue_jobs_not_before_idx',
    'CREATE INDEX stem_queue_jobs_not_before_idx ON stem_queue_jobs (not_before)',
  );
  late final StemDeadLetters stemDeadLetters = StemDeadLetters(this);
  late final Index stemDeadLettersQueueDeadAtIdx = Index(
    'stem_dead_letters_queue_dead_at_idx',
    'CREATE INDEX stem_dead_letters_queue_dead_at_idx ON stem_dead_letters (queue, dead_at DESC)',
  );
  late final StemTaskResults stemTaskResults = StemTaskResults(this);
  late final Index stemTaskResultsExpiresAtIdx = Index(
    'stem_task_results_expires_at_idx',
    'CREATE INDEX stem_task_results_expires_at_idx ON stem_task_results (expires_at)',
  );
  late final StemGroups stemGroups = StemGroups(this);
  late final Index stemGroupsExpiresAtIdx = Index(
    'stem_groups_expires_at_idx',
    'CREATE INDEX stem_groups_expires_at_idx ON stem_groups (expires_at)',
  );
  late final StemGroupResults stemGroupResults = StemGroupResults(this);
  late final Index stemGroupResultsGroupIdx = Index(
    'stem_group_results_group_idx',
    'CREATE INDEX stem_group_results_group_idx ON stem_group_results (group_id)',
  );
  late final StemWorkerHeartbeats stemWorkerHeartbeats = StemWorkerHeartbeats(
    this,
  );
  late final Index stemWorkerHeartbeatsExpiresAtIdx = Index(
    'stem_worker_heartbeats_expires_at_idx',
    'CREATE INDEX stem_worker_heartbeats_expires_at_idx ON stem_worker_heartbeats (expires_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    stemQueueJobs,
    stemQueueJobsQueuePriorityIdx,
    stemQueueJobsNotBeforeIdx,
    stemDeadLetters,
    stemDeadLettersQueueDeadAtIdx,
    stemTaskResults,
    stemTaskResultsExpiresAtIdx,
    stemGroups,
    stemGroupsExpiresAtIdx,
    stemGroupResults,
    stemGroupResultsGroupIdx,
    stemWorkerHeartbeats,
    stemWorkerHeartbeatsExpiresAtIdx,
  ];
}

typedef $StemQueueJobsCreateCompanionBuilder =
    StemQueueJobsCompanion Function({
      required String id,
      required String queue,
      required String envelope,
      Value<int> attempt,
      Value<int> maxRetries,
      Value<int> priority,
      Value<int?> notBefore,
      Value<int?> lockedAt,
      Value<int?> lockedUntil,
      Value<String?> lockedBy,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $StemQueueJobsUpdateCompanionBuilder =
    StemQueueJobsCompanion Function({
      Value<String> id,
      Value<String> queue,
      Value<String> envelope,
      Value<int> attempt,
      Value<int> maxRetries,
      Value<int> priority,
      Value<int?> notBefore,
      Value<int?> lockedAt,
      Value<int?> lockedUntil,
      Value<String?> lockedBy,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $StemQueueJobsFilterComposer
    extends Composer<_$StemSqliteDatabase, StemQueueJobs> {
  $StemQueueJobsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queue => $composableBuilder(
    column: $table.queue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get envelope => $composableBuilder(
    column: $table.envelope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notBefore => $composableBuilder(
    column: $table.notBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lockedAt => $composableBuilder(
    column: $table.lockedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lockedBy => $composableBuilder(
    column: $table.lockedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $StemQueueJobsOrderingComposer
    extends Composer<_$StemSqliteDatabase, StemQueueJobs> {
  $StemQueueJobsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queue => $composableBuilder(
    column: $table.queue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get envelope => $composableBuilder(
    column: $table.envelope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notBefore => $composableBuilder(
    column: $table.notBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lockedAt => $composableBuilder(
    column: $table.lockedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lockedBy => $composableBuilder(
    column: $table.lockedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StemQueueJobsAnnotationComposer
    extends Composer<_$StemSqliteDatabase, StemQueueJobs> {
  $StemQueueJobsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get queue =>
      $composableBuilder(column: $table.queue, builder: (column) => column);

  GeneratedColumn<String> get envelope =>
      $composableBuilder(column: $table.envelope, builder: (column) => column);

  GeneratedColumn<int> get attempt =>
      $composableBuilder(column: $table.attempt, builder: (column) => column);

  GeneratedColumn<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get notBefore =>
      $composableBuilder(column: $table.notBefore, builder: (column) => column);

  GeneratedColumn<int> get lockedAt =>
      $composableBuilder(column: $table.lockedAt, builder: (column) => column);

  GeneratedColumn<int> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lockedBy =>
      $composableBuilder(column: $table.lockedBy, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $StemQueueJobsTableManager
    extends
        RootTableManager<
          _$StemSqliteDatabase,
          StemQueueJobs,
          StemQueueJob,
          $StemQueueJobsFilterComposer,
          $StemQueueJobsOrderingComposer,
          $StemQueueJobsAnnotationComposer,
          $StemQueueJobsCreateCompanionBuilder,
          $StemQueueJobsUpdateCompanionBuilder,
          (
            StemQueueJob,
            BaseReferences<_$StemSqliteDatabase, StemQueueJobs, StemQueueJob>,
          ),
          StemQueueJob,
          PrefetchHooks Function()
        > {
  $StemQueueJobsTableManager(_$StemSqliteDatabase db, StemQueueJobs table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StemQueueJobsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StemQueueJobsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StemQueueJobsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> queue = const Value.absent(),
                Value<String> envelope = const Value.absent(),
                Value<int> attempt = const Value.absent(),
                Value<int> maxRetries = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int?> notBefore = const Value.absent(),
                Value<int?> lockedAt = const Value.absent(),
                Value<int?> lockedUntil = const Value.absent(),
                Value<String?> lockedBy = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StemQueueJobsCompanion(
                id: id,
                queue: queue,
                envelope: envelope,
                attempt: attempt,
                maxRetries: maxRetries,
                priority: priority,
                notBefore: notBefore,
                lockedAt: lockedAt,
                lockedUntil: lockedUntil,
                lockedBy: lockedBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String queue,
                required String envelope,
                Value<int> attempt = const Value.absent(),
                Value<int> maxRetries = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int?> notBefore = const Value.absent(),
                Value<int?> lockedAt = const Value.absent(),
                Value<int?> lockedUntil = const Value.absent(),
                Value<String?> lockedBy = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => StemQueueJobsCompanion.insert(
                id: id,
                queue: queue,
                envelope: envelope,
                attempt: attempt,
                maxRetries: maxRetries,
                priority: priority,
                notBefore: notBefore,
                lockedAt: lockedAt,
                lockedUntil: lockedUntil,
                lockedBy: lockedBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StemQueueJobsProcessedTableManager =
    ProcessedTableManager<
      _$StemSqliteDatabase,
      StemQueueJobs,
      StemQueueJob,
      $StemQueueJobsFilterComposer,
      $StemQueueJobsOrderingComposer,
      $StemQueueJobsAnnotationComposer,
      $StemQueueJobsCreateCompanionBuilder,
      $StemQueueJobsUpdateCompanionBuilder,
      (
        StemQueueJob,
        BaseReferences<_$StemSqliteDatabase, StemQueueJobs, StemQueueJob>,
      ),
      StemQueueJob,
      PrefetchHooks Function()
    >;
typedef $StemDeadLettersCreateCompanionBuilder =
    StemDeadLettersCompanion Function({
      required String id,
      required String queue,
      required String envelope,
      Value<String?> reason,
      Value<String?> meta,
      required int deadAt,
      Value<int> rowid,
    });
typedef $StemDeadLettersUpdateCompanionBuilder =
    StemDeadLettersCompanion Function({
      Value<String> id,
      Value<String> queue,
      Value<String> envelope,
      Value<String?> reason,
      Value<String?> meta,
      Value<int> deadAt,
      Value<int> rowid,
    });

class $StemDeadLettersFilterComposer
    extends Composer<_$StemSqliteDatabase, StemDeadLetters> {
  $StemDeadLettersFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queue => $composableBuilder(
    column: $table.queue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get envelope => $composableBuilder(
    column: $table.envelope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deadAt => $composableBuilder(
    column: $table.deadAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $StemDeadLettersOrderingComposer
    extends Composer<_$StemSqliteDatabase, StemDeadLetters> {
  $StemDeadLettersOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queue => $composableBuilder(
    column: $table.queue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get envelope => $composableBuilder(
    column: $table.envelope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deadAt => $composableBuilder(
    column: $table.deadAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StemDeadLettersAnnotationComposer
    extends Composer<_$StemSqliteDatabase, StemDeadLetters> {
  $StemDeadLettersAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get queue =>
      $composableBuilder(column: $table.queue, builder: (column) => column);

  GeneratedColumn<String> get envelope =>
      $composableBuilder(column: $table.envelope, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);

  GeneratedColumn<int> get deadAt =>
      $composableBuilder(column: $table.deadAt, builder: (column) => column);
}

class $StemDeadLettersTableManager
    extends
        RootTableManager<
          _$StemSqliteDatabase,
          StemDeadLetters,
          StemDeadLetter,
          $StemDeadLettersFilterComposer,
          $StemDeadLettersOrderingComposer,
          $StemDeadLettersAnnotationComposer,
          $StemDeadLettersCreateCompanionBuilder,
          $StemDeadLettersUpdateCompanionBuilder,
          (
            StemDeadLetter,
            BaseReferences<
              _$StemSqliteDatabase,
              StemDeadLetters,
              StemDeadLetter
            >,
          ),
          StemDeadLetter,
          PrefetchHooks Function()
        > {
  $StemDeadLettersTableManager(_$StemSqliteDatabase db, StemDeadLetters table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StemDeadLettersFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StemDeadLettersOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StemDeadLettersAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> queue = const Value.absent(),
                Value<String> envelope = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<String?> meta = const Value.absent(),
                Value<int> deadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StemDeadLettersCompanion(
                id: id,
                queue: queue,
                envelope: envelope,
                reason: reason,
                meta: meta,
                deadAt: deadAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String queue,
                required String envelope,
                Value<String?> reason = const Value.absent(),
                Value<String?> meta = const Value.absent(),
                required int deadAt,
                Value<int> rowid = const Value.absent(),
              }) => StemDeadLettersCompanion.insert(
                id: id,
                queue: queue,
                envelope: envelope,
                reason: reason,
                meta: meta,
                deadAt: deadAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StemDeadLettersProcessedTableManager =
    ProcessedTableManager<
      _$StemSqliteDatabase,
      StemDeadLetters,
      StemDeadLetter,
      $StemDeadLettersFilterComposer,
      $StemDeadLettersOrderingComposer,
      $StemDeadLettersAnnotationComposer,
      $StemDeadLettersCreateCompanionBuilder,
      $StemDeadLettersUpdateCompanionBuilder,
      (
        StemDeadLetter,
        BaseReferences<_$StemSqliteDatabase, StemDeadLetters, StemDeadLetter>,
      ),
      StemDeadLetter,
      PrefetchHooks Function()
    >;
typedef $StemTaskResultsCreateCompanionBuilder =
    StemTaskResultsCompanion Function({
      required String id,
      required String state,
      Value<String?> payload,
      Value<String?> error,
      Value<int> attempt,
      Value<String> meta,
      required int expiresAt,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $StemTaskResultsUpdateCompanionBuilder =
    StemTaskResultsCompanion Function({
      Value<String> id,
      Value<String> state,
      Value<String?> payload,
      Value<String?> error,
      Value<int> attempt,
      Value<String> meta,
      Value<int> expiresAt,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $StemTaskResultsFilterComposer
    extends Composer<_$StemSqliteDatabase, StemTaskResults> {
  $StemTaskResultsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $StemTaskResultsOrderingComposer
    extends Composer<_$StemSqliteDatabase, StemTaskResults> {
  $StemTaskResultsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StemTaskResultsAnnotationComposer
    extends Composer<_$StemSqliteDatabase, StemTaskResults> {
  $StemTaskResultsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get attempt =>
      $composableBuilder(column: $table.attempt, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $StemTaskResultsTableManager
    extends
        RootTableManager<
          _$StemSqliteDatabase,
          StemTaskResults,
          StemTaskResult,
          $StemTaskResultsFilterComposer,
          $StemTaskResultsOrderingComposer,
          $StemTaskResultsAnnotationComposer,
          $StemTaskResultsCreateCompanionBuilder,
          $StemTaskResultsUpdateCompanionBuilder,
          (
            StemTaskResult,
            BaseReferences<
              _$StemSqliteDatabase,
              StemTaskResults,
              StemTaskResult
            >,
          ),
          StemTaskResult,
          PrefetchHooks Function()
        > {
  $StemTaskResultsTableManager(_$StemSqliteDatabase db, StemTaskResults table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StemTaskResultsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StemTaskResultsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StemTaskResultsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempt = const Value.absent(),
                Value<String> meta = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StemTaskResultsCompanion(
                id: id,
                state: state,
                payload: payload,
                error: error,
                attempt: attempt,
                meta: meta,
                expiresAt: expiresAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String state,
                Value<String?> payload = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempt = const Value.absent(),
                Value<String> meta = const Value.absent(),
                required int expiresAt,
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => StemTaskResultsCompanion.insert(
                id: id,
                state: state,
                payload: payload,
                error: error,
                attempt: attempt,
                meta: meta,
                expiresAt: expiresAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StemTaskResultsProcessedTableManager =
    ProcessedTableManager<
      _$StemSqliteDatabase,
      StemTaskResults,
      StemTaskResult,
      $StemTaskResultsFilterComposer,
      $StemTaskResultsOrderingComposer,
      $StemTaskResultsAnnotationComposer,
      $StemTaskResultsCreateCompanionBuilder,
      $StemTaskResultsUpdateCompanionBuilder,
      (
        StemTaskResult,
        BaseReferences<_$StemSqliteDatabase, StemTaskResults, StemTaskResult>,
      ),
      StemTaskResult,
      PrefetchHooks Function()
    >;
typedef $StemGroupsCreateCompanionBuilder =
    StemGroupsCompanion Function({
      required String id,
      required int expected,
      Value<String> meta,
      required int expiresAt,
      required int createdAt,
      Value<int> rowid,
    });
typedef $StemGroupsUpdateCompanionBuilder =
    StemGroupsCompanion Function({
      Value<String> id,
      Value<int> expected,
      Value<String> meta,
      Value<int> expiresAt,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $StemGroupsFilterComposer
    extends Composer<_$StemSqliteDatabase, StemGroups> {
  $StemGroupsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expected => $composableBuilder(
    column: $table.expected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $StemGroupsOrderingComposer
    extends Composer<_$StemSqliteDatabase, StemGroups> {
  $StemGroupsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expected => $composableBuilder(
    column: $table.expected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StemGroupsAnnotationComposer
    extends Composer<_$StemSqliteDatabase, StemGroups> {
  $StemGroupsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get expected =>
      $composableBuilder(column: $table.expected, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $StemGroupsTableManager
    extends
        RootTableManager<
          _$StemSqliteDatabase,
          StemGroups,
          StemGroup,
          $StemGroupsFilterComposer,
          $StemGroupsOrderingComposer,
          $StemGroupsAnnotationComposer,
          $StemGroupsCreateCompanionBuilder,
          $StemGroupsUpdateCompanionBuilder,
          (
            StemGroup,
            BaseReferences<_$StemSqliteDatabase, StemGroups, StemGroup>,
          ),
          StemGroup,
          PrefetchHooks Function()
        > {
  $StemGroupsTableManager(_$StemSqliteDatabase db, StemGroups table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StemGroupsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StemGroupsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StemGroupsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> expected = const Value.absent(),
                Value<String> meta = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StemGroupsCompanion(
                id: id,
                expected: expected,
                meta: meta,
                expiresAt: expiresAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int expected,
                Value<String> meta = const Value.absent(),
                required int expiresAt,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => StemGroupsCompanion.insert(
                id: id,
                expected: expected,
                meta: meta,
                expiresAt: expiresAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StemGroupsProcessedTableManager =
    ProcessedTableManager<
      _$StemSqliteDatabase,
      StemGroups,
      StemGroup,
      $StemGroupsFilterComposer,
      $StemGroupsOrderingComposer,
      $StemGroupsAnnotationComposer,
      $StemGroupsCreateCompanionBuilder,
      $StemGroupsUpdateCompanionBuilder,
      (StemGroup, BaseReferences<_$StemSqliteDatabase, StemGroups, StemGroup>),
      StemGroup,
      PrefetchHooks Function()
    >;
typedef $StemGroupResultsCreateCompanionBuilder =
    StemGroupResultsCompanion Function({
      required String groupId,
      required String taskId,
      required String state,
      Value<String?> payload,
      Value<String?> error,
      Value<int> attempt,
      Value<String> meta,
      required int createdAt,
      Value<int> rowid,
    });
typedef $StemGroupResultsUpdateCompanionBuilder =
    StemGroupResultsCompanion Function({
      Value<String> groupId,
      Value<String> taskId,
      Value<String> state,
      Value<String?> payload,
      Value<String?> error,
      Value<int> attempt,
      Value<String> meta,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $StemGroupResultsFilterComposer
    extends Composer<_$StemSqliteDatabase, StemGroupResults> {
  $StemGroupResultsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $StemGroupResultsOrderingComposer
    extends Composer<_$StemSqliteDatabase, StemGroupResults> {
  $StemGroupResultsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StemGroupResultsAnnotationComposer
    extends Composer<_$StemSqliteDatabase, StemGroupResults> {
  $StemGroupResultsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get attempt =>
      $composableBuilder(column: $table.attempt, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $StemGroupResultsTableManager
    extends
        RootTableManager<
          _$StemSqliteDatabase,
          StemGroupResults,
          StemGroupResult,
          $StemGroupResultsFilterComposer,
          $StemGroupResultsOrderingComposer,
          $StemGroupResultsAnnotationComposer,
          $StemGroupResultsCreateCompanionBuilder,
          $StemGroupResultsUpdateCompanionBuilder,
          (
            StemGroupResult,
            BaseReferences<
              _$StemSqliteDatabase,
              StemGroupResults,
              StemGroupResult
            >,
          ),
          StemGroupResult,
          PrefetchHooks Function()
        > {
  $StemGroupResultsTableManager(_$StemSqliteDatabase db, StemGroupResults table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StemGroupResultsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StemGroupResultsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StemGroupResultsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempt = const Value.absent(),
                Value<String> meta = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StemGroupResultsCompanion(
                groupId: groupId,
                taskId: taskId,
                state: state,
                payload: payload,
                error: error,
                attempt: attempt,
                meta: meta,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String taskId,
                required String state,
                Value<String?> payload = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempt = const Value.absent(),
                Value<String> meta = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => StemGroupResultsCompanion.insert(
                groupId: groupId,
                taskId: taskId,
                state: state,
                payload: payload,
                error: error,
                attempt: attempt,
                meta: meta,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StemGroupResultsProcessedTableManager =
    ProcessedTableManager<
      _$StemSqliteDatabase,
      StemGroupResults,
      StemGroupResult,
      $StemGroupResultsFilterComposer,
      $StemGroupResultsOrderingComposer,
      $StemGroupResultsAnnotationComposer,
      $StemGroupResultsCreateCompanionBuilder,
      $StemGroupResultsUpdateCompanionBuilder,
      (
        StemGroupResult,
        BaseReferences<_$StemSqliteDatabase, StemGroupResults, StemGroupResult>,
      ),
      StemGroupResult,
      PrefetchHooks Function()
    >;
typedef $StemWorkerHeartbeatsCreateCompanionBuilder =
    StemWorkerHeartbeatsCompanion Function({
      required String workerId,
      required String namespace,
      required int timestamp,
      required int isolateCount,
      required int inflight,
      Value<String> queues,
      Value<int?> lastLeaseRenewal,
      required String version,
      Value<String> extras,
      required int expiresAt,
      required int createdAt,
      Value<int> rowid,
    });
typedef $StemWorkerHeartbeatsUpdateCompanionBuilder =
    StemWorkerHeartbeatsCompanion Function({
      Value<String> workerId,
      Value<String> namespace,
      Value<int> timestamp,
      Value<int> isolateCount,
      Value<int> inflight,
      Value<String> queues,
      Value<int?> lastLeaseRenewal,
      Value<String> version,
      Value<String> extras,
      Value<int> expiresAt,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $StemWorkerHeartbeatsFilterComposer
    extends Composer<_$StemSqliteDatabase, StemWorkerHeartbeats> {
  $StemWorkerHeartbeatsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workerId => $composableBuilder(
    column: $table.workerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isolateCount => $composableBuilder(
    column: $table.isolateCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inflight => $composableBuilder(
    column: $table.inflight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queues => $composableBuilder(
    column: $table.queues,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastLeaseRenewal => $composableBuilder(
    column: $table.lastLeaseRenewal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extras => $composableBuilder(
    column: $table.extras,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $StemWorkerHeartbeatsOrderingComposer
    extends Composer<_$StemSqliteDatabase, StemWorkerHeartbeats> {
  $StemWorkerHeartbeatsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workerId => $composableBuilder(
    column: $table.workerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isolateCount => $composableBuilder(
    column: $table.isolateCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inflight => $composableBuilder(
    column: $table.inflight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queues => $composableBuilder(
    column: $table.queues,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastLeaseRenewal => $composableBuilder(
    column: $table.lastLeaseRenewal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extras => $composableBuilder(
    column: $table.extras,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StemWorkerHeartbeatsAnnotationComposer
    extends Composer<_$StemSqliteDatabase, StemWorkerHeartbeats> {
  $StemWorkerHeartbeatsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workerId =>
      $composableBuilder(column: $table.workerId, builder: (column) => column);

  GeneratedColumn<String> get namespace =>
      $composableBuilder(column: $table.namespace, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get isolateCount => $composableBuilder(
    column: $table.isolateCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get inflight =>
      $composableBuilder(column: $table.inflight, builder: (column) => column);

  GeneratedColumn<String> get queues =>
      $composableBuilder(column: $table.queues, builder: (column) => column);

  GeneratedColumn<int> get lastLeaseRenewal => $composableBuilder(
    column: $table.lastLeaseRenewal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get extras =>
      $composableBuilder(column: $table.extras, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $StemWorkerHeartbeatsTableManager
    extends
        RootTableManager<
          _$StemSqliteDatabase,
          StemWorkerHeartbeats,
          StemWorkerHeartbeat,
          $StemWorkerHeartbeatsFilterComposer,
          $StemWorkerHeartbeatsOrderingComposer,
          $StemWorkerHeartbeatsAnnotationComposer,
          $StemWorkerHeartbeatsCreateCompanionBuilder,
          $StemWorkerHeartbeatsUpdateCompanionBuilder,
          (
            StemWorkerHeartbeat,
            BaseReferences<
              _$StemSqliteDatabase,
              StemWorkerHeartbeats,
              StemWorkerHeartbeat
            >,
          ),
          StemWorkerHeartbeat,
          PrefetchHooks Function()
        > {
  $StemWorkerHeartbeatsTableManager(
    _$StemSqliteDatabase db,
    StemWorkerHeartbeats table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StemWorkerHeartbeatsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StemWorkerHeartbeatsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StemWorkerHeartbeatsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> workerId = const Value.absent(),
                Value<String> namespace = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> isolateCount = const Value.absent(),
                Value<int> inflight = const Value.absent(),
                Value<String> queues = const Value.absent(),
                Value<int?> lastLeaseRenewal = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> extras = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StemWorkerHeartbeatsCompanion(
                workerId: workerId,
                namespace: namespace,
                timestamp: timestamp,
                isolateCount: isolateCount,
                inflight: inflight,
                queues: queues,
                lastLeaseRenewal: lastLeaseRenewal,
                version: version,
                extras: extras,
                expiresAt: expiresAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workerId,
                required String namespace,
                required int timestamp,
                required int isolateCount,
                required int inflight,
                Value<String> queues = const Value.absent(),
                Value<int?> lastLeaseRenewal = const Value.absent(),
                required String version,
                Value<String> extras = const Value.absent(),
                required int expiresAt,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => StemWorkerHeartbeatsCompanion.insert(
                workerId: workerId,
                namespace: namespace,
                timestamp: timestamp,
                isolateCount: isolateCount,
                inflight: inflight,
                queues: queues,
                lastLeaseRenewal: lastLeaseRenewal,
                version: version,
                extras: extras,
                expiresAt: expiresAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StemWorkerHeartbeatsProcessedTableManager =
    ProcessedTableManager<
      _$StemSqliteDatabase,
      StemWorkerHeartbeats,
      StemWorkerHeartbeat,
      $StemWorkerHeartbeatsFilterComposer,
      $StemWorkerHeartbeatsOrderingComposer,
      $StemWorkerHeartbeatsAnnotationComposer,
      $StemWorkerHeartbeatsCreateCompanionBuilder,
      $StemWorkerHeartbeatsUpdateCompanionBuilder,
      (
        StemWorkerHeartbeat,
        BaseReferences<
          _$StemSqliteDatabase,
          StemWorkerHeartbeats,
          StemWorkerHeartbeat
        >,
      ),
      StemWorkerHeartbeat,
      PrefetchHooks Function()
    >;

class $StemSqliteDatabaseManager {
  final _$StemSqliteDatabase _db;
  $StemSqliteDatabaseManager(this._db);
  $StemQueueJobsTableManager get stemQueueJobs =>
      $StemQueueJobsTableManager(_db, _db.stemQueueJobs);
  $StemDeadLettersTableManager get stemDeadLetters =>
      $StemDeadLettersTableManager(_db, _db.stemDeadLetters);
  $StemTaskResultsTableManager get stemTaskResults =>
      $StemTaskResultsTableManager(_db, _db.stemTaskResults);
  $StemGroupsTableManager get stemGroups =>
      $StemGroupsTableManager(_db, _db.stemGroups);
  $StemGroupResultsTableManager get stemGroupResults =>
      $StemGroupResultsTableManager(_db, _db.stemGroupResults);
  $StemWorkerHeartbeatsTableManager get stemWorkerHeartbeats =>
      $StemWorkerHeartbeatsTableManager(_db, _db.stemWorkerHeartbeats);
}
