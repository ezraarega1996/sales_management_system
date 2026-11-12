import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:inventory_frontend/utils/api.dart';

/// A sale (one basket / receipt) recorded on the phone that the server has not confirmed yet.
class PendingSale {
  final String clientId;

  /// Body sent to the server. Baskets: `{shopId, lines: [...], clientId, soldTime}` for
  /// `POST /sales/batch`. Older single-item entries (no `lines`) go to `POST /sales`.
  final Map<String, dynamic> payload;

  /// Base units taken from each stock row (availableItemId -> units), so stock can be shown
  /// correctly before the server confirms the sale.
  final Map<String, double> stockUnits;

  /// Short description for lists, e.g. "Coca-Cola ×3, Sugar ×2".
  final String title;
  final int itemCount;
  final DateTime createdAt;

  /// Set when the server permanently rejected the sale (e.g. not enough stock).
  final String? error;

  const PendingSale({
    required this.clientId,
    required this.payload,
    required this.stockUnits,
    required this.title,
    required this.itemCount,
    required this.createdAt,
    this.error,
  });

  bool get isFailed => error != null;
  bool get isBasket => payload['lines'] is List;
  String get endpoint => isBasket ? 'sales/batch' : 'sales';

  double get amount =>
      isBasket
          ? (payload['lines'] as List).fold(0.0, (sum, l) => sum + ((l as Map)['amount'] as num).toDouble())
          : (payload['amount'] as num?)?.toDouble() ?? 0;

  PendingSale withError(String? error) => PendingSale(
    clientId: clientId,
    payload: payload,
    stockUnits: stockUnits,
    title: title,
    itemCount: itemCount,
    createdAt: createdAt,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'payload': payload,
    'stockUnits': stockUnits,
    'title': title,
    'itemCount': itemCount,
    'createdAt': createdAt.toIso8601String(),
    'error': error,
  };

  factory PendingSale.fromJson(Map<String, dynamic> json) {
    // Entries saved by the previous app version stored one stock row and an item/unit name
    final stockUnits =
        json['stockUnits'] != null
            ? (json['stockUnits'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
            : {
              if (json['availableItemId'] != null) json['availableItemId'] as String: (json['units'] as num).toDouble(),
            };
    return PendingSale(
      clientId: json['clientId'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      stockUnits: stockUnits,
      title: json['title'] as String? ?? '${json['itemName'] ?? ''} ${json['fractionName'] ?? ''}'.trim(),
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(json['createdAt'] as String),
      error: json['error'] as String?,
    );
  }
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

/// Sends one queued sale to [endpoint] and returns the server's response.
typedef SaleSender = Future<dynamic> Function(String endpoint, Map<String, dynamic> payload);

/// Emitted when a queued sale has been accepted by the server.
class SyncedSale {
  final PendingSale sale;

  /// Created sale lines: a list for baskets, a single map for older single-item entries.
  final dynamic serverResponse;
  const SyncedSale(this.sale, this.serverResponse);
}

/// Offline-first queue for sales.
///
/// Sales are saved on the phone first and sent when the server can be reached. Each sale carries
/// a `clientId`, so resending after a lost response never records it twice (the server
/// deduplicates). Sales the server rejects for good (4xx) are kept as failed and shown to the
/// user instead of being retried forever.
class SaleOutbox extends ChangeNotifier {
  SaleOutbox({SaleSender? sender, OutboxStore? store, this.retryInterval = const Duration(seconds: 30)})
    : _sender = sender ?? ((endpoint, payload) => Api.post(endpoint, payload)),
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

  /// The sale being sent right now, and a future that completes when that send is over.
  String? _sendingId;
  Completer<void>? _sendDone;
  Timer? _timer;

  Stream<SyncedSale> get synced => _synced.stream;
  List<PendingSale> get pending => _items.where((s) => !s.isFailed).toList();
  List<PendingSale> get failed => _items.where((s) => s.isFailed).toList();
  bool get isSyncing => _syncing;
  bool get hasUnsynced => _items.isNotEmpty;

  /// Base units of [availableItemId] sold on the phone but not yet confirmed by the server.
  double pendingUnitsFor(String availableItemId) =>
      pending.fold(0.0, (sum, s) => sum + (s.stockUnits[availableItemId] ?? 0));

  /// Loads the queue of the logged-in user (each user has their own queue).
  Future<void> switchUser(String? userId) async {
    _timer?.cancel();
    _timer = null;
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

  /// Saves a basket on the phone. Call [sync] afterwards to send it.
  Future<PendingSale> enqueueBasket({
    required String shopId,
    required List<Map<String, dynamic>> lines,
    required Map<String, double> stockUnits,
    required String title,
    DateTime? now,
  }) async {
    final soldAt = now ?? DateTime.now();
    final clientId = const Uuid().v4();
    final sale = PendingSale(
      clientId: clientId,
      payload: {'shopId': shopId, 'lines': lines, 'clientId': clientId, 'soldTime': soldAt.toUtc().toIso8601String()},
      stockUnits: stockUnits,
      title: title,
      itemCount: lines.length,
      createdAt: soldAt,
    );
    _items.add(sale);
    await _persist();
    _scheduleRetry();
    notifyListeners();
    return sale;
  }

  /// Whether [clientId] is still waiting on the phone (not yet confirmed by the server).
  bool isPending(String clientId) => _items.any((s) => s.clientId == clientId && !s.isFailed);

  /// If [clientId] is being sent right now, waits until that attempt is over (sent or failed), so
  /// an undo can then tell whether the sale reached the server. Returns at once otherwise.
  Future<void> waitWhileSending(String clientId) async {
    while (_sendingId == clientId && _sendDone != null) {
      await _sendDone!.future;
    }
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
        // Undone/discarded while earlier sales were being sent: don't send it
        if (!_items.any((s) => s.clientId == sale.clientId)) continue;
        _sendingId = sale.clientId;
        _sendDone = Completer<void>();
        try {
          final response = await _sender(sale.endpoint, sale.payload);
          _items.removeWhere((s) => s.clientId == sale.clientId);
          sent++;
          await _persist();
          _synced.add(SyncedSale(sale, response));
          notifyListeners();
        } on ApiException catch (e) {
          // 401 = session expired: keep the sale and retry after the user logs in again
          if (!e.isPermanent || e.statusCode == 401) break;
          _replace(sale.withError(e.message));
          await _persist();
          notifyListeners();
        } catch (_) {
          break; // offline / timeout / unexpected: keep it and retry later
        } finally {
          _sendingId = null;
          _sendDone?.complete();
          _sendDone = null;
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

  /// Drops a sale that is still on the phone (a failed one, or one just undone before syncing).
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
