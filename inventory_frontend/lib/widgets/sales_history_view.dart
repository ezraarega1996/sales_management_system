import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/sold_item.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

/// Sales history shared by owners (all sales, profit, delete) and salesmen (own sales, plus
/// sales still waiting to sync). Sales are grouped by day, and basket lines by receipt.
///
/// The list is built lazily, and the grouping is only redone when the sales or the search change.
class SalesHistoryView extends StatefulWidget {
  final bool isOwner;

  /// Loads the sales into [SalesProvider] (all sales for owners, own sales for salesmen).
  final Future<void> Function(SalesProvider provider) load;

  /// Opens the detail page for one sale line.
  final Widget Function(SoldItem sale) detailBuilder;

  const SalesHistoryView({super.key, required this.isOwner, required this.load, required this.detailBuilder});

  @override
  State<SalesHistoryView> createState() => _SalesHistoryViewState();
}

/// One row of the flattened list: a day header or a receipt.
sealed class _Row {}

class _DayRow extends _Row {
  final DateTime day;
  final double total;
  final int count;
  _DayRow(this.day, this.total, this.count);
}

class _ReceiptRow extends _Row {
  final List<SoldItem> lines;
  _ReceiptRow(this.lines);
  DateTime get time => lines.first.createdAt;
  double get total => lines.fold(0.0, (sum, s) => sum + s.soldPrice);
  double? get profit => lines.any((s) => s.profit != null) ? lines.fold(0.0, (sum, s) => sum! + (s.profit ?? 0)) : null;
}

class _SalesHistoryViewState extends State<SalesHistoryView> {
  bool _isLoading = false;
  String _query = '';
  final Set<String> _expanded = {};

