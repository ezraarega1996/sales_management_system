import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:inventory_frontend/config.dart' as config;
import 'package:inventory_frontend/utils/connection_status.dart';
import 'package:inventory_frontend/utils/local_cache.dart';
import 'package:inventory_frontend/utils/storage.dart';

/// The server could not be reached (no signal, timeout, DNS failure...).
class OfflineException implements Exception {
  final String message;
  const OfflineException([this.message = 'No internet connection. Showing saved data where available.']);
  @override
  String toString() => message;
}

/// The server answered with an error status.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  /// 4xx except timeouts / rate limiting: retrying the same request will not help.
  bool get isPermanent => statusCode >= 400 && statusCode < 500 && statusCode != 408 && statusCode != 429;

  @override
  String toString() => message;
}

/// Result of [Api.getCached]: fresh server data, or the last saved copy when offline.
class CachedResponse {
  final dynamic data;
  final bool fromCache;
  final DateTime savedAt;
  const CachedResponse(this.data, {required this.fromCache, required this.savedAt});
}

class Api {
  static String baseUrl = config.baseUrl;

  /// One shared client keeps connections alive, avoiding a new TCP handshake per request
  /// (expensive on high-latency mobile networks). Responses are gzip-decoded automatically.
  static final http.Client _client = http.Client();

  static const Duration _readTimeout = Duration(seconds: 15);
  static const Duration _writeTimeout = Duration(seconds: 20);

  /// Called when the server rejects the session (HTTP 401), e.g. to log the user out.
  static void Function()? onUnauthorized;

  static Future<dynamic> get(String endpoint) => _send('GET', endpoint, retries: 2);

  static Future<dynamic> post(String endpoint, Map<String, dynamic> data) => _send('POST', endpoint, body: data);

  static Future<dynamic> put(String endpoint, Map<String, dynamic> data) => _send('PUT', endpoint, body: data);

  static Future<dynamic> delete(String endpoint) => _send('DELETE', endpoint);

  /// GET that saves successful responses on the device and falls back to the saved copy when
  /// the server can't be reached. Throws [OfflineException] only if nothing was saved yet.
  static Future<CachedResponse> getCached(String endpoint) async {
    try {
      final data = await get(endpoint);
      await LocalCache.write(endpoint, data);
      return CachedResponse(data, fromCache: false, savedAt: DateTime.now());
    } on OfflineException {
      final cached = await LocalCache.read(endpoint);
      if (cached == null) rethrow;
      ConnectionStatus.instance.noteSavedData(cached.savedAt);
      return CachedResponse(cached.data, fromCache: true, savedAt: cached.savedAt);
    }
  }

  static Future<dynamic> _send(String method, String endpoint, {Map<String, dynamic>? body, int retries = 0}) async {
    final uri = Uri.parse('$baseUrl/$endpoint');
    final token = await Storage.getToken();
    final headers = {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};

    for (var attempt = 0; ; attempt++) {
      try {
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) request.body = jsonEncode(body);
        final timeout = method == 'GET' ? _readTimeout : _writeTimeout;
        final streamed = await _client.send(request).timeout(timeout);
        final response = await http.Response.fromStream(streamed).timeout(timeout);
        ConnectionStatus.instance.markOnline();
        return _handleResponse(response, endpoint);
      } on SocketException {
        if (attempt >= retries) return _offline();
      } on TimeoutException {
        if (attempt >= retries) return _offline();
      } on http.ClientException {
        if (attempt >= retries) return _offline();
      } on HandshakeException {
        if (attempt >= retries) return _offline();
      }
      // Back off before retrying (GETs only): 1s, then 2s
      await Future.delayed(Duration(seconds: attempt + 1));
    }
  }

  static Never _offline() {
    ConnectionStatus.instance.markOffline();
    throw const OfflineException();
  }

  static dynamic _handleResponse(http.Response response, String endpoint) {
    final status = response.statusCode;
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (status >= 200 && status < 300) return decoded;

    if (status == 401 && endpoint != 'auth/login') onUnauthorized?.call();

    final message =
        decoded is Map && decoded['message'] is String ? decoded['message'] as String : 'Server error ($status)';
    throw ApiException(status, message);
  }
}
