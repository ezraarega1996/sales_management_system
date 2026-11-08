import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:inventory_frontend/utils/api.dart';

/// A sale recorded on the phone that has not been confirmed by the server yet.
class PendingSale {
  final String clientId;

  /// Body for `POST /sales` (includes `clientId` and `soldTime`).
  final Map<String, dynamic> payload;

  /// Stock row the sale takes from, and how many base units, so stock can be shown
  /// correctly before the server confirms the sale.
  final String? availableItemId;
  final double units;

  final String itemName;
  final String fractionName;
  final DateTime createdAt;

  /// Set when the server permanently rejected the sale (e.g. not enough stock).
  final String? error;

  const PendingSale({
    required this.clientId,
    required this.payload,
    required this.availableItemId,
    required this.units,
    required this.itemName,
    required this.fractionName,
    required this.createdAt,
    this.error,
  });

  bool get isFailed => error != null;
  double get amount => (payload['amount'] as num?)?.toDouble() ?? 0;
  double get quantity => (payload['quantity'] as num?)?.toDouble() ?? 0;

  PendingSale withError(String? error) => PendingSale(
    clientId: clientId,
    payload: payload,
    availableItemId: availableItemId,
    units: units,
    itemName: itemName,
    fractionName: fractionName,
    createdAt: createdAt,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'payload': payload,
    'availableItemId': availableItemId,
    'units': units,
    'itemName': itemName,
    'fractionName': fractionName,
    'createdAt': createdAt.toIso8601String(),
    'error': error,
  };

  factory PendingSale.fromJson(Map<String, dynamic> json) => PendingSale(
    clientId: json['clientId'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    availableItemId: json['availableItemId'] as String?,
    units: (json['units'] as num).toDouble(),
    itemName: json['itemName'] as String? ?? '',
    fractionName: json['fractionName'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    error: json['error'] as String?,
  );
}

/// Where the queue is persisted. Swappable for tests.
abstract class OutboxStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String value);
}

class PrefsOutboxStore implements OutboxStore {
  String _key(String userId) => 'sale_outbox:$userId';

  @override
  Future<String?> read(String userId) async => (await SharedPreferences.getInstance()).getString(_key(userId));

  @override
  Future<void> write(String userId, String value) async =>
      (await SharedPreferences.getInstance()).setString(_key(userId), value);
}

/// Sends one sale to the server and returns the created sale JSON.
typedef SaleSender = Future<dynamic> Function(Map<String, dynamic> payload);

/// Emitted when a queued sale has been accepted by the server.
class SyncedSale {
  final PendingSale sale;
  final dynamic serverSale;
  const SyncedSale(this.sale, this.serverSale);
}

/// Offline-first queue for sales.
///
/// Sales are saved on the phone first and sent when the server can be reached. Each sale carries
/// a `clientId`, so resending after a lost response never records it twice (the server
/// deduplicates). Sales the server rejects for good (4xx) are kept as failed and shown to the
/// user instead of being retried forever.
class SaleOutbox extends ChangeNotifier {
  SaleOutbox({SaleSender? sender, OutboxStore? store, this.retryInterval = const Duration(seconds: 30)})
    : _sender = sender ?? ((payload) => Api.post('sales', payload)),
      _store = store ?? PrefsOutboxStore();

  static final SaleOutbox instance = SaleOutbox();

  final SaleSender _sender;
  final OutboxStore _store;

  /// How often to retry while sales are waiting; null disables the timer (tests).
  final Duration? retryInterval;

  final _synced = StreamController<SyncedSale>.broadcast();
  List<PendingSale> _items = [];
  String? _userId;
  bool _syncing = false;
  Timer? _timer;

  Stream<SyncedSale> get synced => _synced.stream;
  List<PendingSale> get pending => _items.where((s) => !s.isFailed).toList();
  List<PendingSale> get failed => _items.where((s) => s.isFailed).toList();
  bool get isSyncing => _syncing;
  bool get hasUnsynced => _items.isNotEmpty;

  /// Base units of [availableItemId] sold on the phone but not yet confirmed by the server.
  double pendingUnitsFor(String availableItemId) =>
      pending.where((s) => s.availableItemId == availableItemId).fold(0.0, (sum, s) => sum + s.units);

  /// Loads the queue of the logged-in user (each user has their own queue).
  Future<void> switchUser(String? userId) async {
    _timer?.cancel();
    _userId = userId;
    _items = [];
    if (userId != null) {
      final raw = await _store.read(userId);
      if (raw != null) {
        try {
          _items = (jsonDecode(raw) as List).map((e) => PendingSale.fromJson(Map<String, dynamic>.from(e))).toList();
        } catch (_) {
          _items = [];
        }
      }
    }
    _scheduleRetry();
    notifyListeners();
  }

  /// Saves a sale on the phone. Call [sync] afterwards to send it.
  Future<PendingSale> enqueue({
    required Map<String, dynamic> payload,
    required String? availableItemId,
    required double units,
    required String itemName,
    required String fractionName,
    DateTime? now,
  }) async {
    final soldAt = now ?? DateTime.now();
    final clientId = const Uuid().v4();
    final sale = PendingSale(
      clientId: clientId,
      payload: {...payload, 'clientId': clientId, 'soldTime': soldAt.toUtc().toIso8601String()},
      availableItemId: availableItemId,
      units: units,
      itemName: itemName,
      fractionName: fractionName,
      createdAt: soldAt,
    );
    _items.add(sale);
    await _persist();
    _scheduleRetry();
    notifyListeners();
    return sale;
  }

  /// Sends waiting sales oldest-first. Stops at the first network problem (to retry later).
  /// Returns how many sales the server accepted.
  Future<int> sync() async {
    if (_syncing || pending.isEmpty) return 0;
    _syncing = true;
    notifyListeners();
    var sent = 0;
    try {
      for (final sale in pending) {
        try {
          final serverSale = await _sender(sale.payload);
          _items.removeWhere((s) => s.clientId == sale.clientId);
          sent++;
          await _persist();
          _synced.add(SyncedSale(sale, serverSale));
          notifyListeners();
        } on ApiException catch (e) {
          // 401 = session expired: keep the sale and retry after the user logs in again
          if (!e.isPermanent || e.statusCode == 401) break;
          _replace(sale.withError(e.message));
          await _persist();
          notifyListeners();
        } catch (_) {
          break; // offline / timeout / unexpected: keep it and retry later
        }
      }
    } finally {
      _syncing = false;
      _scheduleRetry();
      notifyListeners();
    }
    return sent;
  }

  /// Moves a failed sale back to the queue and tries to send it again.
  Future<void> retry(String clientId) async {
    final sale = _items.where((s) => s.clientId == clientId).firstOrNull;
    if (sale == null) return;
    _replace(sale.withError(null));
    await _persist();
    notifyListeners();
    await sync();
  }

  /// Drops a failed sale (e.g. it was a mistake and the server rejected it).
  Future<void> discard(String clientId) async {
    _items.removeWhere((s) => s.clientId == clientId);
    await _persist();
    _scheduleRetry();
    notifyListeners();
  }

  void _replace(PendingSale sale) {
    final i = _items.indexWhere((s) => s.clientId == sale.clientId);
    if (i != -1) _items[i] = sale;
  }

  Future<void> _persist() async {
    final userId = _userId;
    if (userId == null) return;
    await _store.write(userId, jsonEncode(_items.map((s) => s.toJson()).toList()));
  }

  void _scheduleRetry() {
    final interval = retryInterval;
    if (interval == null) return;
    if (pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(interval, (_) => sync());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _synced.close();
    super.dispose();
  }
}
