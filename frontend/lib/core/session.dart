import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class Session extends ChangeNotifier {
  Session(this.api) {
    api.onSessionExpired = () {
      user = null;
      notifyListeners();
    };
  }
  final ApiClient api;
  Map<String, dynamic>? user;
  bool loading = true;
  String? restoreError;
  bool get isCarrier => user?['role'] == 'carrier';
  int get userId => user!['id'] as int;
  String get name => (user?['first_name'] as String?)?.isNotEmpty == true
      ? user!['first_name'] as String
      : 'Пользователь';

  Future<void> initialize() async {
    loading = true;
    restoreError = null;
    notifyListeners();
    try {
      await api.restore();
      if (api.access != null) user = await api.get('/auth/me');
    } catch (e) {
      if (api.access != null) restoreError = errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final response = await api.dio.post('/auth/login',
        data: {'email': email.trim(), 'password': password},
        options: Options(extra: {'public': true}));
    await api.saveTokens(Map<String, dynamic>.from(response.data as Map));
    user = await api.get('/auth/me');
    notifyListeners();
  }

  Future<void> register(Map<String, dynamic> data) async {
    await api.dio.post('/auth/register',
        data: data, options: Options(extra: {'public': true}));
    await login(data['email'] as String, data['password'] as String);
  }

  Future<void> reloadProfile() async {
    user = await api.get('/auth/me');
    notifyListeners();
  }

  Future<void> logout() async {
    await api.clearTokens();
    user = null;
    restoreError = null;
    notifyListeners();
  }
}
