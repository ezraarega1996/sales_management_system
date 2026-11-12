import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/models/item_bought.dart';
import 'package:inventory_frontend/models/sold_item.dart';
import 'package:inventory_frontend/models/shop.dart';

class AvailableItem {
  final String id;
  final String itemId;
  final String businessId;
  final String shopId;
  final double quantity;
  final double soldPrice;
  final Item? item;
  final List<ItemBought>? boughtTransactions;
  final List<SoldItem>? soldTransactions;
  final Shop? shop;

  /// Cost of the next unit to be sold, per base unit (oldest purchase lot still in stock, FIFO).
  /// Only sent to owners; null for salesmen and for stock without cost data.
  final double? unitCost;

  /// Weighted average cost of all units still in stock, per base unit (owners only).
  final double? avgUnitCost;

  /// What the units still in stock cost in total (owners only).
  final double? stockValue;

  AvailableItem({
    required this.id,
    required this.itemId,
    required this.businessId,
    required this.shopId,
    required this.quantity,
    required this.soldPrice,
    this.item,
    this.boughtTransactions,
    this.soldTransactions,
    this.shop,
    this.unitCost,
    this.avgUnitCost,
    this.stockValue,
  });

  factory AvailableItem.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return AvailableItem(
      id: json['id'],
      itemId: json['itemId'],
      businessId: json['businessId'],
      shopId: json['shopId'],
      quantity: parseDouble(json['quantity']),
      soldPrice: parseDouble(json['soldPrice']),
      item: json['item'] != null ? Item.fromJson(json['item']) : null,
      boughtTransactions:
          json['boughtTransactions'] != null
              ? (json['boughtTransactions'] as List).map((e) => ItemBought.fromJson(e)).toList()
              : null,
      soldTransactions:
          json['soldTransactions'] != null
              ? (json['soldTransactions'] as List).map((e) => SoldItem.fromJson(e)).toList()
              : null,
      shop: json['shop'] != null ? Shop.fromJson(json['shop']) : null,
      unitCost: json['unitCost'] == null ? null : parseDouble(json['unitCost']),
      avgUnitCost: json['avgUnitCost'] == null ? null : parseDouble(json['avgUnitCost']),
      stockValue: json['stockValue'] == null ? null : parseDouble(json['stockValue']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itemId': itemId,
      'businessId': businessId,
      'shopId': shopId,
      'quantity': quantity,
      'soldPrice': soldPrice,
      'item': item?.toJson(),
      'boughtTransactions': boughtTransactions?.map((transaction) => transaction.toJson()).toList(),
      'soldTransactions': soldTransactions?.map((transaction) => transaction.toJson()).toList(),
      'shop': shop?.toJson(),
      'unitCost': unitCost,
      'avgUnitCost': avgUnitCost,
      'stockValue': stockValue,
    };
  }

  /// Same stock row with a different quantity (used to show sales not yet synced).
  AvailableItem withQuantity(double newQuantity) => AvailableItem(
    id: id,
    itemId: itemId,
    businessId: businessId,
    shopId: shopId,
    quantity: newQuantity,
    soldPrice: soldPrice,
    item: item,
    boughtTransactions: boughtTransactions,
    soldTransactions: soldTransactions,
    shop: shop,
    unitCost: unitCost,
    avgUnitCost: avgUnitCost,
    stockValue: stockValue,
  );

  // Identity is the stock row id, so dropdowns keep their selection when the list is refreshed
  @override
  bool operator ==(Object other) => other is AvailableItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AvailableItem(id: $id, itemId: $itemId, quantity: $quantity)';
}
