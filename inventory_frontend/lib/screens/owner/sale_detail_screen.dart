import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inventory_frontend/models/sold_item.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SaleDetailScreen extends StatelessWidget {
  final SoldItem sale;
  
  const SaleDetailScreen({
    super.key,
    required this.sale,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm');
    final l10n = AppLocalizations.of(context)!;
    final moneyFormat = NumberFormat('#,##0.00');
    String money(double v) => '${l10n.currencySymbol} ${moneyFormat.format(v)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sale Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Sale ID', sale.id),
                    _buildInfoRow('Date', dateFormat.format(sale.createdAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Item Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Item', sale.item?.name ?? 'Unknown'),
                    _buildInfoRow('Fraction', sale.fractionId),
                    _buildInfoRow('Quantity', sale.quantity.toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Financial Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(l10n.amountLabel, money(sale.soldPrice)),
                    if (sale.priceChanged) _buildInfoRow(l10n.saleNormalPriceLabel, money(sale.expectedAmount!)),
                    // Cost of the goods sold (FIFO: what these exact units were bought for)
                    if (sale.profit != null) ...[
                      _buildInfoRow(l10n.saleCostOfGoods, money(sale.soldPrice - sale.profit!)),
                      _buildInfoRow(l10n.profit, money(sale.profit!)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
