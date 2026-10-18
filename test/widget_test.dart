import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mizan_law/src/app.dart';
import 'package:mizan_law/src/app_controller.dart';
import 'package:mizan_law/src/shared/mizan_theme.dart';

import 'support/test_office.dart';

void main() {
  testWidgets('the app shell opens the Arabic office dashboard', (tester) async {
    final office = await TestOffice.create();
    final controller = AppController(office.database);
    await controller.initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await office.close();
    });

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

    expect(find.text('مكتب اليوم'), findsWidgets);
    expect(find.text('ميزان'), findsOneWidget);
    expect(find.text('إضافة قضية'), findsNothing);
  });
}
