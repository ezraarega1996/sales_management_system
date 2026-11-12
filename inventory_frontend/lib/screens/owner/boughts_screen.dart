import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:inventory_frontend/models/bought.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/bought_provider.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/providers/shop_provider.dart';
import 'package:inventory_frontend/screens/owner/items_screen.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';

/// Stock purchases ("added items"). Shown inside the owner dashboard (which provides the app
/// bar, so [showAppBar] is false there) and pushed from the summary with optional filters.
class BoughtsScreen extends StatefulWidget {
  final String? filterItemId;
  final String? filterFractionId;
  final DateTime? filterStart;

  /// A bare date (midnight) means "through the end of that day"; any other time is used as is.
  final DateTime? filterEnd;
  final String? initialShopId;
  final bool showAppBar;

  const BoughtsScreen({
    super.key,
    this.filterItemId,
    this.filterFractionId,
    this.filterStart,
    this.filterEnd,
    this.initialShopId,
    this.showAppBar = true,
  });

  @override
  State<BoughtsScreen> createState() => _BoughtsScreenState();
}

/// One row of the flattened list: a day header or a purchase.
sealed class _Row {}

class _DayRow extends _Row {
  final DateTime day;
  final double total;
  _DayRow(this.day, this.total);
}

class _BoughtRow extends _Row {
  final Bought bought;
  _BoughtRow(this.bought);
}

/// Stand-in when a purchase's unit can't be found in the item's units.
Fraction _placeholderFraction({String name = ''}) =>
    Fraction(id: '', name: name, ratio: 1, sellingPrice: 0, purchasePrice: 0, itemId: '');

Fraction? _findFraction(Iterable<Fraction>? fractions, String? id) {
  if (fractions == null || id == null) return null;
  for (final f in fractions) {
    if (f.id == id) return f;
  }
  return null;
}

double _lineTotal(Bought b) => b.quantity * b.fractionPurchasePrice;

class _BoughtsScreenState extends State<BoughtsScreen> {
  static final _money = NumberFormat('#,##0.00');

  final Map<String, String> _selectedFractionIds = {}; // boughtId -> fractionId shown
  final Set<String> _deleting = {};
  bool _isLoading = true;
  String _query = '';
  late String? _shopFilter = widget.initialShopId; // null = all shops

