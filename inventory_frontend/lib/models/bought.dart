import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/shop.dart';

class Bought {
  final String id;
  final String fractionId;
  final double fractionPurchasePrice;
  final double fractionSoldPrice;
  final double quantity;
  final DateTime? expiryDate;
  final DateTime createdTime;
  final String itemId;
  final Item? item;
  final Fraction? fraction;
  final String? shopId;
  final Shop? shop;
  final double? available_items_count;
  
  
  Bought({
    required this.id,
    required this.fractionId,
    required this.fractionPurchasePrice,
    required this.fractionSoldPrice,
    required this.quantity,
    this.expiryDate,
    required this.createdTime,
    required this.itemId,
    this.item,
    this.fraction,
    this.shopId,
    this.shop,
    this.available_items_count,
  });
  
  factory Bought.fromJson(Map<String, dynamic> json) {
    final fractionId = json['fractionId']?.toString() ?? '';
    return Bought(
      id: json['id']?.toString() ?? '',
      fractionId: fractionId,
      fractionPurchasePrice: _toDouble(json['fractionPurchasePrice']) ?? 0.0,
      fractionSoldPrice: _toDouble(json['fractionSoldPrice']) ?? 0.0,
      quantity: _toDouble(json['quantity']) ?? 0.0,
      expiryDate: _toDate(json['expiryDate']),
      createdTime: _toDate(json['createdTime'] ?? json['createdAt']) ?? DateTime.now(),
      itemId: json['itemId']?.toString() ?? '',
      item: json['Item'] is Map<String, dynamic> ? Item.fromJson(json['Item']) : null,
      fraction: _findFraction(json['Item'], fractionId),
      shopId: json['shopId']?.toString(),
      shop: json['Shop'] is Map<String, dynamic> ? Shop.fromJson(json['Shop']) : null,
      available_items_count: _toDouble(json['available_items_count']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _toDate(dynamic value) => value == null ? null : DateTime.tryParse(value.toString());

  /// The purchased unit, looked up in the item's fractions; null when it isn't there or can't be read.
  static Fraction? _findFraction(dynamic itemJson, String fractionId) {
    if (itemJson is! Map || fractionId.isEmpty) return null;
    final fractions = itemJson['fractions'];
    if (fractions is! List) return null;
    for (final f in fractions) {
      if (f is Map<String, dynamic> && f['id']?.toString() == fractionId) {
        try {
          return Fraction.fromJson(f);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fractionId': fractionId,
      'fractionPurchasePrice': fractionPurchasePrice,
      'fractionSoldPrice': fractionSoldPrice,
      'quantity': quantity,
      'expiryDate': expiryDate?.toIso8601String(),
      'itemId': itemId,
      'shopId': shopId,
    };
  }

  @override
  String toString() {
    return 'Bought(id: $id, fractionId: $fractionId, fractionPurchasePrice: $fractionPurchasePrice, fractionSoldPrice: $fractionSoldPrice, quantity: $quantity, expiryDate: $expiryDate, createdTime: $createdTime, itemId: $itemId, item: $item, fraction: $fraction, shopId: $shopId, shop: $shop)';
  }
} 