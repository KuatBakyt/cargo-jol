import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jol_cargo/core/api_client.dart';
import 'package:jol_cargo/core/session.dart';
import 'package:jol_cargo/features/cargo/cargo_form.dart';

void main() {
  testWidgets('Route can advance without validating unopened cargo fields',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => Session(ApiClient()),
        child: const MaterialApp(home: CargoForm())));
    for (final entry in {
      'Город отправления': 'Алматы',
      'Город назначения': 'Астана',
      'Адрес загрузки': 'Склад 1',
      'Адрес разгрузки': 'Склад 2'
    }.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tester.ensureVisible(find.text('Далее').first);
    await tester.tap(find.text('Далее').first);
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(TextFormField, 'Название груза'), findsOneWidget);
    expect(find.text('Заполните поле'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
