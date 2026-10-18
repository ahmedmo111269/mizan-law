enum PersonKind { natural, organization }

enum ClientStatus { active, archived }

enum ClientSort { nameAscending, nameDescending, recentlyUpdated }

class WorkspaceInfo {
  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.createdAtUtc,
  });

  final String id;
  final String name;
  final String fileName;
  final String createdAtUtc;

  factory WorkspaceInfo.fromMap(Map<String, Object?> map) => WorkspaceInfo(
        id: map['id']! as String,
        name: map['name']! as String,
        fileName: map['file_name']! as String,
        createdAtUtc: map['created_at_utc']! as String,
      );
}

class PersonRecord {
  const PersonRecord({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.revision,
  });

  final String id;
  final PersonKind kind;
  final String displayName;
  final String? phone;
  final String? email;
  final String createdAtUtc;
  final String updatedAtUtc;
  final int revision;

  factory PersonRecord.fromMap(Map<String, Object?> map) => PersonRecord(
        id: map['id']! as String,
        kind: map['kind'] == 'organization'
            ? PersonKind.organization
            : PersonKind.natural,
        displayName: map['display_name']! as String,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        createdAtUtc: (map['person_created_at_utc'] ?? map['created_at_utc'])! as String,
        updatedAtUtc: (map['person_updated_at_utc'] ?? map['updated_at_utc'])! as String,
        revision: (map['revision'] as int?) ?? 1,
      );
}

class ClientRecord {
  const ClientRecord({
    required this.engagementId,
    required this.person,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.statusChangedAtUtc,
    required this.revision,
  });

  final String engagementId;
  final PersonRecord person;
  final ClientStatus status;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String statusChangedAtUtc;
  final int revision;

  factory ClientRecord.fromMap(Map<String, Object?> map) => ClientRecord(
        engagementId: map['engagement_id']! as String,
        person: PersonRecord.fromMap(map),
        status: map['status'] == 'archived'
            ? ClientStatus.archived
            : ClientStatus.active,
        createdAtUtc: map['created_at_utc']! as String,
        updatedAtUtc: map['updated_at_utc']! as String,
        statusChangedAtUtc: map['status_changed_at_utc']! as String,
        revision: (map['engagement_revision'] as int?) ?? 1,
      );
}

class PersonCandidate {
  const PersonCandidate({
    required this.person,
    required this.matchReason,
    required this.alreadyClient,
  });

  final PersonRecord person;
  final String matchReason;
  final bool alreadyClient;
}

class ClientPage {
  const ClientPage({required this.items, required this.hasMore});

  final List<ClientRecord> items;
  final bool hasMore;
}

class PersonDraft {
  const PersonDraft({
    required this.kind,
    required this.displayName,
    this.phone,
    this.email,
  });

  final PersonKind kind;
  final String displayName;
  final String? phone;
  final String? email;
}