  // Memoized grouping, keyed on the list identities and the filters
  List<Bought>? _groupedFrom;
  List<Item>? _groupedItems;
  String? _groupedQuery;
  String? _groupedShop;
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
    final boughts = context.read<BoughtProvider>();
    // Keep the current list visible while refreshing; only show a spinner when there is nothing yet
    setState(() => _isLoading = boughts.boughts.isEmpty);
    await Future.wait([
      boughts.fetchBoughts(),
      context.read<ItemProvider>().fetchItems(),
      context.read<ShopProvider>().getShops(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  bool _matchesFixedFilters(Bought b) {
    if (widget.filterItemId != null && b.itemId != widget.filterItemId) return false;
    if (widget.filterFractionId != null && b.fractionId != widget.filterFractionId) return false;
    // isBefore/isAfter compare instants, so UTC times from the server compare correctly with local filters
    if (widget.filterStart != null && b.createdTime.isBefore(widget.filterStart!)) return false;
    if (widget.filterEnd != null) {
      final e = widget.filterEnd!;
      final endInclusive =
          e == DateTime(e.year, e.month, e.day) ? DateTime(e.year, e.month, e.day, 23, 59, 59, 999) : e;
      if (b.createdTime.isAfter(endInclusive)) return false;
    }
    return true;
  }

  void _regroupIfNeeded(List<Bought> boughts, List<Item> items, String? shopFilter) {
    if (identical(boughts, _groupedFrom) &&
        identical(items, _groupedItems) &&
        _query == _groupedQuery &&
        shopFilter == _groupedShop) {
      return;
    }
    _groupedFrom = boughts;
    _groupedItems = items;
    _groupedQuery = _query;
    _groupedShop = shopFilter;

    final names = {for (final i in items) i.id: i.name.toLowerCase()};
    final q = _query.trim().toLowerCase();
    final visible =
        boughts.where((b) {
            if (!_matchesFixedFilters(b)) return false;
            if (shopFilter != null && b.shopId != shopFilter) return false;
            if (q.isEmpty) return true;
            final name = b.item?.name.toLowerCase() ?? names[b.itemId] ?? '';
            return name.contains(q);
          }).toList()
          ..sort((a, b) => b.createdTime.compareTo(a.createdTime));

    // Insert a header before each new day; its total is only known once the whole day is seen
    final rows = <_Row>[];
    DateTime? currentDay;
    var headerIndex = -1;
    var dayTotal = 0.0;
    void closeDay() {
      if (headerIndex >= 0) rows[headerIndex] = _DayRow(currentDay!, dayTotal);
    }

    for (final b in visible) {
      final local = b.createdTime.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day != currentDay) {
        closeDay();
        currentDay = day;
        headerIndex = rows.length;
        rows.add(_DayRow(day, 0));
        dayTotal = 0;
      }
      rows.add(_BoughtRow(b));
      dayTotal += _lineTotal(b);
    }
    closeDay();

    _rows = rows;
    _shownCount = visible.length;
    _shownTotal = visible.fold(0.0, (sum, b) => sum + _lineTotal(b));
  }

  Future<void> _openForm({Bought? bought}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showModalBottomSheet<_SaveOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder:
          (_) => _BoughtForm(
            bought: bought,
            initialItemId: widget.filterItemId,
            initialFractionId: widget.filterFractionId,
            initialShopId: _shopFilter ?? widget.initialShopId,
          ),
    );
    if (outcome == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(outcome == _SaveOutcome.saved ? l10n.success : l10n.boughtPricesNotUpdated)),
    );
  }

  Future<void> _delete(Bought bought) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<BoughtProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.deleteBoughtItem),
            content: Text(l10n.confirmDeleteBought),
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
    if (confirm != true || !mounted) return;
    setState(() => _deleting.add(bought.id));
    // The provider removes the row itself, so there is no need to reload everything
    final ok = await provider.deleteBought(bought.id);
    if (mounted) setState(() => _deleting.remove(bought.id));
    messenger.showSnackBar(SnackBar(content: Text(ok ? l10n.success : (provider.error ?? l10n.error))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isOwner || auth.isAdmin;

    return Scaffold(
      appBar:
          widget.showAppBar
              ? AppBar(
                title: Text(l10n.boughtItems),
                actions: [IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: l10n.refresh, onPressed: _load)],
              )
              : null,
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildList(l10n, canManage),
      floatingActionButton:
          canManage
              ? FloatingActionButton.extended(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.add),
              )
              : null,
    );
  }

  Widget _buildList(AppLocalizations l10n, bool canManage) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<BoughtProvider>();
    final items = context.watch<ItemProvider>().items;
    final shopList = context.watch<ShopProvider>().shops;

    // Shop chips only when the (fixed-filtered) purchases span several shops
    final shopNames = {for (final s in shopList) s.id: s.name};
    final shops = <String, String>{};
    for (final b in provider.boughts) {
      final id = b.shopId;
      if (id == null || !_matchesFixedFilters(b)) continue;
      shops[id] = b.shop?.name ?? shopNames[id] ?? l10n.unknownShop;
    }
    final showShopChips = shops.length > 1;
    final shopFilter = shops.containsKey(_shopFilter) ? _shopFilter : null;

    _regroupIfNeeded(provider.boughts, items, shopFilter);
    final itemsById = {for (final i in items) i.id: i};
    final loadFailed = provider.boughts.isEmpty && provider.error != null;
    final symbol = l10n.currencySymbol;

    return RefreshIndicator(
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
                    hintText: l10n.searchItems,
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
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
                if (_shownCount > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    // Purchase amounts are owner-only
                    canManage
                        ? '${l10n.boughtPurchasesCount(_shownCount)} · $symbol ${_money.format(_shownTotal)}'
                        : l10n.boughtPurchasesCount(_shownCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_rows.isEmpty)
            SliverToBoxAdapter(child: _buildEmpty(l10n, loadFailed, _query.trim().isNotEmpty))
          else
            SliverPadding(
              // Bottom padding keeps the last card clear of the FAB
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverList.builder(
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  return switch (row) {
                    _DayRow() => _DayHeader(
                      title: _dayTitle(row.day, l10n),
                      trailing: canManage ? '$symbol ${_money.format(row.total)}' : null,
                    ),
                    _BoughtRow() => _BoughtCard(
                      bought: row.bought,
                      item: itemsById[row.bought.itemId],
                      shopName: row.bought.shop?.name ?? shopNames[row.bought.shopId],
                      selectedFractionId: _selectedFractionIds[row.bought.id],
                      onFractionChanged: (id) => setState(() => _selectedFractionIds[row.bought.id] = id),
                      deleting: _deleting.contains(row.bought.id),
                      onEdit: canManage ? () => _openForm(bought: row.bought) : null,
                      onDelete: canManage ? () => _delete(row.bought) : null,
                      showCosts: canManage,
                    ),
                  };
                },
              ),
            ),
        ],
      ),
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
                : l10n.noBoughtItems,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
          if (failed) TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(l10n.retry)),
        ],
      ),
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

