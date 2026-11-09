import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/available_item_provider.dart';
import 'package:inventory_frontend/providers/basket_provider.dart';
import 'package:inventory_frontend/providers/category_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

final _qtyFormat = NumberFormat('#,##0.##');
final _moneyFormat = NumberFormat('#,##0.##');

String _money(BuildContext context, num value) =>
    '${AppLocalizations.of(context)!.currencySymbol} ${_moneyFormat.format(value)}';

/// The unit a stock row sells in by default: the item's base unit (or the smallest one).
Fraction? _defaultUnit(AvailableItem stock) {
  final fractions = stock.item?.fractions ?? const <Fraction>[];
  if (fractions.isEmpty) return null;
  return fractions.where((f) => f.isUnit).firstOrNull ?? fractions.reduce((a, b) => a.ratio <= b.ratio ? a : b);
}

/// Point-of-sale screen: find items quickly (search, categories, frequently sold), build a basket
/// of several items, take payment and record everything as one receipt. Works offline.
class PosScreen extends StatefulWidget {
  /// Optionally start with this item (and unit) in the basket, e.g. from the Available Items list.
  final AvailableItem? initialStock;
  final Fraction? initialFraction;

  /// False when embedded in a dashboard that already has an app bar.
  final bool showAppBar;

  const PosScreen({super.key, this.initialStock, this.initialFraction, this.showAppBar = true});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final Map<String, String> _rowUnit = {}; // stockId -> fractionId chosen on the row
  String _query = '';
  String? _categoryId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      final stock = widget.initialStock;
      if (stock != null && mounted) {
        final fresh = context.read<AvailableItemProvider>().getAvailableItem(stock.id) ?? stock;
        final unit = widget.initialFraction ?? _defaultUnit(fresh);
        if (unit != null) {
          _rowUnit[fresh.id] = unit.id;
          _add(fresh, unit);
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Stock is reused if fetched in the last minute; categories and recent sales come from the
  /// phone's saved copy when offline.
  Future<void> _load({bool force = false}) async {
    final stockProvider = context.read<AvailableItemProvider>();
    final categories = context.read<CategoryProvider>();
    final sales = context.read<SalesProvider>();
    setState(() => _loading = stockProvider.availableItems.isEmpty);
    await Future.wait([
      stockProvider.fetchAvailableItems(force: force),
      if (force || categories.categories.isEmpty) categories.fetchCategories(),
      if (force || sales.sales.isEmpty) sales.fetchUserSales(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Fraction? _unitFor(AvailableItem stock) {
    final chosen = _rowUnit[stock.id];
    final fractions = stock.item?.fractions ?? const <Fraction>[];
    return fractions.where((f) => f.id == chosen).firstOrNull ?? _defaultUnit(stock);
  }

  void _add(AvailableItem stock, Fraction unit, {double quantity = 1}) {
    final l10n = AppLocalizations.of(context)!;
    final basket = context.read<BasketProvider>();
    switch (basket.add(stock, unit, quantity: quantity)) {
      case BasketResult.ok:
        HapticFeedback.selectionClick();
        // Found by search: clear it and keep the keyboard up so the next item can be typed at once
        if (_query.isNotEmpty) {
          setState(() {
            _searchController.clear();
            _query = '';
          });
          _searchFocus.requestFocus();
          _snack(l10n.posAddedItem(stock.item?.name ?? '', '${_qtyFormat.format(quantity)} ${unit.name}'));
        }
      case BasketResult.notEnoughStock:
        _snack(l10n.posNotEnoughStock(_qtyFormat.format(basket.remainingFor(stock, unit)), unit.name));
      case BasketResult.otherShop:
        _snack(l10n.posOtherShop);
    }
  }

  /// Enter in the search box adds the item when the search narrowed it down to one sellable item;
  /// otherwise the keyboard stays up to keep typing. Matches are worked out now, not taken from
  /// the last build, so a fast "type + enter" still sees the latest text.
  void _submitSearch() {
    final basket = context.read<BasketProvider>();
    final categoryNames = {for (final c in context.read<CategoryProvider>().categories) c.id: c.name};
    final sellable =
        context
            .read<AvailableItemProvider>()
            .availableItems
            .where((s) => _defaultUnit(s) != null && _matches(s, categoryNames))
            .where((s) => basket.remainingFor(s, _unitFor(s)!) >= 1 - 1e-9)
            .toList();
    if (_query.isNotEmpty && sellable.length == 1) {
      _add(sellable.single, _unitFor(sellable.single)!);
    } else {
      _searchFocus.requestFocus();
    }
  }

  /// The − on a row: take one of that unit back out of the basket.
  void _removeOne(AvailableItem stock, Fraction unit) {
    final basket = context.read<BasketProvider>();
    final line = basket.lines.where((l) => l.stock.id == stock.id && l.fraction.id == unit.id).firstOrNull;
    if (line == null) return;
    basket.setQuantity(line, line.quantity > 1 ? line.quantity - 1 : 0);
    HapticFeedback.selectionClick();
  }

  /// Long-press on an item: type how many to add (e.g. 12) instead of tapping + repeatedly.
  Future<void> _addWithQuantity(AvailableItem stock, Fraction unit) async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = context.read<BasketProvider>().remainingFor(stock, unit);
    final quantity = await _askNumber(
      context,
      title: '${stock.item?.name ?? ''} · ${unit.name}',
      initial: 1,
      helper: l10n.dashLeft(_qtyFormat.format(remaining), unit.name),
      quickValues: const [2, 5, 10, 12],
    );
    if (quantity != null && quantity > 0 && mounted) _add(stock, unit, quantity: quantity);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  /// Most sold items of the last 30 days (from sales saved on this phone).
  List<AvailableItem> _frequent(List<AvailableItem> stock) {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final counts = <String, int>{};
    for (final sale in context.read<SalesProvider>().sales) {
      if (sale.createdAt.isAfter(since)) counts[sale.itemId] = (counts[sale.itemId] ?? 0) + 1;
    }
    final ranked =
        stock.where((s) => counts.containsKey(s.itemId) && s.quantity > 0).toList()
          ..sort((a, b) => counts[b.itemId]!.compareTo(counts[a.itemId]!));
    return ranked.take(6).toList();
  }

  bool _matches(AvailableItem stock, Map<String, String> categoryNames) {
    if (_categoryId != null && stock.item?.categoryId != _categoryId) return false;
    if (_query.isEmpty) return true;
    final haystack = '${stock.item?.name ?? ''} ${categoryNames[stock.item?.categoryId] ?? ''}'.toLowerCase();
    return _query.toLowerCase().split(RegExp(r'\s+')).every(haystack.contains);
  }

  void _openBasket() {
    context.read<BasketProvider>().refreshStock(context.read<AvailableItemProvider>().availableItems);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BasketSheet(onPay: _openCheckout),
    );
  }

  Future<void> _openCheckout() async {
    final result = await showModalBottomSheet<_ReceiptData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CheckoutSheet(),
    );
    if (result == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReceiptSheet(data: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stockProvider = context.watch<AvailableItemProvider>();
    final basket = context.watch<BasketProvider>();
    final auth = context.watch<AuthProvider>();
    final stock = stockProvider.availableItems.where((s) => _defaultUnit(s) != null).toList();
    final categoryNames = {for (final c in context.watch<CategoryProvider>().categories) c.id: c.name};
    final usedCategories = stock.map((s) => s.item?.categoryId).whereType<String>().toSet();
    final showShopName = (auth.isOwner || auth.isAdmin) && stock.map((s) => s.shopId).toSet().length > 1;
    final filtered = stock.where((s) => _matches(s, categoryNames)).toList();
    final browsing = _query.isEmpty && _categoryId == null;
    final frequent = browsing ? _frequent(stock) : const <AvailableItem>[];

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (stock.isEmpty) {
      content = _EmptyState(
        icon: stockProvider.error != null ? Icons.cloud_off_rounded : Icons.inventory_2_outlined,
        message: stockProvider.error != null ? l10n.loadFailedNoData : l10n.noItemsAssignedToYou,
        onRetry: () => _load(force: true),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (frequent.isNotEmpty) ...[
              _SectionLabel(l10n.posFrequent),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in frequent)
                    GestureDetector(
                      onLongPress: () => _addWithQuantity(s, _unitFor(s)!),
                      child: ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(s.item?.name ?? ''),
                        onPressed: () => _add(s, _unitFor(s)!),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (filtered.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 48), child: Center(child: Text(l10n.posNoMatch))),
            for (final s in filtered)
              _StockRow(
                stock: s,
                unit: _unitFor(s)!,
                lineQty: basket.quantityOf(s.id, _unitFor(s)!.id),
                remaining: basket.remainingFor(s, _unitFor(s)!),
                shopName: showShopName ? s.shop?.name : null,
                onUnitChanged: (f) => setState(() => _rowUnit[s.id] = f.id),
                onAdd: () => _add(s, _unitFor(s)!),
                onAddQuantity: () => _addWithQuantity(s, _unitFor(s)!),
                onRemoveOne: () => _removeOne(s, _unitFor(s)!),
              ),
          ],
        ),
      );
    }

    final body = Column(
      children: [
        const OfflineBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: (v) => setState(() => _query = v.trim()),
            textInputAction: TextInputAction.search,
            // Enter adds the item when the search narrowed it down to one; otherwise keep typing
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
              hintText: l10n.searchItems,
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _query.isEmpty
                      ? null
                      : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed:
                            () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                      ),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        if (usedCategories.length > 1)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CategoryChip(
                  label: l10n.posAll,
                  selected: _categoryId == null,
                  onTap: () => setState(() => _categoryId = null),
                ),
                for (final id in usedCategories)
                  _CategoryChip(
                    label: categoryNames[id] ?? '…',
                    selected: _categoryId == id,
                    onTap: () => setState(() => _categoryId = _categoryId == id ? null : id),
                  ),
              ],
            ),
          ),
        Expanded(child: content),
        if (!basket.isEmpty) _BasketBar(onOpen: _openBasket),
      ],
    );

    return Scaffold(appBar: widget.showAppBar ? AppBar(title: Text(l10n.sellItem)) : null, body: body);
  }
}

