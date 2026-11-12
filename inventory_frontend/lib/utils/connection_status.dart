import 'package:flutter/foundation.dart';

/// App-wide online/offline state, updated by [Api] after every request.
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus._();
  static final ConnectionStatus instance = ConnectionStatus._();

  bool _isOffline = false;
  DateTime? _offlineSince;
  DateTime? _savedDataFrom;

  bool get isOffline => _isOffline;
  DateTime? get offlineSince => _offlineSince;

  /// While offline: when the oldest saved data shown on screen was downloaded, so people know how
  /// stale stock and sales may be. Null when online or when nothing saved was shown.
  DateTime? get savedDataFrom => _savedDataFrom;

  /// Called when a screen falls back to data saved at [savedAt].
  void noteSavedData(DateTime savedAt) {
    if (_savedDataFrom != null && !savedAt.isBefore(_savedDataFrom!)) return;
    _savedDataFrom = savedAt;
    notifyListeners();
  }

  void markOnline() {
    if (!_isOffline) return;
    _isOffline = false;
    _offlineSince = null;
    _savedDataFrom = null;
    notifyListeners();
  }

  void markOffline() {
    if (_isOffline) return;
    _isOffline = true;
    _offlineSince = DateTime.now();
    notifyListeners();
  }
}
