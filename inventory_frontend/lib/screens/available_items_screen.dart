import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/providers/available_item_provider.dart';
import 'package:inventory_frontend/screens/owner/transactions_screen.dart';
import 'package:inventory_frontend/screens/salesman/pos_screen.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

enum _StockSort { name, lowFirst }

/// Current stock per item. Shown inside the dashboards (which provide the app bar) and in a
/// shop's detail tabs ([shopId] set, stock of that shop only).
class AvailableItemsScreen extends StatefulWidget {
  final String? shopId;
  const AvailableItemsScreen({super.key, this.shopId});

  @override
  State<AvailableItemsScreen> createState() => _AvailableItemsScreenState();
}

class _AvailableItemsScreenState extends State<AvailableItemsScreen> {
  /// Quantity at or below this (in the shown unit) is flagged as running low.
  static const _lowStockThreshold = 10.0;
  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat('#,##0.00');

  final Map<String, String> _selectedFractionIds = {}; // availableItemId -> fractionId
  bool _isLoading = true;
  String _query = '';
  String? _shopFilter; // null = all shops
  _StockSort _sort = _StockSort.name;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAvailableItems());
  }

  Future<void> _loadAvailableItems() async {
    if (!mounted) return;
    final provider = context.read<AvailableItemProvider>();
    // Keep showing the current list while refreshing; only show a spinner when there is nothing yet
    setState(() => _isLoading = provider.availableItems.isEmpty);
    await provider.fetchAvailableItems(shopId: widget.shopId);
    if (mounted) setState(() => _isLoading = false);
  }

  /// The unit the quantity is shown in: the one the user picked, else the item's base unit.
  Fraction _shownFraction(AvailableItem ai, List<Fraction> fractions) {
    final picked = _selectedFractionIds[ai.id];
    if (picked != null) {
      for (final f in fractions) {
        if (f.id == picked) return f;
      }
    }
    for (final f in fractions) {
      if (f.isUnit) return f;
    }
    return fractions.first;
  }

  double _shownQuantity(AvailableItem ai, Fraction f) => f.ratio == 0 ? 0 : ai.quantity / f.ratio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Column(children: [OfflineBanner(), Expanded(child: Center(child: CircularProgressIndicator()))]);
    }

    final provider = context.watch<AvailableItemProvider>();
    // Read the list once per build; the provider caches it, so this is cheap
    final all =
        provider.availableItems
            .where((ai) => (ai.item?.fractions ?? const []).isNotEmpty)
            .where((ai) => widget.shopId == null || ai.shopId == widget.shopId)
            .toList();

    // Shop chips only make sense when the list mixes several shops (owner view)
    final shops = <String, String>{};
    for (final ai in all) {
      final name = ai.shop?.name;
      if (name != null && name.isNotEmpty) shops[ai.shopId] = name;
    }
    final showShopChips = widget.shopId == null && shops.length > 1;
    final shopFilter = showShopChips && shops.containsKey(_shopFilter) ? _shopFilter : null;

    final q = _query.trim().toLowerCase();
    final visible =
        all.where((ai) {
          if (shopFilter != null && ai.shopId != shopFilter) return false;
          return q.isEmpty || (ai.item?.name ?? '').toLowerCase().contains(q);
        }).toList();
    if (_sort == _StockSort.lowFirst) {
      visible.sort((a, b) => a.quantity.compareTo(b.quantity));
    } else {
      visible.sort((a, b) => (a.item?.name ?? '').toLowerCase().compareTo((b.item?.name ?? '').toLowerCase()));
    }

    final outCount = all.where((ai) => ai.quantity <= 0).length;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAvailableItems,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              decoration: InputDecoration(
                                hintText: l10n.searchItems,
                                prefixIcon: const Icon(Icons.search_rounded),
                                isDense: true,
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<_StockSort>(
                            tooltip: l10n.stockSort,
                            initialValue: _sort,
                            onSelected: (s) => setState(() => _sort = s),
                            icon: const Icon(Icons.sort_rounded),
                            itemBuilder:
                                (_) => [
                                  PopupMenuItem(value: _StockSort.name, child: Text(l10n.stockSortName)),
                                  PopupMenuItem(value: _StockSort.lowFirst, child: Text(l10n.stockSortLowFirst)),
                                ],
                          ),
                        ],
                      ),
                      if (showShopChips) ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(l10n.stockAllShops),
                                  selected: shopFilter == null,
                                  onSelected: (_) => setState(() => _shopFilter = null),
                                ),
                              ),
                              for (final entry in shops.entries)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    avatar: const Icon(Icons.storefront_outlined, size: 16),
                                    label: Text(entry.value),
                                    selected: shopFilter == entry.key,
                                    onSelected: (_) => setState(() => _shopFilter = entry.key),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              l10n.summaryItemsTitle(visible.length),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (outCount > 0) ...[
                              const SizedBox(width: 8),
                              _Badge(text: l10n.stockOutCount(outCount), color: scheme.error),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(child: _buildEmpty(l10n, provider.error != null && all.isEmpty, q.isNotEmpty))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _buildCard(visible[i], l10n, showShop: widget.shopId == null && shops.length > 1),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, bool failed, bool searching) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 80, left: 32, right: 32),
      child: Column(
        children: [
          Icon(failed ? Icons.cloud_off_rounded : Icons.inventory_2_outlined, size: 44, color: color),
          const SizedBox(height: 12),
          Text(
            failed
                ? l10n.loadFailedNoData
                : searching
                ? l10n.summaryNoItemsMatch
                : l10n.noItemsFound,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
          if (failed)
            TextButton.icon(onPressed: _loadAvailableItems, icon: const Icon(Icons.refresh), label: Text(l10n.retry)),
        ],
      ),
    );
  }

  Widget _buildCard(AvailableItem ai, AppLocalizations l10n, {required bool showShop}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fractions = ai.item!.fractions!;
    final fraction = _shownFraction(ai, fractions);
    final qty = _shownQuantity(ai, fraction);
    final out = qty <= 0;
    final low = !out && qty <= _lowStockThreshold;
    final stockColor =
        out
            ? scheme.error
            : low
            ? Colors.orange.shade800
            : Colors.green.shade700;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionsScreen(availableItem: ai))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stock level dot
                  Container(
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: stockColor, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ai.item?.name ?? l10n.unknownItem,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (showShop && ai.shop?.name != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.storefront_outlined, size: 13, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    ai.shop!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quantity in the chosen unit
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _qty.format(qty),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: stockColor, height: 1.1),
                      ),
                      Text(
                        out
                            ? l10n.stockOutOfStock
                            : low
                            ? '${fraction.name} · ${l10n.stockLow}'
                            : fraction.name,
                        style: theme.textTheme.labelSmall?.copyWith(color: stockColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
              // Cost of the stock on hand (owners only; the server leaves it out for salesmen),
              // in the unit shown: weighted average, FIFO next-unit cost (used for profit), total value
              if (ai.avgUnitCost != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CostPill(
                      label: l10n.stockAvgCost(fraction.name),
                      value: _money.format(ai.avgUnitCost! * fraction.ratio),
                    ),
                    if (ai.unitCost != null && (ai.unitCost! - ai.avgUnitCost!).abs() > 0.0001)
                      _CostPill(label: l10n.stockNextCost, value: _money.format(ai.unitCost! * fraction.ratio)),
                    if (ai.stockValue != null)
                      _CostPill(label: l10n.stockValue, value: '${l10n.currencySymbol} ${_money.format(ai.stockValue)}'),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  // Unit switcher (only when there is more than one unit)
                  if (fractions.length > 1)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in fractions)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(f.name),
                                  selected: f.id == fraction.id,
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: const TextStyle(fontSize: 12),
                                  onSelected: (_) => setState(() => _selectedFractionIds[ai.id] = f.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  Text(
                    '${l10n.currencySymbol} ${_money.format(fraction.sellingPrice)}',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed:
                        out
                            ? null
                            : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => PosScreen(initialStock: ai, initialFraction: fraction)),
                            ),
                    icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                    label: Text(l10n.sellItem),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "label value" chip for the stock cost figures.
class _CostPill extends StatelessWidget {
  final String label;
  final String value;

  const _CostPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
            TextSpan(text: value, style: TextStyle(color: scheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