// ---------------------------------------------------------------------------
// Item list pieces
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
  );
}

class _StockRow extends StatelessWidget {
  final AvailableItem stock;
  final Fraction unit;
  final double lineQty; // how many of [unit] are in the basket
  final double remaining; // in [unit]s
  final String? shopName;
  final ValueChanged<Fraction> onUnitChanged;
  final VoidCallback onAdd;
  final VoidCallback onAddQuantity;
  final VoidCallback onRemoveOne;

  const _StockRow({
    required this.stock,
    required this.unit,
    required this.lineQty,
    required this.remaining,
    required this.shopName,
    required this.onUnitChanged,
    required this.onAdd,
    required this.onAddQuantity,
    required this.onRemoveOne,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final fractions = stock.item?.fractions ?? const <Fraction>[];
    final soldOut = remaining < 1 - 1e-9;
    final low = !soldOut && remaining <= 5;
    final stockColor = soldOut ? scheme.outline : (low ? Colors.orange.shade800 : scheme.onSurfaceVariant);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: soldOut ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      // The whole row is a big target: tap adds one, long-press asks how many
      child: InkWell(
        onTap: soldOut ? null : onAdd,
        onLongPress: soldOut ? null : onAddQuantity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName != null ? '${stock.item?.name} · $shopName' : stock.item?.name ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: soldOut ? scheme.outline : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (low) Icon(Icons.warning_amber_rounded, size: 14, color: stockColor),
                        if (low) const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            soldOut ? l10n.posSoldOut : l10n.dashLeft(_qtyFormat.format(remaining), unit.name),
                            style: TextStyle(fontSize: 12, color: stockColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_money(context, unit.sellingPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (fractions.length > 1)
                    PopupMenuButton<Fraction>(
                      initialValue: unit,
                      onSelected: onUnitChanged,
                      itemBuilder:
                          (_) => [
                            for (final f in fractions)
                              PopupMenuItem(value: f, child: Text('${f.name} · ${_money(context, f.sellingPrice)}')),
                          ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(unit.name, style: TextStyle(fontSize: 12, color: scheme.primary)),
                            Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(unit.name, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(width: 4),
              // In the basket: − count + stepper; otherwise a single +. No tooltip on +, because
              // long-press means "how many" (announced via semantics instead).
              if (lineQty > 0) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemoveOne,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                GestureDetector(
                  onTap: onAddQuantity,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 24),
                    child: Text(
                      _qtyFormat.format(lineQty),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ],
              Semantics(
                label: l10n.posHoldForQuantity,
                child: GestureDetector(
                  onLongPress: soldOut ? null : onAddQuantity,
                  child: IconButton.filledTonal(onPressed: soldOut ? null : onAdd, icon: const Icon(Icons.add)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  const _EmptyState({required this.icon, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context)!.retry),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Basket
// ---------------------------------------------------------------------------

class _BasketBar extends StatelessWidget {
  final VoidCallback onOpen;
  const _BasketBar({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final basket = context.watch<BasketProvider>();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.shopping_basket_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.posItemsCount(basket.lineCount),
                        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
                      ),
                      Text(
                        _money(context, basket.total),
                        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: Text(l10n.posPay),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a number. [quickValues] are one-tap answers (e.g. ×2, ×5, ×10, ×12).
Future<double?> _askNumber(
  BuildContext context, {
  required String title,
  required double initial,
  String? helper,
  List<double> quickValues = const [],
}) {
  final controller = TextEditingController(text: _qtyFormat.format(initial).replaceAll(',', ''))
    ..selection = TextSelection(baseOffset: 0, extentOffset: _qtyFormat.format(initial).replaceAll(',', '').length);
  return showDialog<double>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(helperText: helper),
                onSubmitted: (v) => Navigator.pop(context, double.tryParse(v.trim())),
              ),
              if (quickValues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in quickValues)
                      ActionChip(label: Text('×${_qtyFormat.format(v)}'), onPressed: () => Navigator.pop(context, v)),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(context, double.tryParse(controller.text.trim())),
              child: Text(AppLocalizations.of(context)!.confirm),
            ),
          ],
        ),
  );
}

class _BasketSheet extends StatelessWidget {
  final VoidCallback onPay;
  const _BasketSheet({required this.onPay});

  void _report(BuildContext context, BasketResult result, BasketLine line) {
    if (result != BasketResult.notEnoughStock) return;
    final basket = context.read<BasketProvider>();
    final left = basket.remainingFor(line.stock, line.fraction) + basket.quantityOf(line.stock.id, line.fraction.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.posNotEnoughStock(_qtyFormat.format(left), line.fraction.name)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final basket = context.watch<BasketProvider>();
    final isOwner = context.read<AuthProvider>().isOwner;
    final lines = basket.lines;
    if (lines.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder:
          (context, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l10n.posBasket} · ${l10n.posItemsCount(lines.length)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: basket.clear,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(l10n.posClearBasket),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final line = lines[i];
                    final fractions = line.stock.item?.fractions ?? const <Fraction>[];
                    return Dismissible(
                      key: ValueKey(line.key),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => basket.remove(line),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: const Icon(Icons.delete_outline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      if (fractions.length > 1)
                                        PopupMenuButton<Fraction>(
                                          initialValue: line.fraction,
                                          onSelected: (f) => _report(context, basket.changeUnit(line, f), line),
                                          itemBuilder:
                                              (_) => [
                                                for (final f in fractions) PopupMenuItem(value: f, child: Text(f.name)),
                                              ],
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                line.fraction.name,
                                                style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                              ),
                                              Icon(
                                                Icons.arrow_drop_down,
                                                size: 18,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Text(line.fraction.name),
                                      const Text('  ·  '),
                                      InkWell(
                                        onTap:
                                            isOwner
                                                ? () async {
                                                  final price = await _askNumber(
                                                    context,
                                                    title: l10n.posPricePer(line.fraction.name),
                                                    initial: line.unitPrice,
                                                  );
                                                  if (price != null && price >= 0) basket.setPrice(line, price);
                                                }
                                                : null,
                                        child: Text(
                                          _money(context, line.unitPrice),
                                          style: TextStyle(
                                            decoration: isOwner ? TextDecoration.underline : null,
                                            decorationStyle: TextDecorationStyle.dotted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            _Stepper(
                              quantity: line.quantity,
                              onMinus:
                                  () => basket.setQuantity(line, line.quantity - 1 < 0.0001 ? 0 : line.quantity - 1),
                              onPlus: () => _report(context, basket.setQuantity(line, line.quantity + 1), line),
                              onEdit: () async {
                                final q = await _askNumber(context, title: l10n.quantityLabel, initial: line.quantity);
                                if (q != null && context.mounted) _report(context, basket.setQuantity(line, q), line);
                              },
                            ),
                            SizedBox(
                              width: 84,
                              child: Text(
                                _money(context, line.amount),
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.total),
                            Text(
                              _money(context, basket.total),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        ),
                        onPressed:
                            lines.isEmpty
                                ? null
                                : () {
                                  Navigator.pop(context);
                                  onPay();
                                },
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(l10n.posPay),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final double quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEdit;
  const _Stepper({required this.quantity, required this.onMinus, required this.onPlus, required this.onEdit});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onMinus,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 36),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          alignment: Alignment.center,
          child: Text(_qtyFormat.format(quantity), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
      IconButton(visualDensity: VisualDensity.compact, onPressed: onPlus, icon: const Icon(Icons.add_circle_outline)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Checkout and receipt
// ---------------------------------------------------------------------------

class _ReceiptData {
  final PendingSale sale;
  final bool confirmed;
  final List<BasketLine> lines;
  final double total;
  final double? cash;
  const _ReceiptData({
    required this.sale,
    required this.confirmed,
    required this.lines,
    required this.total,
    this.cash,
  });
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet();

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _cashController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  /// Exact amount plus the next round notes above the total (e.g. 1,045 -> 1,050 / 1,100 / 1,500).
  List<double> _suggestions(double total) {
    final values = <double>{total};
    for (final step in [50, 100, 500, 1000]) {
      final rounded = (total / step).ceil() * step.toDouble();
      if (rounded > total) values.add(rounded);
    }
    return values.toList()..sort();
  }

  Future<void> _confirm() async {
    final basket = context.read<BasketProvider>();
    final sales = context.read<SalesProvider>();
    final lines = basket.lines;
    final total = basket.total;
    final cash = double.tryParse(_cashController.text.trim());
    setState(() => _submitting = true);
    try {
      final result = await sales.checkout(lines);
      basket.clear();
      if (!mounted) return;
      Navigator.pop(
        context,
        _ReceiptData(sale: result.sale, confirmed: result.confirmed, lines: lines, total: total, cash: cash),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = context.watch<BasketProvider>().total;
    final cash = double.tryParse(_cashController.text.trim());
    final change = cash == null ? null : cash - total;
    final short = change != null && change < -1e-9;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.total, textAlign: TextAlign.center),
          Text(
            _money(context, total),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cashController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.posCashReceived,
              prefixText: '${l10n.currencySymbol} ',
              border: const OutlineInputBorder(),
              errorText: short ? l10n.posCashShort : null,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final v in _suggestions(total))
                ActionChip(
                  label: Text(v == total ? l10n.posExact : _moneyFormat.format(v)),
                  onPressed: () => setState(() => _cashController.text = _qtyFormat.format(v).replaceAll(',', '')),
                ),
            ],
          ),
          if (change != null && !short) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.posChange, style: const TextStyle(fontSize: 16)),
                Text(
                  _money(context, change),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.green.shade700),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _submitting || short ? null : _confirm,
            icon:
                _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
            label: Text(l10n.posConfirmSale, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _ReceiptSheet extends StatefulWidget {
  final _ReceiptData data;
  const _ReceiptSheet({required this.data});

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  bool _undoing = false;

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final stock = context.read<AvailableItemProvider>();
    setState(() => _undoing = true);
    try {
      await context.read<SalesProvider>().undoSale(widget.data.sale);
      stock.refreshSoon();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(l10n.posSaleUndone)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _undoing = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = widget.data;
    final color = d.confirmed ? Colors.green.shade700 : Colors.orange.shade800;
    final change = d.cash == null ? null : d.cash! - d.total;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(d.confirmed ? Icons.check_circle : Icons.cloud_done_outlined, size: 56, color: color),
            const SizedBox(height: 8),
            Text(
              d.confirmed ? l10n.posSaleRecorded : l10n.posSavedOffline,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
            ),
            Text(
              DateFormat('MMM d, HH:mm').format(d.sale.createdAt),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in d.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('${l.itemName} · ${_qtyFormat.format(l.quantity)} ${l.fraction.name}')),
                          Text(_money(context, l.amount)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            _ReceiptRow(label: l10n.total, value: _money(context, d.total), bold: true),
            if (d.cash != null) _ReceiptRow(label: l10n.posCashReceived, value: _money(context, d.cash!)),
            if (change != null) _ReceiptRow(label: l10n.posChange, value: _money(context, change), bold: true),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _undoing ? null : _undo,
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  icon:
                      _undoing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.undo),
                  label: Text(l10n.posUndo),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(l10n.posNewSale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _ReceiptRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: bold ? 17 : 14, fontWeight: bold ? FontWeight.w800 : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
