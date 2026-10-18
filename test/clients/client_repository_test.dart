import 'package:flutter_test/flutter_test.dart';

import 'package:mizan_law/src/data/errors.dart';
import 'package:mizan_law/src/domain/models.dart';
import '../support/test_office.dart';

void main() {
  late TestOffice office;

  setUp(() async {
    office = await TestOffice.create();
  });

  tearDown(() async => office.close());

  test('adds the first client with optional contact fields omitted', () async {
    final client = await office.clients.createClient(
      operationId: 'operation-first',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'موكل اختبار أول',
      ),
    );

    expect(client.person.displayName, 'موكل اختبار أول');
    expect(client.person.phone, isNull);
    expect(client.person.email, isNull);
    expect(client.status, ClientStatus.active);
    expect(await office.clients.countClients(), 1);
  });

  test('keeps shared-person timestamps separate from relationship timestamps', () async {
    final client = await office.clients.createClient(
      operationId: 'operation-timestamps',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'موكل اختبار تواريخ مستقلة',
      ),
    );
    const earlier = '2000-01-01T00:00:00.000Z';
    await office.database.connection.update(
      'main.client_engagements',
      <String, Object?>{
        'created_at_utc': earlier,
        'updated_at_utc': earlier,
        'status_changed_at_utc': earlier,
      },
      where: 'id = ?',
      whereArgs: <Object?>[client.engagementId],
    );

    final reloaded = (await office.clients.getClient(client.engagementId))!;
    expect(reloaded.createdAtUtc, earlier);
    expect(reloaded.person.createdAtUtc, isNot(earlier));
  });

  test('idempotent retry with same operation id creates one relation', () async {
    const draft = PersonDraft(
      kind: PersonKind.natural,
      displayName: 'موكل إعادة محاولة',
      phone: '01012345678',
    );
    final first = await office.clients.createClient(
      operationId: 'operation-retry',
      newPerson: draft,
    );
    final retry = await office.clients.createClient(
      operationId: 'operation-retry',
      newPerson: draft,
    );

    expect(retry.engagementId, first.engagementId);
    expect(await office.clients.countClients(), 1);
  });

  test('rejects a duplicate relation for an explicitly selected shared person', () async {
    final created = await office.clients.createClient(
      operationId: 'operation-selected-one',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'شخص اختبار ثابت',
      ),
    );

    await expectLater(
      office.clients.createClient(
        operationId: 'operation-selected-two',
        existingPersonId: created.person.id,
      ),
      throwsA(isA<DuplicateClientException>()),
    );
    expect(await office.clients.countClients(), 1);
  });

  test('similar identities warn and remain separate only after confirmation', () async {
    final first = await office.clients.createClient(
      operationId: 'operation-similar-one',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'أحمد علي اختبار',
      ),
    );
    final draft = const PersonDraft(
      kind: PersonKind.natural,
      displayName: 'أحمد علي اختبار',
    );

    await expectLater(
      office.clients.createClient(
        operationId: 'operation-similar-two',
        newPerson: draft,
      ),
      throwsA(isA<SimilarPeopleException>()),
    );
    expect(await office.clients.countClients(), 1);

    final separate = await office.clients.createClient(
      operationId: 'operation-similar-two',
      newPerson: draft,
      reviewedSimilarPersonIds: <String>[first.person.id],
    );
    expect(separate.person.id, isNot(first.person.id));
    expect(await office.clients.countClients(), 2);
  });

  test('a newly observed similar person requires its own review', () async {
    const draft = PersonDraft(
      kind: PersonKind.natural,
      displayName: 'اسم مشترك لا يدمج تلقائيًا',
    );
    final first = await office.clients.createClient(
      operationId: 'operation-review-first',
      newPerson: draft,
    );
    final second = await office.clients.createClient(
      operationId: 'operation-review-second',
      newPerson: draft,
      reviewedSimilarPersonIds: <String>[first.person.id],
    );

    await expectLater(
      office.clients.createClient(
        operationId: 'operation-review-third',
        newPerson: draft,
        reviewedSimilarPersonIds: <String>[first.person.id],
      ),
      throwsA(isA<SimilarPeopleException>()),
    );
    expect(await office.clients.countClients(), 2);
    expect(second.person.id, isNot(first.person.id));
  });

  test('edits shared identity fields without changing the client relationship', () async {
    final created = await office.clients.createClient(
      operationId: 'operation-edit',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'اسم اختبار قبل التعديل',
      ),
    );

    final updated = await office.clients.updateIdentity(
      engagementId: created.engagementId,
      displayName: 'اسم اختبار بعد التعديل',
      phone: '01123456789',
      email: 'test@example.invalid',
    );

    expect(updated.person.id, created.person.id);
    expect(updated.person.displayName, 'اسم اختبار بعد التعديل');
    expect(updated.person.phone, '01123456789');
    expect(updated.person.email, 'test@example.invalid');
    expect(updated.engagementId, created.engagementId);
  });

  test('search normalizes Arabic alef and phone digits and paginates', () async {
    await office.clients.createClient(
      operationId: 'operation-search-one',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'أحمد اختبار ألف',
        phone: '٠١٠١٢٣٤٥٦٧٨',
        email: 'SEARCH@example.invalid',
      ),
    );
    for (var index = 0; index < 30; index++) {
      await office.clients.createClient(
        operationId: 'operation-page-$index',
        newPerson: PersonDraft(
          kind: PersonKind.natural,
          displayName: '${index.toString().padLeft(2, '0')} موكل اختبار صفحة',
        ),
      );
    }

    final byName = await office.clients.listClients(query: 'احمد اختبار');
    final byPhone = await office.clients.listClients(query: '01012345678');
    final byEmail = await office.clients.listClients(query: 'search@example.invalid');
    final emailCandidates = await office.clients.findPotentialMatches(
      const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'اسم مختلف للاختبار',
        email: 'search@example.invalid',
      ),
    );
    final firstPage = await office.clients.listClients(page: 0, pageSize: 10);
    final secondPage = await office.clients.listClients(page: 1, pageSize: 10);

    expect(byName.items.single.person.displayName, 'أحمد اختبار ألف');
    expect(byPhone.items.single.person.displayName, 'أحمد اختبار ألف');
    expect(byEmail.items.single.person.displayName, 'أحمد اختبار ألف');
    expect(emailCandidates.single.matchReason, 'البريد الإلكتروني متطابق');
    expect(firstPage.items, hasLength(10));
    expect(firstPage.hasMore, isTrue);
    expect(secondPage.items, hasLength(10));
    expect(secondPage.items.first.engagementId, isNot(firstPage.items.first.engagementId));
  });

  test('sorts and filters by active and archived relationship status', () async {
    final z = await office.clients.createClient(
      operationId: 'operation-sort-z',
      newPerson: const PersonDraft(kind: PersonKind.natural, displayName: 'زاي اختبار'),
    );
    await office.clients.createClient(
      operationId: 'operation-sort-a',
      newPerson: const PersonDraft(kind: PersonKind.natural, displayName: 'ألف اختبار'),
    );
    await office.clients.setArchived(engagementId: z.engagementId, archived: true);

    final active = await office.clients.listClients(status: ClientStatus.active);
    final archived = await office.clients.listClients(status: ClientStatus.archived);
    final descending = await office.clients.listClients(
      status: null,
      sort: ClientSort.nameDescending,
    );

    expect(active.items, hasLength(1));
    expect(archived.items.single.person.displayName, 'زاي اختبار');
    expect(descending.items, hasLength(2));
    expect(descending.items.first.person.displayName, 'زاي اختبار');
  });

  test('archives and restores relationship without deleting shared identity', () async {
    final client = await office.clients.createClient(
      operationId: 'operation-archive',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'موكل أرشفة اختبار',
      ),
    );

    final archived = await office.clients.setArchived(
      engagementId: client.engagementId,
      archived: true,
    );
    expect(archived.status, ClientStatus.archived);
    expect(await office.clients.countClients(status: ClientStatus.active), 0);
    expect(await office.clients.countClients(status: ClientStatus.archived), 1);
    expect(
      await office.database.connection.rawQuery(
        'SELECT id FROM office_registry.people WHERE id = ?',
        <Object?>[client.person.id],
      ),
      isNotEmpty,
    );

    final restored = await office.clients.setArchived(
      engagementId: client.engagementId,
      archived: false,
    );
    expect(restored.status, ClientStatus.active);
    expect(await office.clients.countClients(status: ClientStatus.active), 1);
  });

  test('shares person identity across independent workspaces without sharing relations', () async {
    final firstWorkspace = office.database.activeWorkspace;
    final client = await office.clients.createClient(
      operationId: 'operation-shared-first',
      newPerson: const PersonDraft(
        kind: PersonKind.organization,
        displayName: 'شركة اختبار مشتركة',
      ),
    );
    final secondWorkspace = await office.database.createWorkspace('قاعدة اختبار ثانية');
    final secondRepository = office.clients;

    expect(secondWorkspace.id, isNot(firstWorkspace.id));
    expect(await secondRepository.countClients(), 0);
    final matches = await secondRepository.findPotentialMatches(
      const PersonDraft(
        kind: PersonKind.organization,
        displayName: 'شركة اختبار مشتركة',
      ),
    );
    expect(matches, hasLength(1));

    await secondRepository.createClient(
      operationId: 'operation-shared-second',
      existingPersonId: client.person.id,
    );
    expect(await secondRepository.countClients(), 1);
    await office.database.switchWorkspace(firstWorkspace.id);
    expect(await office.clients.countClients(), 1);
    expect(
      (await office.clients.listClients()).items.single.person.id,
      client.person.id,
    );
  });

  test('database errors do not erase previous records', () async {
    final created = await office.clients.createClient(
      operationId: 'operation-preserve',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'موكل محفوظ اختبار',
      ),
    );
    await expectLater(
      office.clients.updateIdentity(
        engagementId: created.engagementId,
        displayName: '',
        phone: null,
        email: null,
      ),
      throwsA(isA<ValidationException>()),
    );
    final persisted = await office.clients.getClient(created.engagementId);
    expect(persisted?.person.displayName, 'موكل محفوظ اختبار');
    expect(await office.clients.countClients(), 1);
  });
}
