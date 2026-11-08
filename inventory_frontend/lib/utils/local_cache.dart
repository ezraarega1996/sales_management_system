import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A cached JSON value and when it was saved.
class CachedValue {
  final dynamic data;
  final DateTime savedAt;
  const CachedValue(this.data, this.savedAt);
}

/// Small on-device JSON cache, so screens can show the last known data without a connection.
/// Entries are namespaced per user so one account never sees another account's data.
class LocalCache {
  static const _prefix = 'cache:';
  static String _namespace = 'anonymous';

  static void setUser(String? userId) => _namespace = userId ?? 'anonymous';

  static String _key(String key) => '$_prefix$_namespace:$key';

  static Future<void> write(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'data': data}));
  }

  static Future<CachedValue?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(key));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedValue(decoded['data'], DateTime.parse(decoded['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }

  /// Removes every cached entry (all users). Used on logout.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(key);
    }
  }
}