  // Memoized result of grouping, keyed on the provider's sales list identity and the query
  List<SoldItem>? _groupedFrom;
  String? _groupedQuery;
  List<_Row> _rows = const [];
  int _shownCount = 0;
  double _shownTotal = 0;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final provider = context.read<SalesProvider>();
    // Keep the current list visible while refreshing
    setState(() => _isLoading = provider.sales.isEmpty);
    await widget.load(provider);
    if (mounted) setState(() => _isLoading = false);
  }

  void _regroupIfNeeded(List<SoldItem> sales, AppLocalizations l10n) {
    if (identical(sales, _groupedFrom) && _query == _groupedQuery) return;
    _groupedFrom = sales;
    _groupedQuery = _query;

    final q = _query.trim().toLowerCase();
    final matching =
        q.isEmpty
            ? sales
            : sales.where((s) {
              final item = (s.item?.name ?? '').toLowerCase();
              final salesman = (s.salesman?.name ?? '').toLowerCase();
              return item.contains(q) || salesman.contains(q);
            }).toList();
    final sorted = [...matching]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Group basket lines by receipt (older sales have no receipt and stay on their own)
    final receipts = <List<SoldItem>>[];
    final byReceipt = <String, List<SoldItem>>{};
    for (final sale in sorted) {
      final id = sale.receiptId;
      if (id == null) {
        receipts.add([sale]);
      } else if (byReceipt[id] case final lines?) {
        lines.add(sale);
      } else {
        receipts.add(byReceipt[id] = [sale]);
      }
    }

    // Insert a header before each new day
    final rows = <_Row>[];
    DateTime? currentDay;
    var headerIndex = -1;
    var dayTotal = 0.0;
    var dayCount = 0;
    // The header's total is only known once the whole day has been seen
    void closeDay() {
      if (headerIndex >= 0) rows[headerIndex] = _DayRow(currentDay!, dayTotal, dayCount);
    }

    for (final lines in receipts) {
      final local = lines.first.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day != currentDay) {
        closeDay();
        currentDay = day;
        headerIndex = rows.length;
        rows.add(_DayRow(day, 0, 0));
        dayTotal = 0;
        dayCount = 0;
      }
      rows.add(_ReceiptRow(lines));
      dayTotal += lines.fold(0.0, (sum, s) => sum + s.soldPrice);
      dayCount++;
    }
    closeDay();

    _rows = rows;
    _shownCount = receipts.length;
    _shownTotal = sorted.fold(0.0, (sum, s) => sum + s.soldPrice);
  }

  Future<void> _deleteLine(SoldItem sale) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<SalesProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.deleteSaleTitle),
            content: Text(l10n.deleteSaleContent),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
    );
    if (confirm != true) return;
    // The provider removes the line itself, so there is no need to reload everything
    final ok = await provider.deleteSale(sale.id);
    messenger.showSnackBar(SnackBar(content: Text(ok ? l10n.saleDeletedSuccess : (provider.error ?? l10n.error))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<SalesProvider>();
    final unsynced = widget.isOwner ? const <PendingSale>[] : provider.unsyncedSales;

    if (_isLoading) {
      return const Column(children: [OfflineBanner(), Expanded(child: Center(child: CircularProgressIndicator()))]);
    }

    _regroupIfNeeded(provider.sales, l10n);
    final loadFailed = provider.sales.isEmpty && provider.error != null;
    final money = NumberFormat('#,##0.00');
    final symbol = l10n.currencySymbol;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              // Always scrollable so pull-to-refresh also works on an empty list
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  sliver: SliverList.list(
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: l10n.salesSearchHintOwner,
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_shownCount > 0) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${l10n.summarySalesCount(_shownCount)} · $symbol ${money.format(_shownTotal)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (unsynced.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverList.list(
                      children: [
                        _DayHeader(title: l10n.unsyncedSales),
                        for (final sale in unsynced) _UnsyncedSaleCard(sale: sale),
                      ],
                    ),
                  ),
                if (_rows.isEmpty && unsynced.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(
                            loadFailed ? Icons.cloud_off_rounded : Icons.receipt_long_outlined,
                            size: 44,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(loadFailed ? l10n.loadFailedNoData : l10n.noSalesFound),
                          if (loadFailed) TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(l10n.retry)),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final row = _rows[i];
                        return switch (row) {
                          _DayRow() => _DayHeader(
                            title: _dayTitle(row.day, l10n),
                            trailing: '$symbol ${money.format(row.total)}',
                          ),
                          _ReceiptRow() => _ReceiptCard(
                            row: row,
                            isOwner: widget.isOwner,
                            expanded: _expanded.contains(row.lines.first.id),
                            onToggle:
                                () => setState(() {
                                  final id = row.lines.first.id;
                                  _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id);
                                }),
                            onOpen:
                                (sale) => Navigator.of(
                                  context,
                                ).push(MaterialPageRoute(builder: (_) => widget.detailBuilder(sale))),
                            onDelete: widget.isOwner ? _deleteLine : null,
                          ),
                        };
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _dayTitle(DateTime day, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.today;
    if (day == today.subtract(const Duration(days: 1))) return l10n.summaryYesterday;
    return DateFormat.yMMMEd().format(day);
  }
}

class _DayHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _DayHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  static const _collapsedLines = 3;
  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat('#,##0.00');
  static final _time = DateFormat.Hm();

  final _ReceiptRow row;
  final bool isOwner;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<SoldItem> onOpen;
  final Future<void> Function(SoldItem sale)? onDelete;

  const _ReceiptCard({
    required this.row,
    required this.isOwner,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = row.lines;
    final shown = expanded ? lines : lines.take(_collapsedLines).toList();
    final hidden = lines.length - shown.length;
    final profit = isOwner ? row.profit : null;
    final salesman = lines.first.salesman?.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Receipt header: time, salesman, total
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.receipt_long_rounded, size: 20, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${_time.format(row.time.toLocal())} · ${l10n.posItemsCount(lines.length)}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (lines.any((s) => s.priceChanged)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade800.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  l10n.salesPriceChanged,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (isOwner || salesman != null)
                          Text(
                            salesman ?? l10n.unknownSalesman,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${l10n.currencySymbol} ${_money.format(row.total)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      if (profit != null)
                        Text(
                          '${l10n.profit} ${_money.format(profit)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: profit < 0 ? scheme.error : Colors.green.shade700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, indent: 14, endIndent: 14, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            // Lines
            for (final sale in shown)
              InkWell(
                onTap: () => onOpen(sale),
                onLongPress: onDelete == null ? null : () => onDelete!(sale),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: sale.item?.name ?? l10n.unknownItem,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(
                                    text: '  ×${_qty.format(sale.quantity)} ${sale.fraction?.name ?? ''}',
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // A price changed at the counter: show the normal price for transparency
                            if (sale.priceChanged)
                              Row(
                                children: [
                                  Icon(Icons.sell_outlined, size: 12, color: Colors.orange.shade800),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      l10n.salesNormalPrice(_money.format(sale.expectedAmount)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _money.format(sale.soldPrice),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: sale.priceChanged ? Colors.orange.shade800 : null,
                        ),
                      ),
                      if (onDelete != null)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, size: 18, color: scheme.onSurfaceVariant),
                          padding: EdgeInsets.zero,
                          onSelected: (_) => onDelete!(sale),
                          itemBuilder:
                              (_) => [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, color: scheme.error),
                                      const SizedBox(width: 8),
                                      Text(l10n.delete, style: TextStyle(color: scheme.error)),
                                    ],
                                  ),
                                ),
                              ],
                        )
                      else
                        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            if (lines.length > _collapsedLines)
              TextButton(
                onPressed: onToggle,
                child: Text(expanded ? l10n.salesShowLess : l10n.salesShowMore(hidden)),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// A sale saved on the phone that the server has not confirmed yet.
class _UnsyncedSaleCard extends StatelessWidget {
  final PendingSale sale;
  const _UnsyncedSaleCard({required this.sale});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final salesProvider = context.read<SalesProvider>();
    final failed = sale.isFailed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: failed ? scheme.errorContainer : scheme.tertiaryContainer.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: Icon(
            failed ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
            color: failed ? scheme.error : scheme.onTertiaryContainer,
          ),
          title: Text(sale.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              '${l10n.posItemsCount(sale.itemCount)} · ${l10n.amountWithCurrency(sale.amount.toStringAsFixed(2))}',
              DateFormat('MMM d, HH:mm').format(sale.createdAt),
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
      ),
    );
  }
}
