import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/utils/api.dart';
import 'package:inventory_frontend/utils/local_cache.dart';

class AvailableItemProvider with ChangeNotifier {
  AvailableItemProvider({SaleOutbox? outbox}) : _outbox = outbox ?? SaleOutbox.instance {
    _outbox.addListener(notifyListeners);
    _syncedSub = _outbox.synced.listen(_onSaleSynced);
  }

  static const _freshFor = Duration(seconds: 60);

  final SaleOutbox _outbox;
  late final StreamSubscription<SyncedSale> _syncedSub;
  Timer? _refreshDebounce;

  /// Stock as last reported by the server (or the saved copy when offline).
  List<AvailableItem> _serverItems = [];
  String? _endpoint;
  DateTime? _fetchedAt;
  bool _fromCache = false;
  bool _isLoading = false;
  String? _error;

  /// Stock to show: server quantity minus sales recorded on this phone that are still syncing.
  List<AvailableItem> get availableItems => _serverItems.map(_withPendingSales).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True when the list comes from the phone's saved copy because the server was unreachable.
  bool get isShowingSavedData => _fromCache;
  DateTime? get lastUpdated => _fetchedAt;

  AvailableItem _withPendingSales(AvailableItem item) {
    final pending = _outbox.pendingUnitsFor(item.id);
    return pending == 0 ? item : item.withQuantity(math.max(0, item.quantity - pending));
  }

  /// Loads stock. With [force] false, data fetched in the last minute is reused instead of
  /// downloading it again.
  Future<void> fetchAvailableItems({String? shopId, bool force = true}) async {
    final endpoint = (shopId != null && shopId.isNotEmpty) ? 'available-items?shopId=$shopId' : 'available-items';
    final fresh =
        _endpoint == endpoint &&
        !_fromCache &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < _freshFor;
    if (!force && fresh) return;

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await Api.getCached(endpoint);
      _serverItems = (response.data as List).map((item) => AvailableItem.fromJson(item)).toList();
      _endpoint = endpoint;
      _fromCache = response.fromCache;
      _fetchedAt = response.savedAt;
    } catch (e) {
      // Keep showing what we already have
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// A queued sale reached the server: make the deduction permanent locally right away, then
  /// refresh from the server shortly after to pick up the authoritative numbers.
  void _onSaleSynced(SyncedSale synced) {
    final id = synced.sale.availableItemId;
    final index = _serverItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = _serverItems[index];
      _serverItems[index] = item.withQuantity(math.max(0, item.quantity - synced.sale.units));
      final endpoint = _endpoint;
      if (endpoint != null) {
        LocalCache.write(endpoint, _serverItems.map((i) => i.toJson()).toList());
      }
      notifyListeners();
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(seconds: 2), () {
      if (_endpoint != null && _outbox.pending.isEmpty) {
        fetchAvailableItems(shopId: Uri.parse(_endpoint!).queryParameters['shopId']);
      }
    });
  }

  Future<void> fetchAvailableItemTransactions(String availableItemId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await Api.get('available-items/$availableItemId/transactions');
      final index = _serverItems.indexWhere((i) => i.id == availableItemId);
      if (response != null && index != -1) {
        _serverItems[index] = AvailableItem.fromJson({
          ..._serverItems[index].toJson(),
          'boughtTransactions': response['boughtTransactions'],
          'soldTransactions': response['soldTransactions'],
        });
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  AvailableItem? getAvailableItem(String availableItemId) {
    final item = _serverItems.where((i) => i.id == availableItemId).firstOrNull;
    return item == null ? null : _withPendingSales(item);
  }

  @override
  void dispose() {
    _outbox.removeListener(notifyListeners);
    _syncedSub.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }
}
