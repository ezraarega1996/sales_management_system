import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/screens/owner/boughts_screen.dart';
import 'package:inventory_frontend/screens/owner/filtered_sales_history_screen.dart';
import 'package:inventory_frontend/models/bought.dart';
import 'package:inventory_frontend/models/sold_item.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/providers/bought_provider.dart';
import 'package:inventory_frontend/providers/available_item_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/providers/shop_provider.dart';
import 'package:inventory_frontend/screens/owner/transactions_screen.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Quick period choices shown as chips above the summary.
enum _Period { today, yesterday, last7, last30, thisMonth, custom }

class SummaryScreen extends StatefulWidget {
  /// When provided, the screen will lock to this shop and (by default)
  /// hide the shop dropdown so the user cannot switch shops.
  final String? fixedShopId;

  /// Whether the user is allowed to change the selected shop via dropdown.
  /// Owners should use the default (true); salesman usage can set this to false.
  /// Also hides purchase amounts and profit, which are owner-only.
  final bool allowShopSwitch;

  const SummaryScreen({super.key, this.fixedShopId, this.allowShopSwitch = true});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  _Period _period = _Period.today;
  bool _isLoading = true;
  final Map<String, String> _selectedUnitIds = {}; // key: itemId_fractionId -> fractionId
  String? _selectedShopId;
  String _search = '';

  // Formatters are reused across rebuilds and rows instead of being created per cell
  final NumberFormat _money = NumberFormat('#,##0.00');
  final NumberFormat _qty = NumberFormat('#,##0.##');

