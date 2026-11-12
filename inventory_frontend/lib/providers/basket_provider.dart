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
  /// What one [fraction] of this item costs: the FIFO cost of the next units in stock when the
  /// server sent it (owners), else the catalogue purchase price.
  double get unitCost => stock.unitCost != null ? stock.unitCost! * fraction.ratio : fraction.purchasePrice;

  /// Estimated profit, for the below-cost warning. The server works out the real profit.
  double get profit => (unitPrice - unitCost) * quantity;

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

  /// Prices set on an item row before it was added (key: stockId:fractionId). Used when the item
  /// is added, and cleared with the basket so the next customer starts at normal prices.
  final Map<String, double> _pendingPrices = {};

  /// The price per unit that will be charged for [fraction] of [stock] in this sale.
  double priceFor(AvailableItem stock, Fraction fraction) =>
      _lines['${stock.id}:${fraction.id}']?.unitPrice ??
      _pendingPrices['${stock.id}:${fraction.id}'] ??
      fraction.sellingPrice;

  /// Whether this sale uses a different price than the catalogue for [fraction] of [stock].
  bool isPriceChanged(AvailableItem stock, Fraction fraction) =>
      (priceFor(stock, fraction) - fraction.sellingPrice).abs() >= 0.005;

  /// Sets the price for [fraction] of [stock] from the item list: changes the basket line if it is
  /// already there, otherwise remembers it for when the item is added.
  void setPriceFor(AvailableItem stock, Fraction fraction, double price) {
    final key = '${stock.id}:${fraction.id}';
    final line = _lines[key];
    if (line != null) {
      setPrice(line, price);
      return;
    }
    if ((price - fraction.sellingPrice).abs() < 0.005) {
      _pendingPrices.remove(key);
    } else {
      _pendingPrices[key] = price;
    }
    notifyListeners();
  }

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
            // A price set on the item row before adding carries over to the new line
            ? BasketLine(stock: stock, fraction: fraction, quantity: quantity, priceOverride: _pendingPrices.remove(key))
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

  /// Sets the price per unit for this sale. Setting it back to the catalogue price clears the
  /// override, so the sale isn't reported as a changed price.
  void setPrice(BasketLine line, double price) {
    final current = _lines[line.key];
    if (current == null) return;
    _lines[line.key] =
        (price - current.fraction.sellingPrice).abs() < 0.005
            ? BasketLine(stock: current.stock, fraction: current.fraction, quantity: current.quantity)
            : current.copyWith(priceOverride: price);
    notifyListeners();
  }

  void remove(BasketLine line) {
    if (_lines.remove(line.key) != null) notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty && _pendingPrices.isEmpty) return;
    _lines.clear();
    _pendingPrices.clear();
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