class _BoughtCard extends StatelessWidget {
  /// Expiry within this many days is flagged.
  static const _expiringSoonDays = 30;
  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat('#,##0.00');
  static final _time = DateFormat.Hm();
  static final _date = DateFormat.yMMMd();

  final Bought bought;
  final Item? item;
  final String? shopName;
  final String? selectedFractionId;
  final ValueChanged<String> onFractionChanged;
  final bool deleting;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Owners see the cost per unit and the line total; salesmen only what came in.
  final bool showCosts;

  const _BoughtCard({
    required this.bought,
    required this.item,
    required this.shopName,
    required this.selectedFractionId,
    required this.onFractionChanged,
    required this.deleting,
    required this.onEdit,
    required this.onDelete,
    this.showCosts = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final fractions =
        (bought.item?.fractions?.isNotEmpty ?? false) ? bought.item!.fractions! : (item?.fractions ?? const <Fraction>[]);
    final boughtFraction =
        _findFraction(fractions, bought.fractionId) ??
        bought.fraction ??
        _placeholderFraction(name: fractions.isEmpty ? '' : fractions.first.name);
    // The unit the quantity is shown in: the one picked on this card, else the purchased one
    final shown = _findFraction(fractions, selectedFractionId) ?? boughtFraction;
    final factor = shown.ratio == 0 ? 1.0 : boughtFraction.ratio / shown.ratio;
    final qty = bought.quantity * factor;
    final unitCost = factor == 0 ? bought.fractionPurchasePrice : bought.fractionPurchasePrice / factor;
    final stockAfter = bought.available_items_count == null ? null : bought.available_items_count! * factor;

    final name = bought.item?.name ?? item?.name ?? l10n.unknownItem;
    final meta = [_time.format(bought.createdTime.toLocal()), shopName ?? l10n.unknownShop];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, onDelete == null ? 14 : 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.add_shopping_cart_rounded, size: 20, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          showCosts
                              ? '${_qty.format(qty)} ${shown.name} × ${l10n.currencySymbol} ${_money.format(unitCost)}'
                              : '${_qty.format(qty)} ${shown.name}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                        ),
                        Row(
                          children: [
                            Icon(Icons.storefront_outlined, size: 13, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                meta.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (showCosts)
                    Text(
                      '${l10n.currencySymbol} ${_money.format(_lineTotal(bought))}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    )
                  else
                    // Salesmen: how many came in, in the unit shown
                    Text(
                      '+${_qty.format(qty)}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.blue.shade700),
                    ),
                  if (onDelete != null)
                    deleting
                        ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                        : PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, size: 20, color: scheme.onSurfaceVariant),
                          padding: EdgeInsets.zero,
                          onSelected: (action) => action == 'edit' ? onEdit?.call() : onDelete!(),
                          itemBuilder:
                              (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_outlined),
                                      const SizedBox(width: 8),
                                      Text(l10n.edit),
                                    ],
                                  ),
                                ),
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
                        ),
                ],
              ),
              if (bought.expiryDate != null || stockAfter != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (bought.expiryDate != null) _expiryBadge(context, l10n, bought.expiryDate!.toLocal()),
                    if (stockAfter != null)
                      _Badge(
                        icon: Icons.inventory_2_outlined,
                        text: l10n.boughtStockAfter(_qty.format(stockAfter), shown.name),
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
              // Unit switcher (only when the item has more than one unit)
              if (fractions.length > 1) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in fractions)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f.name),
                            selected: f.id == shown.id,
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(fontSize: 12),
                            onSelected: (_) => onFractionChanged(f.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _expiryBadge(BuildContext context, AppLocalizations l10n, DateTime expiry) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(expiry.year, expiry.month, expiry.day).difference(today).inDays;
    if (days < 0) {
      return _Badge(icon: Icons.event_busy_rounded, text: l10n.boughtExpiredOn(_date.format(expiry)), color: scheme.error);
    }
    if (days <= _expiringSoonDays) {
      return _Badge(icon: Icons.event_rounded, text: l10n.boughtExpiresInDays(days), color: Colors.orange.shade800);
    }
    return _Badge(icon: Icons.event_rounded, text: l10n.boughtExpiresOn(_date.format(expiry)), color: scheme.onSurfaceVariant);
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Badge({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

enum _SaveOutcome { saved, savedPricesNotUpdated }

/// Add / edit form in a bottom sheet. Pops with a [_SaveOutcome] once the purchase is saved.
class _BoughtForm extends StatefulWidget {
  final Bought? bought;
  final String? initialItemId;
  final String? initialFractionId;
  final String? initialShopId;

  const _BoughtForm({this.bought, this.initialItemId, this.initialFractionId, this.initialShopId});

  @override
  State<_BoughtForm> createState() => _BoughtFormState();
}

class _BoughtFormState extends State<_BoughtForm> {
  /// One id per purchase form: if a save times out and is tapped again, the server sees the same
  /// id and doesn't record (and add to stock) the purchase twice.
  final String _clientId = const Uuid().v4();
  static final _date = DateFormat.yMMMd();
  static final _money = NumberFormat('#,##0.00');
  static final _decimal = FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*'));

  final _formKey = GlobalKey<FormState>();
  final _purchasePrice = TextEditingController();
  final _sellingPrice = TextEditingController();
  final _quantity = TextEditingController();
  String? _shopId;
  String? _itemId;
  String? _fractionId;
  DateTime? _expiryDate;
  bool _isSubmitting = false;
  String? _error;

  bool get _isEditing => widget.bought != null;

  @override
  void initState() {
    super.initState();
    final b = widget.bought;
    if (b != null) {
      _shopId = b.shopId;
      _itemId = b.itemId;
      _fractionId = b.fractionId;
      _purchasePrice.text = _plain(b.fractionPurchasePrice);
      _sellingPrice.text = _plain(b.fractionSoldPrice);
      _quantity.text = _plain(b.quantity);
      _expiryDate = b.expiryDate?.toLocal();
    } else {
      _itemId = widget.initialItemId;
      _fractionId = widget.initialFractionId;
      _shopId = widget.initialShopId;
      final active = context.read<ShopProvider>().shops.where((s) => s.isActive).toList();
      if (_shopId == null && active.length == 1) _shopId = active.first.id;
      _prefillPrices(onlyIfEmpty: true);
    }
  }

  @override
  void dispose() {
    _purchasePrice.dispose();
    _sellingPrice.dispose();
    _quantity.dispose();
    super.dispose();
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static double? _parse(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

  Item? get _item {
    for (final i in context.read<ItemProvider>().items) {
      if (i.id == _itemId) return i;
    }
    return null;
  }

  /// Fills the prices from the selected unit's catalog prices.
  void _prefillPrices({bool onlyIfEmpty = false}) {
    if (onlyIfEmpty && (_purchasePrice.text.isNotEmpty || _sellingPrice.text.isNotEmpty)) return;
    final fraction = _findFraction(_item?.fractions, _fractionId);
    if (fraction == null) return;
    _purchasePrice.text = _plain(fraction.purchasePrice);
    _sellingPrice.text = _plain(fraction.sellingPrice);
  }

  Future<void> _addNewItem() async {
    final result = await Navigator.of(
      context,
    ).push<String?>(MaterialPageRoute(builder: (_) => const ItemsScreen(autoOpenAdd: true)));
    if (result == null || !mounted) return;
    // Refresh items and select the newly created one
    await context.read<ItemProvider>().fetchItems();
    if (!mounted) return;
    setState(() {
      _itemId = result;
      _fractionId = null;
      _purchasePrice.clear();
      _sellingPrice.clear();
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _expiryDate ?? today;
    // Editing may show a purchase that has already expired, so past dates are allowed then
    var first = _isEditing ? DateTime(2000) : today;
    if (initial.isBefore(first)) first = DateTime(initial.year, initial.month, initial.day);
    final last = DateTime(now.year + 30, 12, 31);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: first,
      lastDate: last,
    );
    if (date != null) setState(() => _expiryDate = date);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    final boughtProvider = context.read<BoughtProvider>();
    final itemProvider = context.read<ItemProvider>();
    final fraction = _findFraction(_item?.fractions, _fractionId);
    if (fraction == null) {
      setState(() => _error = l10n.selectFractionToContinue);
      return;
    }
    final purchasePrice = _parse(_purchasePrice.text)!;
    final sellingPrice = _parse(_sellingPrice.text)!;
    final quantity = _parse(_quantity.text)!;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final ok =
          _isEditing
              ? await boughtProvider.updateBought(
                id: widget.bought!.id,
                fractionId: fraction.id,
                fractionPurchasePrice: purchasePrice,
                fractionSoldPrice: sellingPrice,
                quantity: quantity,
                expiryDate: _expiryDate,
                shopId: _shopId,
              )
              : await boughtProvider.createBought(
                clientId: _clientId,
                itemId: _itemId!,
                fractionId: fraction.id,
                fractionPurchasePrice: purchasePrice,
                fractionSoldPrice: sellingPrice,
                quantity: quantity,
                expiryDate: _expiryDate,
                shopId: _shopId,
              );
      if (!ok) {
        if (mounted) setState(() => _error = boughtProvider.error ?? l10n.error);
        return;
      }

      // Only once the purchase is saved: carry changed prices over to the item's catalog unit.
      // These catalogue prices are only defaults for the next purchase and for selling; profit is
      // worked out on the server from this purchase's own cost (FIFO stock lots).
      var outcome = _SaveOutcome.saved;
      if (fraction.purchasePrice != purchasePrice || fraction.sellingPrice != sellingPrice) {
        final updated = await itemProvider.updateFraction(
          fraction.id,
          fraction.name,
          fraction.ratio,
          sellingPrice,
          purchasePrice,
          isUnit: fraction.isUnit,
        );
        if (!updated) outcome = _SaveOutcome.savedPricesNotUpdated;
      }
      if (mounted) Navigator.of(context).pop(outcome);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shops = context.watch<ShopProvider>().shops.where((s) => s.isActive || s.id == _shopId).toList();
    final items = context.watch<ItemProvider>().items;
    final item = _item;
    final fractions = item?.fractions ?? const <Fraction>[];
    final enabled = !_isSubmitting;

    String? priceValidator(String? v) {
      if (v == null || v.trim().isEmpty) return l10n.required;
      final n = _parse(v);
      if (n == null) return l10n.invalidNumber;
      if (n < 0) return l10n.boughtPriceNotNegative;
      return null;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? l10n.editBoughtItem : l10n.addBoughtItem,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: shops.any((s) => s.id == _shopId) ? _shopId : null,
                isExpanded: true,
                decoration: authInputDecoration(context, label: l10n.selectShop, icon: Icons.storefront_outlined),
                borderRadius: BorderRadius.circular(14),
                items: [for (final s in shops) DropdownMenuItem(value: s.id, child: Text(s.name))],
                onChanged: enabled ? (v) => setState(() => _shopId = v) : null,
                validator: (v) => v == null || v.isEmpty ? l10n.required : null,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: items.any((i) => i.id == _itemId) ? _itemId : null,
                      isExpanded: true,
                      decoration: authInputDecoration(context, label: l10n.selectItem, icon: Icons.inventory_2_outlined),
                      borderRadius: BorderRadius.circular(14),
                      items: [
                        for (final i in items)
                          DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis)),
                      ],
                      // The backend can't move a purchase to another item, so the item is fixed when editing
                      onChanged:
                          enabled && !_isEditing
                              ? (v) => setState(() {
                                _itemId = v;
                                _fractionId = null;
                                _purchasePrice.clear();
                                _sellingPrice.clear();
                              })
                              : null,
                      validator: (v) => v == null || v.isEmpty ? l10n.required : null,
                    ),
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton.filledTonal(
                        onPressed: enabled ? _addNewItem : null,
                        icon: const Icon(Icons.add_rounded),
                        tooltip: l10n.addItem,
                      ),
                    ),
                  ],
                ],
              ),
              if (_itemId != null) ...[
                const SizedBox(height: 14),
                if (fractions.isEmpty)
                  Text(l10n.noFractionsAvailable, style: TextStyle(color: scheme.error))
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(_itemId),
                    value: _findFraction(fractions, _fractionId)?.id,
                    isExpanded: true,
                    hint: Text(l10n.chooseFraction),
                    decoration: authInputDecoration(context, label: l10n.selectFraction, icon: Icons.straighten_rounded),
                    borderRadius: BorderRadius.circular(14),
                    items: [
                      for (final f in fractions)
                        DropdownMenuItem(
                          value: f.id,
                          child: Text(
                            '${f.name}  ·  ${l10n.ratio} ${_plain(f.ratio)}  ·  ${l10n.currencySymbol} ${_money.format(f.sellingPrice)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    selectedItemBuilder: (_) => [for (final f in fractions) Text(f.name, overflow: TextOverflow.ellipsis)],
                    onChanged:
                        enabled
                            ? (v) => setState(() {
                              _fractionId = v;
                              _prefillPrices();
                            })
                            : null,
                    validator: (v) => v == null ? l10n.selectFractionToContinue : null,
                  ),
              ],
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _purchasePrice,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimal],
                      decoration: authInputDecoration(context, label: l10n.purchasePrice),
                      validator: priceValidator,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPrice,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimal],
                      decoration: authInputDecoration(context, label: l10n.soldPriceLabel),
                      validator: priceValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _quantity,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_decimal],
                decoration: authInputDecoration(context, label: l10n.quantityLabel, icon: Icons.numbers_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l10n.required;
                  final n = _parse(v);
                  if (n == null) return l10n.invalidNumber;
                  if (n <= 0) return l10n.boughtQuantityPositive;
                  return null;
                },
              ),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: enabled ? _pickExpiry : null,
                child: InputDecorator(
                  isEmpty: _expiryDate == null,
                  decoration: authInputDecoration(
                    context,
                    label: l10n.expiryDate,
                    icon: Icons.event_outlined,
                    // The backend keeps the old date when none is sent, so clearing is only offered when adding
                    suffix:
                        _expiryDate != null && !_isEditing && enabled
                            ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: l10n.clear,
                              onPressed: () => setState(() => _expiryDate = null),
                            )
                            : const Icon(Icons.calendar_today_outlined),
                  ).copyWith(hintText: l10n.selectExpiryDate),
                  child: Text(_expiryDate == null ? '' : _date.format(_expiryDate!)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: enabled ? () => Navigator.of(context).pop() : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: AuthSubmitButton(label: l10n.save, isLoading: _isSubmitting, onPressed: _submit),
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