  @override
  void initState() {
    super.initState();
    _applyPeriod(_Period.today, notify: false);
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      // A salesman's shop is fixed, so the shop list isn't needed
      if (widget.fixedShopId == null) _loadShops();
    });
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  // _startDate and _endDate are exact instants (inclusive), so an owner who settled
  // accounts at e.g. 15:30 can report on everything from that minute on.
  void _applyPeriod(_Period period, {bool notify = true}) {
    final today = _day(DateTime.now());
    late DateTime start;
    late DateTime endDay;
    switch (period) {
      case _Period.today:
        start = endDay = today;
      case _Period.yesterday:
        start = endDay = today.subtract(const Duration(days: 1));
      case _Period.last7:
        start = today.subtract(const Duration(days: 6));
        endDay = today;
      case _Period.last30:
        start = today.subtract(const Duration(days: 29));
        endDay = today;
      case _Period.thisMonth:
        start = DateTime(today.year, today.month, 1);
        endDay = today;
      case _Period.custom:
        return;
    }
    void apply() {
      _period = period;
      _startDate = start;
      _endDate = _endOfDay(endDay);
    }

    notify ? setState(apply) : apply();
  }

  /// Picks a date, then a time. Cancelling the time keeps the start (00:00) or end (23:59) of that day.
  Future<DateTime?> _pickDateTime(DateTime initial, {required bool isEnd}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 3),
      lastDate: _day(now),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: AppLocalizations.of(context)!.summaryPickTime,
    );
    if (time == null) return isEnd ? _endOfDay(date) : _day(date);
    // The end minute is inclusive: 15:30 includes sales at 15:30:45
    return DateTime(date.year, date.month, date.day, time.hour, time.minute, isEnd ? 59 : 0, isEnd ? 999 : 0);
  }

  Future<void> _pickFrom() async {
    final picked = await _pickDateTime(_startDate, isEnd: false);
    if (picked == null || !mounted) return;
    setState(() {
      _period = _Period.custom;
      _startDate = picked;
      // Keep the range valid: a From after To moves To to the end of that day
      if (_endDate.isBefore(_startDate)) _endDate = _endOfDay(_startDate);
    });
  }

  Future<void> _pickTo() async {
    final picked = await _pickDateTime(_endDate, isEnd: true);
    if (picked == null || !mounted) return;
    if (picked.isBefore(_startDate)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.summaryToBeforeFrom)));
      return;
    }
    setState(() {
      _period = _Period.custom;
      _endDate = picked;
    });
  }

  Future<void> _loadShops() async {
    final shopProvider = context.read<ShopProvider>();
    try {
      await shopProvider.getShops();
      final shops = shopProvider.shops;
      if (mounted && shops.isNotEmpty && _selectedShopId == null) {
        setState(() => _selectedShopId = shops.first.id);
      }
    } catch (_) {
      // Ignore shop loading errors here; ShopProvider already handles error state.
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final boughts = context.read<BoughtProvider>();
    final sales = context.read<SalesProvider>();
    final available = context.read<AvailableItemProvider>();
    // Only show the full-screen spinner the first time; refreshes keep the current numbers visible
    final hasData = sales.sales.isNotEmpty || boughts.boughts.isNotEmpty || available.availableItems.isNotEmpty;
    setState(() => _isLoading = !hasData);

    try {
      await Future.wait([boughts.fetchBoughts(), sales.fetchSales(), available.fetchAvailableItems()]);
    } catch (_) {
      // Providers keep their own error state
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<_ItemSummary> _buildSummariesFromAvailableItems(List<AvailableItem> availableItems) {
    return availableItems.map((ai) {
        final fractions = ai.item?.fractions ?? const <Fraction>[];
        final unitFraction =
            fractions.where((f) => f.isUnit).isNotEmpty
                ? fractions.firstWhere((f) => f.isUnit)
                : (fractions.isNotEmpty ? fractions.first : null);

        final baseRatio = unitFraction?.ratio ?? 1;
        // AvailableItem.quantity is stored in base units in the backend.
        // Convert it into the selected base fraction quantity.
        final baseQuantity = baseRatio == 0 ? 0.0 : (ai.quantity / baseRatio);

        return _ItemSummary(
          itemId: ai.itemId,
          baseFractionId: unitFraction?.id ?? '',
          itemName: ai.item?.name ?? 'Unknown',
          fractionName: unitFraction?.name ?? 'Unit',
          baseRatio: baseRatio,
          fractions: fractions,
          previousQuantity: baseQuantity,
          boughtInPeriod: 0,
          boughtAmountInPeriod: 0,
          soldInPeriod: 0,
          soldAmountInPeriod: 0,
          remainingNow: baseQuantity,
          profitInPeriod: 0,
        );
      }).toList()
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
  }

  String _periodLabel(_Period p, AppLocalizations l10n) => switch (p) {
    _Period.today => l10n.today,
    _Period.yesterday => l10n.summaryYesterday,
    _Period.last7 => l10n.summaryLast7Days,
    _Period.last30 => l10n.summaryLast30Days,
    _Period.thisMonth => l10n.summaryThisMonth,
    _Period.custom => l10n.summaryCustomRange,
  };

  /// "Nov 12, 2026" for a whole day, otherwise the exact From – To with times.
  String _rangeLabel() {
    final wholeDays = _startDate == _day(_startDate) && _endDate == _endOfDay(_endDate);
    if (wholeDays) {
      final f = DateFormat.yMMMd();
      return _day(_startDate) == _day(_endDate)
          ? f.format(_startDate)
          : '${f.format(_startDate)} – ${f.format(_endDate)}';
    }
    final f = DateFormat('MMM d, y HH:mm');
    return '${f.format(_startDate)} – ${f.format(_endDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isOwnerView = widget.allowShopSwitch;
    final shops = context.watch<ShopProvider>().shops;
    // If a fixed shopId is provided (e.g. salesman side), always use that.
    final currentShopId =
        widget.fixedShopId != null && widget.fixedShopId!.isNotEmpty
            ? widget.fixedShopId
            : _selectedShopId ?? (shops.isNotEmpty ? shops.first.id : null);

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final boughtProvider = context.watch<BoughtProvider>();
    final salesProvider = context.watch<SalesProvider>();
    final availableItemProvider = context.watch<AvailableItemProvider>();

    // When no fixed shop is provided (owner view), we require shops.
    if (shops.isEmpty && widget.fixedShopId == null) {
      return _Message(icon: Icons.storefront_outlined, text: l10n.noShopsAvailable);
    }
    if (currentShopId == null || currentShopId.isEmpty) {
      return _Message(icon: Icons.storefront_outlined, text: l10n.pleaseSelectShop);
    }

    final start = _startDate;
    final endInclusive = _endDate;

    final filteredBoughts = boughtProvider.boughts.where((b) => b.shopId == currentShopId).toList();

    // Sales:
    // - In salesman context (fixedShopId != null), show ONLY sales that
    //   explicitly belong to the salesman's assigned shop.
    // - In owner context, keep a legacy fallback for older sales that
    //   have no shopId when there is only a single shop.
    final isSingleShopBusiness = shops.length == 1 && shops.first.id == currentShopId;
    final filteredSales =
        salesProvider.sales.where((s) {
          final hasShop = s.shopId != null && s.shopId!.isNotEmpty;
          if (widget.fixedShopId != null) return hasShop && s.shopId == currentShopId;
          return hasShop ? s.shopId == currentShopId : isSingleShopBusiness;
        }).toList();

    // One pass builds every per-item row; the totals are then summed from those rows
    final shopStock = availableItemProvider.availableItems.where((ai) => ai.shopId == currentShopId).toList();
    final summaries = _buildItemSummaries(
      filteredBoughts,
      filteredSales,
      start,
      _endDate,
      // Prev = stock now − bought since From + sold since From (by anyone in the shop). The stock
      // shown already has this phone's unsent sales taken off, but those sales aren't in the sales
      // list yet, so add them back to use the server's stock, matching the server's sales list.
      stockUnits: {
        for (final ai in shopStock) ai.itemId: ai.quantity + SaleOutbox.instance.pendingUnitsFor(ai.id),
      },
    );
    // Items in stock with no purchases or sales loaded still get a row
    final listed = {for (final s in summaries) s.itemId};
    summaries
      ..addAll(_buildSummariesFromAvailableItems(shopStock.where((ai) => !listed.contains(ai.itemId)).toList()))
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
    var totalSold = 0.0, totalBought = 0.0, totalProfit = 0.0;
    for (final s in summaries) {
      totalSold += s.soldAmountInPeriod;
      totalBought += s.boughtAmountInPeriod;
      totalProfit += s.profitInPeriod;
    }
    final salesCount =
        filteredSales.where((s) => !s.createdAt.isBefore(start) && !s.createdAt.isAfter(endInclusive)).length;

    // Stocked items without movements are already included above, so every item has a row
    final effectiveSummaries = summaries;
    final query = _search.trim().toLowerCase();
    final visible =
        query.isEmpty
            ? effectiveSummaries
            : effectiveSummaries.where((s) => s.itemName.toLowerCase().contains(query)).toList();

    final symbol = l10n.currencySymbol;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList.list(
              children: [
                if (shops.isNotEmpty && widget.allowShopSwitch) ...[
                  _ShopPicker(
                    shops: [for (final s in shops) (s.id, s.name)],
                    value: currentShopId,
                    onChanged: (id) => setState(() => _selectedShopId = id),
                  ),
                  const SizedBox(height: 12),
                ],
                // Period chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in _Period.values.where((p) => p != _Period.custom))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_periodLabel(p, l10n)),
                            selected: _period == p,
                            onSelected: (_) => _applyPeriod(p),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Exact From / To, down to the minute
                Row(
                  children: [
                    Expanded(
                      child: _DateTimeField(
                        label: l10n.summaryFrom,
                        value: _startDate,
                        highlighted: _period == _Period.custom,
                        onTap: _pickFrom,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateTimeField(
                        label: l10n.summaryTo,
                        value: _endDate,
                        highlighted: _period == _Period.custom,
                        onTap: _pickTo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TotalsCard(
                  rangeLabel: _rangeLabel(),
                  soldLabel: l10n.soldAmount,
                  sold: '$symbol ${_money.format(totalSold)}',
                  salesCountLabel: l10n.summarySalesCount(salesCount),
                  stats: [
                    if (isOwnerView) ...[
                      (Icons.local_shipping_outlined, l10n.boughtAmount, '$symbol ${_money.format(totalBought)}'),
                      (Icons.trending_up_rounded, l10n.profit, '$symbol ${_money.format(totalProfit)}'),
                      (
                        Icons.account_balance_wallet_outlined,
                        // Cash flow, not profit: profit is the figure next to it (FIFO cost)
                        l10n.summarySalesMinusPurchases,
                        '$symbol ${_money.format(totalSold - totalBought)}',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.summaryItemsTitle(visible.length),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (effectiveSummaries.length > 5) ...[
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: l10n.searchItems,
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: _Message(
                icon: Icons.inbox_outlined,
                text: query.isEmpty ? l10n.noDataForSelectedPeriod : l10n.summaryNoItemsMatch,
              ),
            )
          else
            // Built lazily: only the cards on screen are created, unlike the old DataTable
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _buildItemCard(visible[i], currentShopId, isOwnerView, l10n),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemCard(_ItemSummary s, String shopId, bool isOwnerView, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = '${s.itemId}_${s.baseFractionId}';
    final fractions =
        s.fractions.isNotEmpty
            ? s.fractions
            : <Fraction>[
              Fraction(
                id: s.baseFractionId,
                name: s.fractionName,
                ratio: s.baseRatio,
                sellingPrice: 0,
                purchasePrice: 0,
                itemId: s.itemId,
              ),
            ];
    final selectedUnitId = _selectedUnitIds[key] ?? s.baseFractionId;
    final selectedFraction = fractions.firstWhere((f) => f.id == selectedUnitId, orElse: () => fractions.first);
    final ratioFactor = selectedFraction.ratio == 0 ? 1.0 : s.baseRatio / selectedFraction.ratio;
    String q(double v) => _qty.format(v * ratioFactor);
    final symbol = l10n.currencySymbol;
    final lowStock = s.remainingNow * ratioFactor <= 0;

    void openTransactions() {
      final match =
          context
              .read<AvailableItemProvider>()
              .availableItems
              .where((ai) => ai.shopId == shopId && ai.itemId == s.itemId)
              .toList();
      if (match.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noItemFoundInAvailableItems)));
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TransactionsScreen(availableItem: match.first, showBefore: _startDate)),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                // Unit switcher: shows every quantity in the chosen unit
                PopupMenuButton<String>(
                  tooltip: l10n.unit,
                  initialValue: selectedFraction.id,
                  onSelected: (id) => setState(() => _selectedUnitIds[key] = id),
                  itemBuilder: (_) => [for (final f in fractions) PopupMenuItem(value: f.id, child: Text(f.name))],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedFraction.name,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, size: 18, color: scheme.onSecondaryContainer),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Stock flow for the period: start + bought − sold = left
            Row(
              children: [
                _FlowStat(label: l10n.prevQty, value: q(s.previousQuantity), onTap: openTransactions),
                _FlowStat(
                  label: l10n.bought,
                  value: '+${q(s.boughtInPeriod)}',
                  color: Colors.blue.shade700,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => BoughtsScreen(
                                filterItemId: s.itemId,
                                filterFractionId: null,
                                filterStart: _startDate,
                                filterEnd: _endDate,
                                initialShopId: shopId,
                              ),
                        ),
                      ),
                ),
                _FlowStat(
                  label: l10n.sold,
                  value: '−${q(s.soldInPeriod)}',
                  color: Colors.green.shade700,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => FilteredSalesHistoryScreen(
                                itemId: s.itemId,
                                fractionId: null,
                                shopId: shopId,
                                start: _startDate,
                                end: _endDate,
                              ),
                        ),
                      ),
                ),
                _FlowStat(
                  label: l10n.remaining,
                  value: q(s.remainingNow),
                  color: lowStock ? scheme.error : null,
                  bold: true,
                ),
              ],
            ),
            if (s.soldAmountInPeriod != 0 || s.boughtAmountInPeriod != 0) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MoneyPill(label: l10n.soldAmt, value: '$symbol ${_money.format(s.soldAmountInPeriod)}'),
                    if (isOwnerView) ...[
                      _MoneyPill(label: l10n.boughtAmt, value: '$symbol ${_money.format(s.boughtAmountInPeriod)}'),
                      _MoneyPill(
                        label: l10n.profit,
                        value: '$symbol ${_money.format(s.profitInPeriod)}',
                        color: s.profitInPeriod < 0 ? scheme.error : Colors.green.shade700,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The unit an item is shown in by default: its base unit (isUnit / ratio 1), else the smallest.
  static Fraction? _displayUnit(List<Fraction> fractions) {
    if (fractions.isEmpty) return null;
    for (final f in fractions) {
      if (f.isUnit) return f;
    }
    for (final f in fractions) {
      if (f.ratio == 1) return f;
    }
    return fractions.reduce((a, b) => a.ratio <= b.ratio ? a : b);
  }

  /// One row per item. Purchases and sales can be in different units (cartons bought, pieces
  /// sold), so every quantity is converted to base units with the ratio of the unit it was
  /// recorded in, then shown in the item's base unit (the row's unit switcher converts from there).
  ///
  /// "Remaining" is the shop's actual stock when known ([stockUnits], base units per item), and the
  /// quantity at the start of the period is worked back from it, so the row always matches stock.
  List<_ItemSummary> _buildItemSummaries(
    List<Bought> boughts,
    List<SoldItem> sales,
    DateTime start,
    DateTime end, {
    Map<String, double> stockUnits = const {},
  }) {
    // [end] is already the exact inclusive end (end of day for the presets, or the chosen minute)
    final endInclusive = end;
    final Map<String, _ItemSummaryAccumulator> acc = {};

    double ratioOf(Fraction? recorded, String fractionId, List<Fraction> fractions) {
      if (recorded != null && recorded.ratio > 0) return recorded.ratio;
      for (final f in fractions) {
        if (f.id == fractionId && f.ratio > 0) return f.ratio;
      }
      return 1;
    }

    _ItemSummaryAccumulator forItem(String itemId, String? name, List<Fraction> fractions) {
      final a = acc.putIfAbsent(
        itemId,
        () => _ItemSummaryAccumulator(itemId: itemId, itemName: name ?? 'Unknown', fractions: fractions),
      );
      if (a.fractions.isEmpty && fractions.isNotEmpty) a.fractions = fractions;
      return a;
    }

    for (final b in boughts) {
      final fractions = b.item?.fractions ?? const <Fraction>[];
      final a = forItem(b.itemId, b.item?.name, fractions);
      final units = b.quantity * ratioOf(b.fraction, b.fractionId, fractions);
      final t = b.createdTime;
      if (!t.isBefore(start)) a.boughtSinceStart += units;
      if (t.isBefore(start)) a.boughtBefore += units;
      if (!t.isBefore(start) && !t.isAfter(endInclusive)) {
        a.boughtInPeriod += units;
        a.boughtAmountInPeriod += b.quantity * b.fractionPurchasePrice;
      }
      a.boughtAll += units;
    }

    for (final s in sales) {
      final fractions = s.item?.fractions ?? const <Fraction>[];
      final a = forItem(s.itemId, s.item?.name, fractions);
      final units = s.quantity * ratioOf(s.fraction, s.fractionId, fractions);
      final t = s.createdAt;
      if (!t.isBefore(start)) a.soldSinceStart += units;
      if (t.isBefore(start)) a.soldBefore += units;
      if (!t.isBefore(start) && !t.isAfter(endInclusive)) {
        a.soldInPeriod += units;
        a.soldAmountInPeriod += s.soldPrice;
        a.profitInPeriod += s.profit ?? 0;
      }
      a.soldAll += units;
    }

    return acc.values.map((a) {
      final unit = _displayUnit(a.fractions);
      final unitRatio = (unit?.ratio ?? 1) > 0 ? unit!.ratio : 1.0;
      final stock = stockUnits[a.itemId];
      // From the real stock when we have it; otherwise from the history we loaded
      final remainingUnits = stock ?? (a.boughtAll - a.soldAll);
      final previousUnits =
          stock != null ? stock - a.boughtSinceStart + a.soldSinceStart : a.boughtBefore - a.soldBefore;
      return _ItemSummary(
        itemId: a.itemId,
        baseFractionId: unit?.id ?? '',
        itemName: a.itemName,
        fractionName: unit?.name ?? 'Unit',
        baseRatio: unitRatio,
        fractions: a.fractions,
        previousQuantity: previousUnits / unitRatio,
        boughtInPeriod: a.boughtInPeriod / unitRatio,
        boughtAmountInPeriod: a.boughtAmountInPeriod,
        soldInPeriod: a.soldInPeriod / unitRatio,
        soldAmountInPeriod: a.soldAmountInPeriod,
        remainingNow: remainingUnits / unitRatio,
        profitInPeriod: a.profitInPeriod,
      );
    }).toList()
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
  }
}

class _ItemSummaryAccumulator {
  final String itemId;
  final String itemName;
  List<Fraction> fractions;

  // Base units
  double boughtBefore = 0;
  double soldBefore = 0;
  double boughtSinceStart = 0;
  double soldSinceStart = 0;
  double boughtInPeriod = 0;
  double soldInPeriod = 0;
  double boughtAll = 0;
  double soldAll = 0;

  // Money
  double boughtAmountInPeriod = 0;
  double soldAmountInPeriod = 0;
  double profitInPeriod = 0;

  _ItemSummaryAccumulator({required this.itemId, required this.itemName, required this.fractions});
}

class _ItemSummary {
  final String itemId;
  final String baseFractionId;
  final String itemName;
  final String fractionName;
  final double baseRatio;
  final List<Fraction> fractions;
  final double previousQuantity;
  final double boughtInPeriod;
  final double boughtAmountInPeriod;
  final double soldInPeriod;
  final double soldAmountInPeriod;
  final double remainingNow;
  final double profitInPeriod;

  _ItemSummary({
    required this.itemId,
    required this.baseFractionId,
    required this.itemName,
    required this.fractionName,
    required this.baseRatio,
    required this.fractions,
    required this.previousQuantity,
    required this.boughtInPeriod,
    required this.boughtAmountInPeriod,
    required this.soldInPeriod,
    required this.soldAmountInPeriod,
    required this.remainingNow,
    required this.profitInPeriod,
  });
}



// ---------------------------------------------------------------------------
// Display widgets
// ---------------------------------------------------------------------------

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

/// Tappable From / To box showing the date and the exact time.
class _DateTimeField extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool highlighted;
  final VoidCallback onTap;

  const _DateTimeField({required this.label, required this.value, required this.highlighted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: highlighted ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.yMMMd().format(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      DateFormat.Hm().format(value),
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_calendar_rounded, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopPicker extends StatelessWidget {
  final List<(String, String)> shops; // (id, name)
  final String value;
  final ValueChanged<String> onChanged;

  const _ShopPicker({required this.shops, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      value: shops.any((s) => s.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.storefront_outlined, color: scheme.primary),
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
      borderRadius: BorderRadius.circular(14),
      items: [
        for (final (id, name) in shops)
          DropdownMenuItem(value: id, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
      onChanged: (id) {
        if (id != null) onChanged(id);
      },
    );
  }
}

/// Gradient card with the period's sold total and, for owners, purchases, profit and net.
class _TotalsCard extends StatelessWidget {
  final String rangeLabel;
  final String soldLabel;
  final String sold;
  final String salesCountLabel;
  final List<(IconData, String, String)> stats;

  const _TotalsCard({
    required this.rangeLabel,
    required this.soldLabel,
    required this.sold,
    required this.salesCountLabel,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimary;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.55)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: on.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rangeLabel,
                  style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: on.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text(salesCountLabel, style: TextStyle(color: on, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(soldLabel, style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(sold, style: TextStyle(color: on, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: on.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (icon, label, value) in stats)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 14, color: on.withValues(alpha: 0.8)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(value, style: TextStyle(color: on, fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One step of an item's stock flow (start / bought / sold / left). Tappable when [onTap] is set.
class _FlowStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final VoidCallback? onTap;

  const _FlowStat({required this.label, required this.value, this.color, this.bold = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color ?? theme.colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyPill extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MoneyPill({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
            TextSpan(text: value, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
