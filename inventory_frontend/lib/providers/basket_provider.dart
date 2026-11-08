import 'package:flutter/foundation.dart';

import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/models/fraction.dart';

/// One line of the basket: [quantity] of [fraction] (unit) taken from the [stock] row.
class BasketLine {
  final AvailableItem stock;
  final Fraction fraction;
  final double quantity;

  /// Price per unit when the owner overrides it for this sale; null = catalogue price.
  final double? priceOverride;

  const BasketLine({required this.stock, required this.fraction, required this.quantity, this.priceOverride});

  String get key => '${stock.id}:${fraction.id}';
  String get itemName => stock.item?.name ?? '';
  double get unitPrice => priceOverride ?? fraction.sellingPrice;
  double get amount => unitPrice * quantity;
  double get profit => (unitPrice - fraction.purchasePrice) * quantity;

  /// Base units this line takes from stock.
  double get units => quantity * fraction.ratio;

  BasketLine copyWith({AvailableItem? stock, Fraction? fraction, double? quantity, double? priceOverride}) =>
      BasketLine(
        stock: stock ?? this.stock,
        fraction: fraction ?? this.fraction,
        quantity: quantity ?? this.quantity,
        priceOverride: priceOverride ?? this.priceOverride,
      );
}

enum BasketResult { ok, notEnoughStock, otherShop }

/// The items a customer is buying, before payment. Lives for the whole session so switching
/// screens doesn't lose it.
class BasketProvider with ChangeNotifier {
  static const _epsilon = 1e-9;

  final Map<String, BasketLine> _lines = {};

  List<BasketLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  int get lineCount => _lines.length;
  double get total => _lines.values.fold(0.0, (sum, l) => sum + l.amount);

  /// All lines come from one shop (a receipt belongs to one shop).
  String? get shopId => _lines.isEmpty ? null : _lines.values.first.stock.shopId;

  /// Base units of [stockId] already in the basket.
  double unitsInBasket(String stockId) =>
      _lines.values.where((l) => l.stock.id == stockId).fold(0.0, (sum, l) => sum + l.units);

  /// How many of [fraction] can still be added from [stock] (stock already excludes sales
  /// that are waiting to sync).
  double remainingFor(AvailableItem stock, Fraction fraction) {
    final units = stock.quantity - unitsInBasket(stock.id);
    return units <= _epsilon ? 0 : units / fraction.ratio;
  }

  double quantityOf(String stockId, String fractionId) => _lines['$stockId:$fractionId']?.quantity ?? 0;

  /// Adds [quantity] (default 1) of [fraction] from [stock].
  BasketResult add(AvailableItem stock, Fraction fraction, {double quantity = 1}) {
    if (shopId != null && stock.shopId != shopId) return BasketResult.otherShop;
    if (remainingFor(stock, fraction) + _epsilon < quantity) return BasketResult.notEnoughStock;
    final key = '${stock.id}:${fraction.id}';
    final existing = _lines[key];
    _lines[key] =
        existing == null
            ? BasketLine(stock: stock, fraction: fraction, quantity: quantity)
            : existing.copyWith(stock: stock, quantity: existing.quantity + quantity);
    notifyListeners();
    return BasketResult.ok;
  }

  /// Sets a line's quantity; 0 or less removes it.
  BasketResult setQuantity(BasketLine line, double quantity) {
    if (!_lines.containsKey(line.key)) return BasketResult.ok;
    if (quantity <= 0) {
      remove(line);
      return BasketResult.ok;
    }
    final current = _lines[line.key]!;
    // Stock available to this line = what's left plus what this line already holds
    final allowed = remainingFor(current.stock, current.fraction) + current.quantity;
    if (quantity > allowed + _epsilon) return BasketResult.notEnoughStock;
    _lines[line.key] = current.copyWith(quantity: quantity);
    notifyListeners();
    return BasketResult.ok;
  }

  /// Switches a line to another unit, keeping the quantity (merges with an existing line).
  BasketResult changeUnit(BasketLine line, Fraction fraction) {
    final current = _lines[line.key];
    if (current == null || fraction.id == current.fraction.id) return BasketResult.ok;
    final unitsWithoutLine = current.stock.quantity - unitsInBasket(current.stock.id) + current.units;
    if (current.quantity * fraction.ratio > unitsWithoutLine + _epsilon) return BasketResult.notEnoughStock;
    _lines.remove(line.key);
    final key = '${current.stock.id}:${fraction.id}';
    final merged = _lines[key];
    _lines[key] =
        merged == null
            ? BasketLine(stock: current.stock, fraction: fraction, quantity: current.quantity)
            : merged.copyWith(quantity: merged.quantity + current.quantity);
    notifyListeners();
    return BasketResult.ok;
  }

  void setPrice(BasketLine line, double price) {
    final current = _lines[line.key];
    if (current == null) return;
    _lines[line.key] = current.copyWith(priceOverride: price);
    notifyListeners();
  }

  void remove(BasketLine line) {
    if (_lines.remove(line.key) != null) notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }

  /// Keeps lines pointing at the latest stock numbers after a refresh or sync.
  void refreshStock(List<AvailableItem> stock) {
    final byId = {for (final s in stock) s.id: s};
    var changed = false;
    for (final entry in _lines.entries.toList()) {
      final latest = byId[entry.value.stock.id];
      if (latest != null && !identical(latest, entry.value.stock)) {
        _lines[entry.key] = entry.value.copyWith(stock: latest);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
