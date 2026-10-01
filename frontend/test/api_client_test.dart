import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jol_cargo/core/api_client.dart';

class FakeServer implements HttpClientAdapter {
  int refreshes = 0;
  bool invalidRefresh = false;
  final List<String?> authorization = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final headers = {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    };
    if (options.path == '/auth/refresh') {
      refreshes++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return ResponseBody.fromString(
          jsonEncode(invalidRefresh
              ? {'detail': 'Token is invalid'}
              : {'access': 'new-access', 'refresh': 'new-refresh'}),
          invalidRefresh ? 401 : 200,
          headers: headers);
    }
    authorization.add(options.headers['Authorization'] as String?);
    final valid = options.headers['Authorization'] == 'Bearer new-access';
    return ResponseBody.fromString(
        jsonEncode(
            valid ? {'id': 3, 'role': 'carrier'} : {'detail': 'Expired'}),
        valid ? 200 : 401,
        headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient api;
  late FakeServer server;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(
        {'jol.access': 'old-access', 'jol.refresh': 'old-refresh'});
    server = FakeServer();
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = server;
    api = ApiClient(dio: dio);
    await api.restore();
  });
  test('Concurrent 401 responses rotate refresh once and replay both requests',
      () async {
    final results =
        await Future.wait([api.get('/auth/me'), api.get('/auth/me')]);
    expect(results.every((r) => r['id'] == 3), isTrue);
    expect(server.refreshes, 1);
    expect(await api.storage.read(key: 'jol.refresh'), 'new-refresh');
    expect(
        server.authorization.where((h) => h == 'Bearer new-access').length, 2);
  });
  test('Invalid refresh clears credentials and ends the session', () async {
    server.invalidRefresh = true;
    var expired = false;
    api.onSessionExpired = () => expired = true;
    await expectLater(api.get('/auth/me'), throwsA(isA<DioException>()));
    expect(expired, isTrue);
    expect(api.access, isNull);
    expect(await api.storage.read(key: 'jol.refresh'), isNull);
    expect(server.refreshes, 1);
  });
}
