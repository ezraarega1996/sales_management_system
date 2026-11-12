import 'package:inventory_frontend/models/fraction.dart';

class ItemBought {
  final String id;
  final String itemId;
  final String fractionId;
  final double quantity;
  final double fractionPurchasePrice;
  final double fractionSoldPrice;
  final DateTime? expiryDate;
  final String businessId;
  final String? salesmanId;
  final DateTime createdAt;
  final Fraction? fraction;
  final String? availableItemId;
  final double? available_items_count;

  ItemBought({
    required this.id,
    required this.itemId,
    required this.fractionId,
    required this.quantity,
    required this.fractionPurchasePrice,
    required this.fractionSoldPrice,
    this.expiryDate,
    required this.businessId,
    this.salesmanId,
    required this.createdAt,
    this.fraction,
    this.availableItemId,
    this.available_items_count,
  });

  factory ItemBought.fromJson(Map<String, dynamic> json) {
    // The backend includes the purchased unit as 'Fraction'; older payloads used 'fraction'
    final fractionJson = json['Fraction'] ?? json['fraction'];
    Fraction? fraction;
    if (fractionJson is Map<String, dynamic>) {
      try {
        fraction = Fraction.fromJson(fractionJson);
      } catch (_) {
        fraction = null;
      }
    }
    return ItemBought(
      id: json['id']?.toString() ?? '',
      itemId: json['itemId']?.toString() ?? '',
      fractionId: json['fractionId']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '') ?? 0.0,
      fractionPurchasePrice: double.tryParse(json['fractionPurchasePrice']?.toString() ?? '') ?? 0.0,
      fractionSoldPrice: double.tryParse(json['fractionSoldPrice']?.toString() ?? '') ?? 0.0,
      expiryDate: json['expiryDate'] != null ? DateTime.tryParse(json['expiryDate'].toString()) : null,
      businessId: json['businessId']?.toString() ?? '',
      salesmanId: json['salesmanId']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? json['createdTime'])?.toString() ?? '') ?? DateTime.now(),
      fraction: fraction,
      availableItemId: json['availableItemId']?.toString(),
      available_items_count:
          json['available_items_count'] != null ? double.tryParse(json['available_items_count'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itemId': itemId,
      'fractionId': fractionId,
      'quantity': quantity,
      'fractionPurchasePrice': fractionPurchasePrice,
      'fractionSoldPrice': fractionSoldPrice,
      'expiryDate': expiryDate?.toIso8601String(),
      'businessId': businessId,
      'salesmanId': salesmanId,
      'createdAt': createdAt.toIso8601String(),
      'fraction': fraction?.toJson(),
      'availableItemId': availableItemId,
      'available_items_count': available_items_count,
    };
  }

  @override
  String toString() {
    return 'ItemBought(id: $id, itemId: $itemId, fractionId: $fractionId, quantity: $quantity, fractionPurchasePrice: $fractionPurchasePrice, fractionSoldPrice: $fractionSoldPrice, expiryDate: $expiryDate, businessId: $businessId, salesmanId: $salesmanId, createdAt: $createdAt, fraction: $fraction, availableItemId: $availableItemId, available_items_count: $available_items_count)';
  }
}
