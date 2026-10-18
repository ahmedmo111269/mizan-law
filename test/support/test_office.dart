import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizan_law/src/data/client_repository.dart';
import 'package:mizan_law/src/data/office_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<TestOffice> createTestOffice(WidgetTester tester) async =>
    (await tester.runAsync(TestOffice.create))!;

Future<void> pumpUi(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

class TestOffice {
  TestOffice(this.directory, this.database);

  final Directory directory;
  final OfficeDatabase database;
  ClientRepository get clients => ClientRepository(
        database.connection,
        workspaceId: database.activeWorkspace.id,
      );

  Future<void> close() async {
    await database.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static Future<TestOffice> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('mizan-flutter-test-');
    final database = await OfficeDatabase.open(
      rootDirectory: directory,
      factory: databaseFactoryFfi,
    );
    return TestOffice(directory, database);
  }
}
