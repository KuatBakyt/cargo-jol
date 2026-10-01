import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jol_cargo/core/api_client.dart';
import 'package:jol_cargo/core/session.dart';
import 'package:jol_cargo/features/home_screen.dart';

class DashboardServer implements HttpClientAdapter {
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    return ResponseBody.fromString(jsonEncode({'count': 0, 'results': []}), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final role in ['carrier', 'shipper']) {
    testWidgets('$role dashboard fits a phone and handles an empty account',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = DashboardServer();
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
        ..httpClientAdapter = server;
      final session = Session(ApiClient(dio: dio))
        ..user = {'id': 2, 'role': role, 'first_name': 'Bakyt'};
      var opened = false;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
              home: Scaffold(
                  body: HomeScreen(
                      openCargo: () => opened = true, openProfile: () {})))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (role == 'carrier') {
        expect(find.text('Добавьте машину'), findsOneWidget);
        expect(server.paths, contains('/vehicles'));
        await tester.tap(find.text('НАЙТИ ГРУЗ'));
      } else {
        expect(find.text('Нужно перевезти груз?'), findsOneWidget);
        expect(server.paths, isNot(contains('/vehicles')));
        await tester.tap(find.text('Смотреть все'));
      }
      expect(opened, isTrue);
    });
  }
}
