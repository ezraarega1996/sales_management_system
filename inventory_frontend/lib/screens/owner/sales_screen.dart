import 'package:flutter/material.dart';

import 'package:inventory_frontend/screens/owner/sale_detail_screen.dart';
import 'package:inventory_frontend/widgets/sales_history_view.dart';

/// Every sale in the business, with profit and delete.
/// Shown inside the owner dashboard, which provides the app bar.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SalesHistoryView(
      isOwner: true,
      load: (provider) => provider.fetchSales(),
      detailBuilder: (sale) => SaleDetailScreen(sale: sale),
    );
  }
}
