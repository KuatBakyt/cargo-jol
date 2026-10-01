import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jol_cargo/core/api_client.dart';
import 'package:jol_cargo/core/session.dart';
import 'package:jol_cargo/features/auth/auth_screen.dart';

void main() {
  testWidgets('Registration offers both roles and validates input', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(create: (_) => Session(ApiClient()), child: const MaterialApp(home: AuthScreen())));
    expect(find.text('С возвращением'), findsOneWidget);
    await tester.tap(find.text('Войти'));
    await tester.pump();
    expect(find.text('Введите email'), findsOneWidget);
    await tester.ensureVisible(find.text('Нет аккаунта? Регистрация'));
    await tester.tap(find.text('Нет аккаунта? Регистрация'));
    await tester.pumpAndSettle();
    expect(find.text('Отправляю груз'), findsOneWidget);
    expect(find.text('Перевожу'), findsOneWidget);
    await tester.tap(find.text('Перевожу'));
    await tester.pumpAndSettle();
    expect(find.text('Создать аккаунт'), findsOneWidget);
  });
}
