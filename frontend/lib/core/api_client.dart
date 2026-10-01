import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One client for all screens. Tokens are never stored in preferences or logs.
class ApiClient {
  ApiClient({Dio? dio, FlutterSecureStorage? storage})
      : dio = dio ?? Dio(BaseOptions(
          baseUrl: const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000/api'),
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        )),
        storage = storage ?? const FlutterSecureStorage() {
    this.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (access != null && options.extra['public'] != true) {
          options.headers['Authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        if (error.response?.statusCode != 401 || request.extra['public'] == true || request.extra['retried'] == true) {
          handler.next(error);
          return;
        }
        try {
          await refreshTokens();
          request.extra['retried'] = true;
          request.headers['Authorization'] = 'Bearer $access';
          handler.resolve(await this.dio.fetch(request));
        } catch (_) {
          // Only an invalid refresh ends the session; network failures can be retried.
          handler.next(error);
        }
      },
    ));
  }

  final Dio dio;
  final FlutterSecureStorage storage;
  String? access;
  Future<void>? _refreshing;
  void Function()? onSessionExpired;

  Future<void> restore() async {
    access = await storage.read(key: 'jol.access');
  }

  Future<void> saveTokens(Map<String, dynamic> tokens) async {
    await storage.write(key: 'jol.refresh', value: tokens['refresh'] as String);
    await storage.write(key: 'jol.access', value: tokens['access'] as String);
    access = tokens['access'] as String;
  }

  Future<void> clearTokens() async {
    access = null;
    await storage.delete(key: 'jol.access');
    await storage.delete(key: 'jol.refresh');
  }

  Future<void> refreshTokens() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final refresh = await storage.read(key: 'jol.refresh');
    if (refresh == null) {
      onSessionExpired?.call();
      throw StateError('No refresh token');
    }
    try {
      final response = await dio.post('/auth/refresh', data: {'refresh': refresh}, options: Options(extra: {'public': true}));
      await saveTokens(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 400) {
        await clearTokens();
        onSessionExpired?.call();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final response = await dio.get(path, queryParameters: query);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? data]) async {
    final response = await dio.post(path, data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> data) async {
    final response = await dio.patch(path, data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> delete(String path) async { await dio.delete(path); }
}

String errorText(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 401) return 'Сессия завершена. Войдите снова.';
    if (error.response?.statusCode == 403) return 'У вас нет прав на это действие.';
    if (error.response?.statusCode == 404) return 'Объект не найден или недоступен.';
    if (error.response?.statusCode == 429) return 'Слишком много запросов. Попробуйте позже.';
    final data = error.response?.data;
    if (data is Map) return data.entries.map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}').join('\n');
    if (data is List) return data.join('\n');
    if (error.response == null) return 'Не удалось связаться с сервером. Проверьте интернет и запуск API.';
    return 'Ошибка сервера. Попробуйте позже.';
  }
  return 'Не удалось выполнить действие. Попробуйте ещё раз.';
}
