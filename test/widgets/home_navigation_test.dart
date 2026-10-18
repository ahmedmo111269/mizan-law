import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mizan_law/src/app.dart';
import 'package:mizan_law/src/app_controller.dart';
import 'package:mizan_law/src/domain/models.dart';
import 'package:mizan_law/src/shared/mizan_theme.dart';
import '../support/test_office.dart';

Future<AppController> _mountApp(WidgetTester tester, TestOffice office) async {
  final controller = AppController(office.database);
  await tester.runAsync(controller.initialize);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: MizanTheme.light,
      darkTheme: MizanTheme.dark,
      home: AppShell(controller: controller),
    ),
  );
  await pumpUi(tester);
  return controller;
}

void main() {
  testWidgets('first-run home shows a genuine empty state and client actions', (tester) async {
    final office = await createTestOffice(tester);
    final controller = await _mountApp(tester, office);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(office.close);
    });

    expect(find.text('مكتب اليوم'), findsWidgets);
    expect(find.text('لا يوجد موكلون في هذه القاعدة بعد'), findsOneWidget);
    expect(find.text('إضافة موكل'), findsOneWidget);
    expect(find.text('إضافة قضية'), findsNothing);
    expect(find.text('إضافة جلسة'), findsNothing);
  });

  testWidgets('navigation reaches clients and a real client can be added from a quick action',
      (tester) async {
    final office = await createTestOffice(tester);
    final controller = await _mountApp(tester, office);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(office.close);
    });

    await tester.tap(find.text('الموكلون').last);
    await pumpUi(tester);
    expect(find.text('لا يوجد موكلون نشطون في هذه القاعدة'), findsOneWidget);

    await tester.tap(find.text('إضافة موكل').last);
    await pumpUi(tester);
    expect(find.text('ابحث قبل إنشاء هوية'), findsOneWidget);

    final nameField = find.byKey(const ValueKey<String>('client-name-field'));
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'موكل اختبار واجهة');
    await tester.pump(const Duration(milliseconds: 350));
    await pumpUi(tester);
    await tester.tap(find.text('حفظ الموكل'));
    await pumpUi(tester);

    expect(
      await tester.runAsync(() => office.clients.countClients()),
      1,
    );
    expect(find.text('موكل اختبار واجهة'), findsOneWidget);
  });

  testWidgets('home search opens a real database-backed client card', (tester) async {
    final office = await createTestOffice(tester);
    final controller = await _mountApp(tester, office);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(office.close);
    });
    await tester.runAsync(() => office.clients.createClient(
      operationId: 'widget-search-operation',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'موكل اختبار بحث حقيقي',
      ),
    ));
    controller.markDataChanged();
    await pumpUi(tester);

    final search = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'اسم أو هاتف أو بريد إلكتروني',
    );
    await tester.enterText(search, 'موكل اختبار بحث');
    await tester.pump(const Duration(milliseconds: 320));
    await pumpUi(tester);
    expect(find.text('موكل اختبار بحث حقيقي'), findsOneWidget);

    await tester.tap(find.text('موكل اختبار بحث حقيقي'));
    await pumpUi(tester);
    expect(find.text('بطاقة الموكل'), findsOneWidget);
    expect(find.text('موكل اختبار بحث حقيقي'), findsOneWidget);
    expect(find.textContaining('لم تُنفّذ وحداتها بعد'), findsOneWidget);
  });

  testWidgets('reusing a shared identity requires an explicit user confirmation', (tester) async {
    final office = await createTestOffice(tester);
    final firstClient = (await tester.runAsync(() => office.clients.createClient(
      operationId: 'shared-identity-original',
      newPerson: const PersonDraft(
        kind: PersonKind.natural,
        displayName: 'هوية اختبار مشتركة',
        phone: '01012345678',
      ),
    )))!;
    await tester.runAsync(
      () => office.database.createWorkspace('قاعدة إعادة استخدام اختبار'),
    );
    final controller = await _mountApp(tester, office);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(office.close);
    });

    await tester.tap(find.text('الموكلون').last);
    await pumpUi(tester);
    await tester.tap(find.text('إضافة موكل').last);
    await pumpUi(tester);
    final nameField = find.byKey(const ValueKey<String>('client-name-field'));
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'هوية اختبار مشتركة');
    await tester.pump(const Duration(milliseconds: 350));
    await pumpUi(tester);
    expect(find.text('استخدام'), findsOneWidget);

    await tester.tap(find.text('استخدام'));
    await pumpUi(tester);
    expect(find.text('تأكيد استخدام هوية مشتركة'), findsOneWidget);
    await tester.tap(find.text('تأكيد أنها الهوية نفسها'));
    await pumpUi(tester);
    await tester.tap(find.text('استخدام الهوية وإضافة الموكل'));
    await pumpUi(tester);

    final added =
        (await tester.runAsync(() => office.clients.listClients()))!.items.single;
    expect(added.person.id, firstClient.person.id);
    expect(
      await tester.runAsync(() => office.clients.countClients()),
      1,
    );
  });

  testWidgets('responsive shell has no layout exception at required widths', (tester) async {
    final office = await createTestOffice(tester);
    final controller = await _mountApp(tester, office);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(office.close);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in <double>[320, 360, 390, 768, 1024, 1440]) {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(width * 2, 1600);
      await tester.pump();
      await pumpUi(tester);
      expect(tester.takeException(), isNull, reason: 'layout failed at $width px');
      expect(find.text('مكتب اليوم'), findsWidgets);
      expect(find.text('ميزان'), findsOneWidget);
    }
  });

  testWidgets('opening the client centre from home preserves search scope', (tester) async {
    final office = await createTestOffice(tester);
    final controller = await _mountApp(tester, office);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(office.close);
    });

    final search = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'اسم أو هاتف أو بريد إلكتروني',
    );
    await tester.enterText(search, 'نص بحث اختبار');
    await tester.tap(find.text('البحث في مركز الموكلين'));
    await pumpUi(tester);
    expect(find.text('بحث في موكلي هذه القاعدة'), findsOneWidget);
    expect(find.text('نص بحث اختبار'), findsOneWidget);
  });
}
