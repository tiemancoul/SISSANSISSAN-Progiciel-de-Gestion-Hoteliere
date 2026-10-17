import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the Laravel API and keeps the Sanctum token between visits.
class ApiClient {
  ApiClient(this._prefs);

  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000/api',
  );
  static const _tokenKey = 'auth_token';

  final SharedPreferences _prefs;

  bool get hasToken => _prefs.getString(_tokenKey) != null;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final body = await _send('POST', '/login', {
      'email': email,
      'password': password,
    });
    await _prefs.setString(_tokenKey, body['token'] as String);
    return body['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() => _send('GET', '/me');

  Future<void> logout() async {
    try {
      await _send('POST', '/logout');
    } finally {
      await _prefs.remove(_tokenKey);
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_prefs.getString(_tokenKey) case final token?)
          'Authorization': 'Bearer $token',
      });
    if (data != null) request.body = jsonEncode(data);

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 401) await _prefs.remove(_tokenKey);
    if (response.statusCode == 204) return {};

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        body['message'] as String? ?? 'Erreur ${response.statusCode}',
        response.statusCode,
      );
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
