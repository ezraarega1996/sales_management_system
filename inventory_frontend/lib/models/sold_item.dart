import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/models/user.dart';
import 'package:inventory_frontend/models/fraction.dart';

class SoldItem {
  final String id;
  final String itemId;
  final String fractionId;
  final double quantity;
  final double soldPrice;
  final String businessId;
  final String? shopId;
  final String? salesmanId;
  final DateTime createdAt;
  final Fraction? fraction;
  final Item? item;
  final User? salesman;
  final double? available_items_count;
  final String? availableItemId;

  /// Shared by all lines of one basket (multi-item sale); null for older single sales.
  final String? receiptId;
  final double? profit;

  /// What the line would have cost at the normal (catalogue) price. Differs from [soldPrice]
  /// when the price was changed at the counter.
  final double? expectedAmount;

  /// True when the seller charged a different price than the catalogue price.
  bool get priceChanged => expectedAmount != null && (soldPrice - expectedAmount!).abs() >= 0.01;

  SoldItem({
    required this.id,
    required this.itemId,
    required this.fractionId,
    required this.quantity,
    required this.soldPrice,
    required this.businessId,
    this.shopId,
    this.salesmanId,
    required this.createdAt,
    this.fraction,
    this.item,
    this.salesman,
    this.available_items_count,
    this.availableItemId,
    this.receiptId,
    this.profit,
    this.expectedAmount,
  });

  factory SoldItem.fromJson(Map<String, dynamic> json) {
    final soldPriceRaw = json['soldPrice'] ?? json['amount'] ?? json['expectedAmount'];
    return SoldItem(
      id: json['id'],
      itemId: json['itemId'],
      fractionId: json['fractionId'],
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      soldPrice:
          (soldPriceRaw == null)
              ? 0.0
              : (soldPriceRaw is num)
              ? soldPriceRaw.toDouble()
              : double.tryParse(soldPriceRaw.toString()) ?? 0.0,
      businessId: json['businessId'],
      shopId: json['shopId'],
      salesmanId: json['salesmanId'],
      // When the sale happened (may be earlier than createdAt for sales queued offline)
      createdAt: DateTime.parse(json['soldTime'] ?? json['createdAt']),
      item: json['Item'] != null ? Item.fromJson(json['Item']) : null,
      fraction: _soldFraction(json),
      salesman: json['salesman'] != null ? User.fromJson(json['salesman']) : null,
      available_items_count:
          json['available_items_count'] != null ? double.tryParse(json['available_items_count'].toString()) : null,
      availableItemId: json['availableItemId'],
      receiptId: json['receiptId'],
      profit: (json['profit'] as num?)?.toDouble(),
      expectedAmount: double.tryParse('${json['expectedAmount'] ?? ''}'),
    );
  }

  static Fraction? _soldFraction(Map<String, dynamic> json) {
    final fractions = json['Item']?['fractions'];
    if (fractions is! List) return null;
    final match = fractions.where((f) => f is Map && f['id'] == json['fractionId']).firstOrNull;
    return match == null ? null : Fraction.fromJson(Map<String, dynamic>.from(match));
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itemId': itemId,
      'fractionId': fractionId,
      'quantity': quantity,
      'soldPrice': soldPrice,
      'businessId': businessId,
      'shopId': shopId,
      'salesmanId': salesmanId,
      'createdAt': createdAt.toIso8601String(),
      'fraction': fraction?.toJson(),
      'item': item?.toJson(),
      'salesman': salesman?.toJson(),
      'available_items_count': available_items_count,
      'availableItemId': availableItemId,
      'profit': profit,
      'expectedAmount': expectedAmount,
    };
  }

  @override
  String toString() {
    return 'SoldItem(id: $id, itemId: $itemId, fractionId: $fractionId, quantity: $quantity, soldPrice: $soldPrice, businessId: $businessId, shopId: $shopId, salesmanId: $salesmanId, createdAt: $createdAt, fraction: $fraction, item: $item, available_items_count: $available_items_count, availableItemId: $availableItemId)';
  }
}
