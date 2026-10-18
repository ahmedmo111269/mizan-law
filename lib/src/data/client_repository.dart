import 'package:sqflite_common/sqlite_api.dart';

import '../domain/models.dart';
import 'arabic_normalizer.dart';
import 'errors.dart';
import 'id_generator.dart';

class ClientRepository {
  ClientRepository(this._database, {required this.workspaceId});

  final Database _database;
  final String workspaceId;

  static const int defaultPageSize = 25;
  static const int _maximumPageSize = 100;

  Future<ClientPage> listClients({
    String query = '',
    ClientStatus? status = ClientStatus.active,
    ClientSort sort = ClientSort.nameAscending,
    int page = 0,
    int pageSize = defaultPageSize,
  }) async {
    final safePage = page < 0 ? 0 : page;
    final safeSize = pageSize.clamp(1, _maximumPageSize).toInt();
    final normalized = ArabicNormalizer.text(query);
    final emailQuery = query.trim().toLowerCase();
    final digits = ArabicNormalizer.digits(query);
    final where = <String>[];
    final args = <Object?>[];

    if (status != null) {
      where.add('engagement.status = ?');
      args.add(_statusValue(status));
    }
    if (normalized.isNotEmpty || emailQuery.isNotEmpty || digits.isNotEmpty) {
      final searchClauses = <String>[];
      if (normalized.isNotEmpty) {
        searchClauses.add("person.name_normalized LIKE ? ESCAPE '!'");
        args.add('${_escapeLike(normalized)}%');
      }
      if (emailQuery.isNotEmpty) {
        searchClauses.add("person.email_normalized LIKE ? ESCAPE '!'");
        args.add('${_escapeLike(emailQuery)}%');
      }
      if (digits.isNotEmpty) {
        searchClauses.add('person.phone_normalized LIKE ?');
        args.add('$digits%');
      }
      where.add('(${searchClauses.join(' OR ')})');
    }

    final orderBy = switch (sort) {
      ClientSort.nameAscending => 'person.name_normalized ASC, engagement.id ASC',
      ClientSort.nameDescending => 'person.name_normalized DESC, engagement.id DESC',
      ClientSort.recentlyUpdated =>
        'engagement.updated_at_utc DESC, engagement.id DESC',
    };
    final rows = await _database.rawQuery('''
      SELECT
        engagement.id AS engagement_id,
        engagement.status,
        engagement.created_at_utc,
        engagement.updated_at_utc,
        engagement.status_changed_at_utc,
        engagement.revision AS engagement_revision,
        person.id,
        person.kind,
        person.display_name,
        person.phone,
        person.email,
        person.created_at_utc AS person_created_at_utc,
        person.updated_at_utc AS person_updated_at_utc,
        person.revision
      FROM main.client_engagements AS engagement
      JOIN office_registry.people AS person ON person.id = engagement.person_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', <Object?>[...args, safeSize + 1, safePage * safeSize]);

    final hasMore = rows.length > safeSize;
    final visibleRows = hasMore ? rows.take(safeSize) : rows;
    return ClientPage(
      items: visibleRows.map(_recordFromJoinedRow).toList(growable: false),
      hasMore: hasMore,
    );
  }

  Future<ClientRecord?> getClient(String engagementId) async {
    final rows = await _database.rawQuery('''
      SELECT
        engagement.id AS engagement_id,
        engagement.status,
        engagement.created_at_utc,
        engagement.updated_at_utc,
        engagement.status_changed_at_utc,
        engagement.revision AS engagement_revision,
        person.id,
        person.kind,
        person.display_name,
        person.phone,
        person.email,
        person.created_at_utc AS person_created_at_utc,
        person.updated_at_utc AS person_updated_at_utc,
        person.revision
      FROM main.client_engagements AS engagement
      JOIN office_registry.people AS person ON person.id = engagement.person_id
      WHERE engagement.id = ?
      LIMIT 1
    ''', <Object?>[engagementId]);
    return rows.isEmpty ? null : _recordFromJoinedRow(rows.single);
  }

  /// Returns possible identity matches. A match is a warning, never an automatic merge.
  Future<List<PersonCandidate>> findPotentialMatches(PersonDraft draft) async {
    final name = ArabicNormalizer.text(draft.displayName);
    final phone = _normalizeOptionalPhone(draft.phone);
    final email = _normalizeOptionalEmail(draft.email);
    if (name.length < 2 && phone == null && email == null) {
      return const <PersonCandidate>[];
    }

    final clauses = <String>[];
    final args = <Object?>[];
    if (name.length >= 2) {
      clauses.add("person.name_normalized LIKE ? ESCAPE '!'");
      args.add('${_escapeLike(name)}%');
    }
    if (phone != null) {
      clauses.add('person.phone_normalized = ?');
      args.add(phone);
    }
    if (email != null) {
      clauses.add('person.email_normalized = ?');
      args.add(email);
    }
    final rows = await _database.rawQuery('''
      SELECT person.*,
        EXISTS (
          SELECT 1 FROM main.client_engagements AS engagement
          WHERE engagement.person_id = person.id
        ) AS already_client
      FROM office_registry.people AS person
      WHERE ${clauses.join(' OR ')}
      ORDER BY
        CASE WHEN person.name_normalized = ? THEN 0 ELSE 1 END,
        person.name_normalized ASC,
        person.id ASC
      LIMIT 6
    ''', <Object?>[...args, name]);

    return rows.map((row) {
      final person = PersonRecord.fromMap(row);
      final exactName = ArabicNormalizer.text(person.displayName) == name;
      final exactPhone = phone != null &&
          ArabicNormalizer.digits(person.phone ?? '') == phone;
      final exactEmail = email != null && person.email?.toLowerCase() == email;
      return PersonCandidate(
        person: person,
        matchReason: exactPhone
            ? 'رقم الهاتف متطابق'
            : exactEmail
                ? 'البريد الإلكتروني متطابق'
                : exactName
                    ? 'الاسم متطابق بعد تطبيع البحث'
                    : 'الاسم متقارب في بداية العبارة',
        alreadyClient: (row['already_client'] as int? ?? 0) == 1,
      );
    }).toList(growable: false);
  }

  Future<ClientRecord> createClient({
    required String operationId,
    String? existingPersonId,
    PersonDraft? newPerson,
    List<String> reviewedSimilarPersonIds = const <String>[],
  }) async {
    if ((existingPersonId == null) == (newPerson == null)) {
      throw const ValidationException('اختر شخصًا موجودًا أو أدخل هوية جديدة.');
    }
    if (newPerson != null) _validateDraft(newPerson);

    try {
      return await _database.transaction((transaction) async {
        final receipt = await transaction.query(
          'operation_receipts',
          where: 'operation_id = ?',
          whereArgs: <Object?>[operationId],
          limit: 1,
        );
        if (receipt.isNotEmpty) {
          final prior = await _recordById(
            transaction,
            receipt.single['engagement_id']! as String,
          );
          if (prior != null) return prior;
        }

        late final String personId;
        if (existingPersonId != null) {
          final existing = await transaction.query(
            'office_registry.people',
            columns: const ['id'],
            where: 'id = ?',
            whereArgs: <Object?>[existingPersonId],
            limit: 1,
          );
          if (existing.isEmpty) throw const RecordNotFoundException();
          personId = existingPersonId;
        } else {
          final draft = newPerson!;
          final candidates = await _potentialMatchesInTransaction(
            transaction,
            draft,
          );
          final reviewedIds = reviewedSimilarPersonIds.toSet();
          final unreviewedCandidates = candidates
              .where((candidate) => !reviewedIds.contains(candidate.person.id))
              .toList(growable: false);
          if (unreviewedCandidates.isNotEmpty) {
            throw SimilarPeopleException(unreviewedCandidates);
          }
          personId = IdGenerator.uuidV4();
          final now = _nowUtc();
          await transaction.insert('office_registry.people', <String, Object?>{
            'id': personId,
            'kind': _kindValue(draft.kind),
            'display_name': draft.displayName.trim(),
            'name_normalized': ArabicNormalizer.text(draft.displayName),
            'phone': _normalizeDisplayPhone(draft.phone),
            'phone_normalized': _normalizeOptionalPhone(draft.phone),
            'email': _normalizeDisplayEmail(draft.email),
            'email_normalized': _normalizeOptionalEmail(draft.email),
            'created_at_utc': now,
            'updated_at_utc': now,
            'revision': 1,
          });
        }

        final currentRelation = await transaction.query(
          'main.client_engagements',
          columns: const ['id'],
          where: 'person_id = ?',
          whereArgs: <Object?>[personId],
          limit: 1,
        );
        if (currentRelation.isNotEmpty) {
          throw const DuplicateClientException();
        }

        final now = _nowUtc();
        final engagementId = IdGenerator.uuidV4();
        await transaction.insert('main.client_engagements', <String, Object?>{
          'id': engagementId,
          'person_id': personId,
          'status': 'active',
          'created_at_utc': now,
          'updated_at_utc': now,
          'status_changed_at_utc': now,
          'revision': 1,
        });
        await transaction.insert('main.operation_receipts', <String, Object?>{
          'operation_id': operationId,
          'engagement_id': engagementId,
          'completed_at_utc': now,
        });
        final created = await _recordById(transaction, engagementId);
        if (created == null) throw const StorageException();
        return created;
      });
    } on MizanException {
      rethrow;
    } on DatabaseException catch (_) {
      throw const StorageException();
    }
  }

  Future<ClientRecord> updateIdentity({
    required String engagementId,
    required String displayName,
    required String? phone,
    required String? email,
  }) async {
    final cleanName = displayName.trim();
    if (cleanName.isEmpty || cleanName.length > 200) {
      throw const ValidationException('الاسم مطلوب، ويجب ألا يتجاوز 200 حرف.');
    }
    _validateOptionalPhone(phone);
    _validateOptionalEmail(email);

    try {
      return await _database.transaction((transaction) async {
        final row = await transaction.query(
          'main.client_engagements',
          columns: const ['person_id'],
          where: 'id = ?',
          whereArgs: <Object?>[engagementId],
          limit: 1,
        );
        if (row.isEmpty) throw const RecordNotFoundException();
        final personId = row.single['person_id']! as String;
        final updated = await transaction.update(
          'office_registry.people',
          <String, Object?>{
            'display_name': cleanName,
            'name_normalized': ArabicNormalizer.text(cleanName),
            'phone': _normalizeDisplayPhone(phone),
            'phone_normalized': _normalizeOptionalPhone(phone),
            'email': _normalizeDisplayEmail(email),
            'email_normalized': _normalizeOptionalEmail(email),
            'updated_at_utc': _nowUtc(),
            'revision': await _nextPersonRevision(transaction, personId),
          },
          where: 'id = ?',
          whereArgs: <Object?>[personId],
        );
        if (updated != 1) throw const RecordNotFoundException();
        final result = await _recordById(transaction, engagementId);
        if (result == null) throw const RecordNotFoundException();
        return result;
      });
    } on MizanException {
      rethrow;
    } on DatabaseException catch (_) {
      throw const StorageException();
    }
  }

  Future<ClientRecord> setArchived({
    required String engagementId,
    required bool archived,
  }) async {
    try {
      return await _database.transaction((transaction) async {
        final rows = await transaction.query(
          'main.client_engagements',
          columns: const ['status', 'revision'],
          where: 'id = ?',
          whereArgs: <Object?>[engagementId],
          limit: 1,
        );
        if (rows.isEmpty) throw const RecordNotFoundException();
        final currentStatus = rows.single['status']! as String;
        final nextStatus = archived ? 'archived' : 'active';
        if (currentStatus != nextStatus) {
          final now = _nowUtc();
          await transaction.update(
            'main.client_engagements',
            <String, Object?>{
              'status': nextStatus,
              'updated_at_utc': now,
              'status_changed_at_utc': now,
              'revision': (rows.single['revision']! as int) + 1,
            },
            where: 'id = ?',
            whereArgs: <Object?>[engagementId],
          );
        }
        final result = await _recordById(transaction, engagementId);
        if (result == null) throw const RecordNotFoundException();
        return result;
      });
    } on MizanException {
      rethrow;
    } on DatabaseException catch (_) {
      throw const StorageException();
    }
  }

  Future<int> countClients({ClientStatus? status}) async {
    final where = status == null ? '' : 'WHERE status = ?';
    final args = status == null ? const <Object?>[] : <Object?>[_statusValue(status)];
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM main.client_engagements $where',
      args,
    );
    return rows.single['count']! as int;
  }

  Future<void> verifyIntegrity() async {
    final foreignKeyErrors = await _database.rawQuery(
      'PRAGMA main.foreign_key_check',
    );
    final orphaned = await _database.rawQuery('''
      SELECT COUNT(*) AS count
      FROM main.client_engagements AS engagement
      LEFT JOIN office_registry.people AS person
        ON person.id = engagement.person_id
      WHERE person.id IS NULL
    ''');
    if (foreignKeyErrors.isNotEmpty || (orphaned.single['count'] as int) != 0) {
      throw StateError('Client database integrity check failed');
    }
  }

  Future<ClientRecord?> _recordById(
    DatabaseExecutor database,
    String engagementId,
  ) async {
    final rows = await database.rawQuery('''
      SELECT
        engagement.id AS engagement_id,
        engagement.status,
        engagement.created_at_utc,
        engagement.updated_at_utc,
        engagement.status_changed_at_utc,
        engagement.revision AS engagement_revision,
        person.id,
        person.kind,
        person.display_name,
        person.phone,
        person.email,
        person.created_at_utc AS person_created_at_utc,
        person.updated_at_utc AS person_updated_at_utc,
        person.revision
      FROM main.client_engagements AS engagement
      JOIN office_registry.people AS person ON person.id = engagement.person_id
      WHERE engagement.id = ?
      LIMIT 1
    ''', <Object?>[engagementId]);
    return rows.isEmpty ? null : _recordFromJoinedRow(rows.single);
  }

  Future<int> _nextPersonRevision(
    DatabaseExecutor transaction,
    String personId,
  ) async {
    final rows = await transaction.query(
      'office_registry.people',
      columns: const ['revision'],
      where: 'id = ?',
      whereArgs: <Object?>[personId],
      limit: 1,
    );
    if (rows.isEmpty) throw const RecordNotFoundException();
    return (rows.single['revision']! as int) + 1;
  }

  Future<List<PersonCandidate>> _potentialMatchesInTransaction(
    Transaction transaction,
    PersonDraft draft,
  ) async {
    final name = ArabicNormalizer.text(draft.displayName);
    final phone = _normalizeOptionalPhone(draft.phone);
    final email = _normalizeOptionalEmail(draft.email);
    final clauses = <String>[];
    final args = <Object?>[];
    if (name.length >= 2) {
      clauses.add("person.name_normalized LIKE ? ESCAPE '!'");
      args.add('${_escapeLike(name)}%');
    }
    if (phone != null) {
      clauses.add('person.phone_normalized = ?');
      args.add(phone);
    }
    if (email != null) {
      clauses.add('person.email_normalized = ?');
      args.add(email);
    }
    if (clauses.isEmpty) return const <PersonCandidate>[];

    final rows = await transaction.rawQuery('''
      SELECT person.*,
        EXISTS (
          SELECT 1 FROM main.client_engagements AS engagement
          WHERE engagement.person_id = person.id
        ) AS already_client
      FROM office_registry.people AS person
      WHERE ${clauses.join(' OR ')}
      ORDER BY
        CASE WHEN person.name_normalized = ? THEN 0 ELSE 1 END,
        person.name_normalized ASC,
        person.id ASC
      LIMIT 6
    ''', <Object?>[...args, name]);

    return rows.map((row) {
      final person = PersonRecord.fromMap(row);
      final exactPhone = phone != null &&
          ArabicNormalizer.digits(person.phone ?? '') == phone;
      final exactName = ArabicNormalizer.text(person.displayName) == name;
      final exactEmail = email != null && person.email?.toLowerCase() == email;
      return PersonCandidate(
        person: person,
        matchReason: exactPhone
            ? 'رقم الهاتف متطابق'
            : exactEmail
                ? 'البريد الإلكتروني متطابق'
                : exactName
                    ? 'الاسم متطابق بعد تطبيع البحث'
                    : 'الاسم متقارب في بداية العبارة',
        alreadyClient: (row['already_client'] as int? ?? 0) == 1,
      );
    }).toList(growable: false);
  }

  static ClientRecord _recordFromJoinedRow(Map<String, Object?> row) {
    final personMap = <String, Object?>{
      'id': row['id'],
      'kind': row['kind'],
      'display_name': row['display_name'],
      'phone': row['phone'],
      'email': row['email'],
      'created_at_utc': row['person_created_at_utc'],
      'updated_at_utc': row['person_updated_at_utc'],
      'revision': row['revision'],
    };
    final engagementMap = <String, Object?>{
      ...personMap,
      'person_created_at_utc': row['person_created_at_utc'],
      'person_updated_at_utc': row['person_updated_at_utc'],
      'engagement_id': row['engagement_id'],
      'status': row['status'],
      'created_at_utc': row['created_at_utc'],
      'updated_at_utc': row['updated_at_utc'],
      'status_changed_at_utc': row['status_changed_at_utc'],
      'engagement_revision': row['engagement_revision'],
    };
    return ClientRecord.fromMap(engagementMap);
  }

  static void _validateDraft(PersonDraft draft) {
    final name = draft.displayName.trim();
    if (name.isEmpty || name.length > 200) {
      throw const ValidationException('الاسم مطلوب، ويجب ألا يتجاوز 200 حرف.');
    }
    _validateOptionalPhone(draft.phone);
    _validateOptionalEmail(draft.email);
  }

  static void _validateOptionalPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return;
    final value = phone.trim();
    final digits = ArabicNormalizer.digits(value);
    if (!RegExp(r'^[+0-9٠-٩۰-۹().\s-]+$').hasMatch(value) ||
        digits.length < 7 ||
        digits.length > 15 ||
        value.length > 30) {
      throw const ValidationException('أدخل رقم هاتف صحيحًا أو اترك الحقل فارغًا.');
    }
  }

  static void _validateOptionalEmail(String? email) {
    if (email == null || email.trim().isEmpty) return;
    final value = email.trim();
    if (value.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      throw const ValidationException('أدخل بريدًا إلكترونيًا صحيحًا أو اترك الحقل فارغًا.');
    }
  }

  static String? _normalizeDisplayPhone(String? phone) {
    final value = phone?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? _normalizeOptionalPhone(String? phone) {
    final digits = ArabicNormalizer.digits(phone ?? '');
    return digits.isEmpty ? null : digits;
  }

  static String? _normalizeDisplayEmail(String? email) {
    final value = email?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? _normalizeOptionalEmail(String? email) {
    final value = email?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }

  static String _escapeLike(String value) =>
      value.replaceAll('!', '!!').replaceAll('%', '!%').replaceAll('_', '!_');

  static String _kindValue(PersonKind kind) =>
      kind == PersonKind.organization ? 'organization' : 'natural';

  static String _statusValue(ClientStatus status) =>
      status == ClientStatus.archived ? 'archived' : 'active';

  static String _nowUtc() => DateTime.now().toUtc().toIso8601String();
}
