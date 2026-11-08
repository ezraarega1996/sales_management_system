import 'package:flutter/foundation.dart';

/// App-wide online/offline state, updated by [Api] after every request.
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus._();
  static final ConnectionStatus instance = ConnectionStatus._();

  bool _isOffline = false;
  DateTime? _offlineSince;

  bool get isOffline => _isOffline;
  DateTime? get offlineSince => _offlineSince;

  void markOnline() {
    if (!_isOffline) return;
    _isOffline = false;
    _offlineSince = null;
    notifyListeners();
  }

  void markOffline() {
    if (_isOffline) return;
    _isOffline = true;
    _offlineSince = DateTime.now();
    notifyListeners();
  }
}
