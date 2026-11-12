import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inventory_frontend/models/sales_data.dart';
import 'package:inventory_frontend/providers/basket_provider.dart';
import 'package:inventory_frontend/models/sold_item.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/utils/api.dart';

class SalesProvider with ChangeNotifier {
  SalesProvider({SaleOutbox? outbox}) : _outbox = outbox ?? SaleOutbox.instance {
    _outbox.addListener(notifyListeners);
    _syncedSub = _outbox.synced.listen(_onSaleSynced);
  }

  final SaleOutbox _outbox;
  late final StreamSubscription<SyncedSale> _syncedSub;

  List<SoldItem> _sales = [];
  bool _isLoading = false;
  String? _error;
  bool _fromCache = false;
  Map<String, dynamic>? _dashboardStats;
  double? _totalSales;
  int? _totalItemsSold;
  double? _todaySales;
  List<SalesData> _todaySalesData = [];

  /// Read-only view, rebuilt only after a change (every change goes through notifyListeners).
  /// Screens can also use its identity to tell whether the sales changed since their last build.
  List<SoldItem> get sales => _salesView ??= List.unmodifiable(_sales);
  List<SoldItem>? _salesView;

  @override
  void notifyListeners() {
    _salesView = null;
    super.notifyListeners();
  }
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isShowingSavedData => _fromCache;
  Map<String, dynamic>? get dashboardStats => _dashboardStats;
  double? get totalSales => _totalSales;
  int? get totalItemsSold => _totalItemsSold;
  double? get todaySales => _todaySales;
  List<SalesData> get todaySalesData => _todaySalesData;

  /// Sales recorded on this phone that the server has not confirmed yet (including failed ones).
  List<PendingSale> get unsyncedSales => [..._outbox.failed, ..._outbox.pending.reversed];

  /// Runs [load], tracking loading/error state. On failure the previous data stays visible.
  Future<void> _run(Future<void> Function() load) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await load();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<SoldItem> _parseSales(dynamic data) {
    final sales = (data as List).map((x) => SoldItem.fromJson(x)).toList();
    sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sales;
  }

  Future<void> fetchSales() => _run(() async {
    final response = await Api.getCached('sales');
    _sales = _parseSales(response.data);
    _fromCache = response.fromCache;
    _totalItemsSold = _sales.length;
    _totalSales = _sales.fold<double>(0.0, (sum, item) => sum + item.soldPrice);
  });

  Future<void> fetchUserSales() => _run(() async {
    final response = await Api.getCached('sales/user');
    _sales = _parseSales(response.data);
    _fromCache = response.fromCache;
  });

  Future<void> fetchTodaySales() => _run(() async {
    final response = await Api.getCached('available-items/today-sales');
    final data = response.data as Map<String, dynamic>;
    _todaySales = (data['totalSales'] as num?)?.toDouble() ?? 0;
    _todaySalesData = ((data['salesBySalesman'] as List?) ?? const []).map((json) => SalesData.fromJson(json)).toList();
  });

  Future<void> fetchDashboardStats() => _run(() async {
    final response = await Api.getCached('sales/dashboard');
    final data = response.data as Map<String, dynamic>;
    _dashboardStats = data;
    _fromCache = response.fromCache;
    // JSON numbers without a fraction (e.g. 4955) decode as int, so convert via num
    _totalSales = (data['totalSales'] as num?)?.toDouble();
    _totalItemsSold = (data['salesCount'] as num?)?.toInt();
    _todaySales = (data['todaySales'] as num?)?.toDouble();
  });

  /// Records a basket offline-first: it is saved on the phone immediately and sent to the server
  /// in the background (now, or when the connection comes back) as one receipt.
  ///
  /// Waits up to [confirmWithin] for the server and returns the queued sale plus whether the
  /// server already confirmed it (false = safely saved on the phone, will sync later).
  Future<({PendingSale sale, bool confirmed})> checkout(
    List<BasketLine> lines, {
    Duration confirmWithin = const Duration(seconds: 3),
  }) async {
    final stockUnits = <String, double>{};
    for (final line in lines) {
      stockUnits[line.stock.id] = (stockUnits[line.stock.id] ?? 0) + line.units;
    }
    final names = lines.map((l) => '${l.itemName} ×${_qty(l.quantity)}').toList();
    final title = names.length <= 3 ? names.join(', ') : '${names.take(3).join(', ')} +${names.length - 3}';

    final sale = await _outbox.enqueueBasket(
      shopId: lines.first.stock.shopId,
      lines: [
        for (final l in lines)
          {
            'itemId': l.stock.itemId,
            'fractionId': l.fraction.id,
            'quantity': l.quantity,
            'amount': l.amount,
            'profit': l.profit,
          },
      ],
      stockUnits: stockUnits,
      title: title,
    );
    await _outbox.sync().timeout(confirmWithin, onTimeout: () => 0);
    return (sale: sale, confirmed: !_outbox.isPending(sale.clientId));
  }

  /// Cancels a just-made sale. If it is still on the phone it is simply dropped; otherwise the
  /// server puts the stock back (salesmen: own sales, within 10 minutes). Throws on failure.
  Future<void> undoSale(PendingSale sale) async {
    // If it is being sent right now, wait for that to finish: otherwise dropping the phone's copy
    // wouldn't stop the upload, and the sale would be recorded anyway
    await _outbox.waitWhileSending(sale.clientId);
    if (_outbox.isPending(sale.clientId)) {
      await _outbox.discard(sale.clientId);
      return;
    }
    await Api.delete('sales/receipt/${sale.clientId}');
    _sales.removeWhere((s) => s.receiptId == sale.clientId);
    notifyListeners();
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

  Future<void> syncNow() => _outbox.sync();
  Future<void> retryUnsynced(String clientId) => _outbox.retry(clientId);
  Future<void> discardUnsynced(String clientId) => _outbox.discard(clientId);

  void _onSaleSynced(SyncedSale synced) {
    final response = synced.serverResponse;
    final created = response is List ? response : [response];
    var changed = false;
    for (final json in created.whereType<Map<String, dynamic>>()) {
      final sale = SoldItem.fromJson(json);
      if (_sales.any((s) => s.id == sale.id)) continue;
      _sales.insert(0, sale);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<bool> deleteSale(String id) async {
    _error = null;
    try {
      await Api.delete('sales/$id');
      _sales.removeWhere((sale) => sale.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _outbox.removeListener(notifyListeners);
    _syncedSub.cancel();
    super.dispose();
  }

  /// Forgets everything loaded for the signed-in user (called on logout), so the next person
  /// using this phone never sees it.
  void reset() {
    _sales = [];
    _isLoading = false;
    _error = null;
    _fromCache = false;
    _dashboardStats = null;
    _totalSales = null;
    _totalItemsSold = null;
    _todaySales = null;
    _todaySalesData = [];
    notifyListeners();
  }
}
