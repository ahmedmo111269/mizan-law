import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizan_law/src/data/client_repository.dart';
import 'package:mizan_law/src/data/office_database.dart';
import 'package:mizan_law/src/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  test('first run creates a usable empty workspace and reopening keeps saved data', () async {
    final directory = await Directory.systemTemp.createTemp('mizan-restart-test-');
    var database = await OfficeDatabase.open(
      rootDirectory: directory,
      factory: databaseFactoryFfi,
    );
    expect(database.activeWorkspace.name, 'القاعدة الرئيسية');
    final clients = ClientRepository(
      database.connection,
      workspaceId: database.activeWorkspace.id,
    );
    await clients.createClient(
      operationId: 'persist-operation',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'موكل اختبار بقاء البيانات',
      ),
    );
    final activeId = database.activeWorkspace.id;
    await database.close();

    database = await OfficeDatabase.open(
      rootDirectory: directory,
      factory: databaseFactoryFfi,
    );
    expect(database.activeWorkspace.id, activeId);
    final reopened = ClientRepository(
      database.connection,
      workspaceId: database.activeWorkspace.id,
    );
    final page = await reopened.listClients();
    expect(page.items, hasLength(1));
    expect(page.items.single.person.displayName, 'موكل اختبار بقاء البيانات');
    await database.close();
    await directory.delete(recursive: true);
  });

  test('new workspace files stay isolated and switching is persisted', () async {
    final directory = await Directory.systemTemp.createTemp('mizan-switch-test-');
    var database = await OfficeDatabase.open(
      rootDirectory: directory,
      factory: databaseFactoryFfi,
    );
    final firstWorkspace = database.activeWorkspace;
    final firstRepo = ClientRepository(
      database.connection,
      workspaceId: firstWorkspace.id,
    );
    final sharedPerson = await firstRepo.createClient(
      operationId: 'first-workspace-operation',
      newPerson: const PersonDraft(
        kind: PersonKind.organization,
        displayName: 'جهة اختبار مشتركة بين القواعد',
      ),
    );
    final secondWorkspace = await database.createWorkspace('قاعدة اختبار مستقلة');
    final secondRepo = ClientRepository(
      database.connection,
      workspaceId: secondWorkspace.id,
    );
    expect(await secondRepo.countClients(), 0);
    await secondRepo.createClient(
      operationId: 'second-workspace-operation',
      existingPersonId: sharedPerson.person.id,
    );
    expect(await secondRepo.countClients(), 1);
    await database.switchWorkspace(firstWorkspace.id);
    final firstReopened = ClientRepository(
      database.connection,
      workspaceId: database.activeWorkspace.id,
    );
    expect(await firstReopened.countClients(), 1);
    await database.close();

    database = await OfficeDatabase.open(
      rootDirectory: directory,
      factory: databaseFactoryFfi,
    );
    expect(database.activeWorkspace.id, firstWorkspace.id);
    await database.switchWorkspace(secondWorkspace.id);
    expect(
      (await ClientRepository(
        database.connection,
        workspaceId: secondWorkspace.id,
      ).listClients())
          .items
          .single
          .person
          .id,
      sharedPerson.person.id,
    );
    await database.close();
    await directory.delete(recursive: true);
  });
}
