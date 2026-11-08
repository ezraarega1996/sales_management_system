import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/sold_item.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/screens/salesman/sale_detail_screen.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

class ViewSalesScreen extends StatefulWidget {
  const ViewSalesScreen({super.key});

  @override
  State<ViewSalesScreen> createState() => _ViewSalesScreenState();
}

class _ViewSalesScreenState extends State<ViewSalesScreen> {
  final Map<String, String> _selectedFractionIds = {}; // saleId -> fractionId
  final _dateFormat = DateFormat('MMM dd, yyyy HH:mm');
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSales();
    });
  }

  Future<void> _loadSales() async {
    if (!mounted) return;
    final salesProvider = context.read<SalesProvider>();
    setState(() => _isLoading = salesProvider.sales.isEmpty);
    await salesProvider.fetchUserSales();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.salesHistory),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _isLoading ? null : _loadSales)],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: Consumer<SalesProvider>(
              builder: (context, salesProvider, child) {
                if (_isLoading) return const Center(child: CircularProgressIndicator());

                final unsynced = salesProvider.unsyncedSales;
                final sales = salesProvider.sales;
                final loadFailed = sales.isEmpty && salesProvider.error != null;

                return RefreshIndicator(
                  onRefresh: _loadSales,
                  child: ListView(
                    // Always scrollable so pull-to-refresh also works on an empty list
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (unsynced.isNotEmpty) ...[
                        _SectionHeader(text: l10n.unsyncedSales),
                        for (final sale in unsynced) _UnsyncedSaleTile(sale: sale, dateFormat: _dateFormat),
                        const Divider(height: 24),
                      ],
                      if (sales.isEmpty && unsynced.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 96),
                          child: Center(child: Text(loadFailed ? l10n.loadFailedNoData : l10n.noSalesFound)),
                        ),
                      for (final group in _groupByReceipt(sales))
                        group.first.receiptId == null
                            ? _buildSaleCard(group.first, l10n)
                            : _buildReceiptCard(group, l10n),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Lines of one basket share a receiptId and are shown as one receipt; older sales stay single.
  List<List<SoldItem>> _groupByReceipt(List<SoldItem> sales) {
    final groups = <String, List<SoldItem>>{};
    final ordered = <List<SoldItem>>[];
    for (final sale in sales) {
      final receiptId = sale.receiptId;
      if (receiptId == null) {
        ordered.add([sale]);
      } else if (groups.containsKey(receiptId)) {
        groups[receiptId]!.add(sale);
      } else {
        ordered.add(groups[receiptId] = [sale]);
      }
    }
    return ordered;
  }

  Widget _buildReceiptCard(List<SoldItem> lines, AppLocalizations l10n) {
    final total = lines.fold(0.0, (sum, s) => sum + s.soldPrice);
    final qty = NumberFormat('#,##0.##');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text('${l10n.posItemsCount(lines.length)} · ${l10n.currencySymbol} ${qty.format(total)}'),
        subtitle: Text(
          [
            lines.map((s) => s.item?.name ?? l10n.unknownItem).take(3).join(', '),
            '${_dateFormat.format(lines.first.createdAt.toLocal())} · ${lines.first.salesman?.name ?? l10n.unknownSalesman}',
          ].join('\n'),
        ),
        children: [
          for (final sale in lines)
            ListTile(
              dense: true,
              title: Text(sale.item?.name ?? l10n.unknownItem),
              subtitle: Text('${qty.format(sale.quantity)} ${sale.fraction?.name ?? ''}'),
              trailing: Text('${l10n.currencySymbol} ${qty.format(sale.soldPrice)}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: sale))),
            ),
        ],
      ),
    );
  }

  Widget _buildSaleCard(SoldItem sale, AppLocalizations l10n) {
    final fractions = sale.item?.fractions ?? [];
    final soldFraction =
        sale.fraction ??
        (fractions.isNotEmpty
            ? fractions.first
            : Fraction(id: '', name: '', ratio: 1, sellingPrice: 0, purchasePrice: 0, itemId: ''));
    final selectedId = _selectedFractionIds[sale.id] ?? soldFraction.id;
    final selectedFraction = fractions.where((f) => f.id == selectedId).firstOrNull ?? soldFraction;
    final factor = soldFraction.ratio / selectedFraction.ratio;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(sale.item?.name ?? l10n.unknownItem),
        subtitle: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${sale.item?.name}(${sale.salesman?.name ?? l10n.unknownSalesman})'),
                  Text(l10n.quantityWithUnit((sale.quantity * factor).toString(), selectedFraction.name)),
                  Text(l10n.amountWithCurrency(sale.soldPrice.toString())),
                  if (sale.profit != null)
                    Text(
                      l10n.profitWithAmount('${l10n.currencySymbol} ${sale.profit!.toStringAsFixed(2)}'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if (sale.available_items_count != null)
                    Text(
                      l10n.availableItemsWithUnit(
                        (sale.available_items_count! * factor).toString(),
                        selectedFraction.name,
                      ),
                    ),
                  Text(l10n.dateWithFormat(_dateFormat.format(sale.createdAt.toLocal()))),
                ],
              ),
            ),
            if (fractions.isNotEmpty)
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: DropdownButton<String>(
                    value: selectedFraction.id,
                    items:
                        fractions
                            .map((fraction) => DropdownMenuItem<String>(value: fraction.id, child: Text(fraction.name)))
                            .toList(),
                    onChanged: (value) => setState(() => _selectedFractionIds[sale.id] = value!),
                  ),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: sale))),
        isThreeLine: true,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// A sale saved on the phone that the server has not confirmed yet.
class _UnsyncedSaleTile extends StatelessWidget {
  final PendingSale sale;
  final DateFormat dateFormat;
  const _UnsyncedSaleTile({required this.sale, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final salesProvider = context.read<SalesProvider>();
    final failed = sale.isFailed;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: failed ? scheme.errorContainer : scheme.secondaryContainer.withValues(alpha: 0.5),
      child: ListTile(
        leading: Icon(failed ? Icons.error_outline : Icons.schedule, color: failed ? scheme.error : null),
        title: Text(sale.title),
        subtitle: Text(
          [
            '${l10n.posItemsCount(sale.itemCount)} · ${l10n.amountWithCurrency(sale.amount.toStringAsFixed(2))}',
            dateFormat.format(sale.createdAt),
            failed ? l10n.notRecordedReason(sale.error!) : l10n.waitingToSync,
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing:
            failed
                ? PopupMenuButton<String>(
                  onSelected:
                      (action) =>
                          action == 'retry'
                              ? salesProvider.retryUnsynced(sale.clientId)
                              : salesProvider.discardUnsynced(sale.clientId),
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(value: 'retry', child: Text(l10n.retry)),
                        PopupMenuItem(value: 'discard', child: Text(l10n.discardSale)),
                      ],
                )
                : null,
      ),
    );
  }
}
