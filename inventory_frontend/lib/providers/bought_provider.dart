import 'package:flutter/material.dart';
import 'package:inventory_frontend/models/bought.dart';
import 'package:inventory_frontend/utils/api.dart';

class BoughtProvider with ChangeNotifier {
  List<Bought> _boughts = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  List<Bought> get boughts => _boughts;

  /// True while the list is being fetched.
  bool get isLoading => _isLoading;

  /// True while a purchase is being created, updated or deleted.
  bool get isSaving => _isSaving;

  String? get error => _error;

  Future<void> fetchBoughts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = (await Api.getCached('boughts')).data;
      _boughts = List<Bought>.from(response.map((x) => Bought.fromJson(x)));
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createBought({
    required String itemId,
    required String fractionId,
    required double fractionPurchasePrice,
    required double fractionSoldPrice,
    required double quantity,
    DateTime? expiryDate,
    String? shopId,
    String? clientId,
  }) async {
    return _mutate(() async {
      final response = await Api.post('boughts', {
        // Same id on every retry of this save, so the server records the purchase only once
        if (clientId != null) 'clientId': clientId,
        'itemId': itemId,
        'fractionId': fractionId,
        'fractionPurchasePrice': fractionPurchasePrice,
        'fractionSoldPrice': fractionSoldPrice,
        'quantity': quantity,
        'expiryDate': expiryDate?.toIso8601String(),
        'shopId': shopId,
      });
      // A new list (not an in-place insert) so screens that cache on the list identity regroup
      final bought = Bought.fromJson(response);
      _boughts = [bought, ..._boughts.where((b) => b.id != bought.id)];
    });
  }

  Future<bool> updateBought({
    required String id,
    String? fractionId,
    double? fractionPurchasePrice,
    double? fractionSoldPrice,
    double? quantity,
    DateTime? expiryDate,
    String? shopId,
  }) async {
    return _mutate(() async {
      final response = await Api.put('boughts/$id', {
        'fractionId': fractionId,
        'fractionPurchasePrice': fractionPurchasePrice,
        'fractionSoldPrice': fractionSoldPrice,
        'quantity': quantity,
        'expiryDate': expiryDate?.toIso8601String(),
        'shopId': shopId,
      });
      final updated = Bought.fromJson(response);
      _boughts = [
        for (final b in _boughts)
          if (b.id == id) _keepRelations(updated, b) else b,
      ];
    });
  }

  Future<bool> deleteBought(String id) async {
    return _mutate(() async {
      await Api.delete('boughts/$id');
      _boughts = _boughts.where((t) => t.id != id).toList();
    });
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Keeps the item and shop of the old row when the server response didn't include them.
  static Bought _keepRelations(Bought updated, Bought old) {
    if (updated.item != null && (updated.shop != null || updated.shopId == null)) return updated;
    return Bought(
      id: updated.id,
      fractionId: updated.fractionId,
      fractionPurchasePrice: updated.fractionPurchasePrice,
      fractionSoldPrice: updated.fractionSoldPrice,
      quantity: updated.quantity,
      expiryDate: updated.expiryDate,
      createdTime: updated.createdTime,
      itemId: updated.itemId,
      item: updated.item ?? old.item,
      fraction: updated.fraction ?? old.fraction,
      shopId: updated.shopId,
      shop: updated.shop ?? (updated.shopId == old.shopId ? old.shop : null),
      available_items_count: updated.available_items_count,
    );
  }

  /// Forgets everything loaded for the signed-in user (called on logout), so the next person
  /// using this phone never sees it.
  void reset() {
    _boughts = [];
    _isLoading = false;
    _isSaving = false;
    _error = null;
    notifyListeners();
  }
}
