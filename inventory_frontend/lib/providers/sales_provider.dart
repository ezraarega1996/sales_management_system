import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inventory_frontend/models/sales_data.dart';
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

  List<SoldItem> get sales => [..._sales];
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

  /// Records a sale offline-first: it is saved on the phone immediately and sent to the server
  /// in the background (now, or when the connection comes back).
  ///
  /// Waits up to [confirmWithin] for the server; returns true if it confirmed the sale in that
  /// time, false if the sale is safely queued on the phone and will sync later.
  Future<bool> createSale(
    Map<String, dynamic> saleData, {
    required String availableItemId,
    required double units,
    required String itemName,
    required String fractionName,
    Duration confirmWithin = const Duration(seconds: 3),
  }) async {
    final sale = await _outbox.enqueue(
      payload: saleData,
      availableItemId: availableItemId,
      units: units,
      itemName: itemName,
      fractionName: fractionName,
    );
    await _outbox.sync().timeout(confirmWithin, onTimeout: () => 0);
    return !_outbox.pending.any((s) => s.clientId == sale.clientId);
  }

  Future<void> syncNow() => _outbox.sync();
  Future<void> retryUnsynced(String clientId) => _outbox.retry(clientId);
  Future<void> discardUnsynced(String clientId) => _outbox.discard(clientId);

  void _onSaleSynced(SyncedSale synced) {
    if (synced.serverSale is! Map<String, dynamic>) return;
    final sale = SoldItem.fromJson(synced.serverSale as Map<String, dynamic>);
    if (_sales.any((s) => s.id == sale.id)) return;
    _sales.insert(0, sale);
    notifyListeners();
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
}
