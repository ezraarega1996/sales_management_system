import 'package:flutter/material.dart';

import 'package:inventory_frontend/screens/salesman/sale_detail_screen.dart';
import 'package:inventory_frontend/widgets/sales_history_view.dart';

/// The sales of the salesman's shop (by every salesman there, without profit), plus this phone's
/// sales still waiting to sync.
/// Shown inside the salesman dashboard, which provides the app bar.
class ViewSalesScreen extends StatelessWidget {
  const ViewSalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SalesHistoryView(
      isOwner: false,
      // The server returns only this salesman's shop for GET /sales
      load: (provider) => provider.fetchSales(),
      detailBuilder: (sale) => SaleDetailScreen(sale: sale),
    );
  }
}
