import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/category_provider.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/screens/owner/categories_screen.dart';
import 'package:inventory_frontend/screens/owner/item_detail_screen.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';
import 'package:inventory_frontend/widgets/fraction_management_dialog.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

enum _ItemAction { edit, units, delete }

/// The item catalog: search, filter by category, add/edit/delete items and their units.
///
/// Shown inside the owner dashboard (which provides the app bar, [showAppBar] false) and pushed
/// as its own page, e.g. from the bought items form with [autoOpenAdd], where it pops with the
/// new item's id once the item is saved.
class ItemsScreen extends StatefulWidget {
  final String? initialCategoryId;
  final bool autoOpenAdd;
  final bool showAppBar;
  const ItemsScreen({super.key, this.initialCategoryId, this.autoOpenAdd = false, this.showAppBar = true});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  static final _money = NumberFormat('#,##0.00');

  bool _isLoading = true;
  String _query = '';
  String? _categoryFilter; // null = all categories

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.initialCategoryId;
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
      if (widget.autoOpenAdd && mounted) _openItemForm();
    });
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    final itemProvider = context.read<ItemProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    // Keep showing the current list while refreshing; only show a spinner when there is nothing yet
    setState(() => _isLoading = itemProvider.items.isEmpty);
    await Future.wait([itemProvider.fetchItems(), categoryProvider.fetchCategories()]);
    if (mounted) setState(() => _isLoading = false);
  }

  /// Add (no [item]) or edit an item. A new item opens its detail page, or, when this page was
  /// opened to add an item ([ItemsScreen.autoOpenAdd]), returns its id to the caller.
  Future<void> _openItemForm([Item? item]) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final saved = await showDialog<Item>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ItemFormDialog(item: item, initialCategoryId: item == null ? _categoryFilter : null),
    );
    if (saved == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(item == null ? l10n.itemAdded : l10n.itemUpdated)));
    if (item != null) return;
    if (widget.autoOpenAdd) {
      navigator.pop(saved.id);
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => ItemDetailScreen(item: saved)));
  }

  Future<void> _deleteItem(Item item) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<ItemProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.deleteItem),
            content: Text(l10n.catalogDeleteItemConfirm(item.name)),
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
    // The provider removes the item itself, so there is no need to reload everything
    final ok = await provider.deleteItem(item.id);
    messenger.showSnackBar(SnackBar(content: Text(ok ? l10n.itemDeleted : (provider.error ?? l10n.error))));
  }

  void _manageUnits(Item item) {
    showDialog(context: context, builder: (_) => FractionManagementDialog(item: item));
  }

  void _openDetails(Item item) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemProvider = context.watch<ItemProvider>();
    final categories = context.watch<CategoryProvider>().categories;
    final isOwner = context.select<AuthProvider, bool>((a) => a.isOwner);

    final categoryNames = {for (final c in categories) c.id: c.name};
    final title =
        widget.initialCategoryId != null ? (categoryNames[widget.initialCategoryId] ?? l10n.items) : l10n.items;

    return Scaffold(
      appBar:
          widget.showAppBar
              ? AppBar(title: Text(title), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)])
              : null,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildList(l10n, itemProvider, categories.map((c) => MapEntry(c.id, c.name)), categoryNames, isOwner),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : () => _openItemForm(),
        tooltip: l10n.addItem,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(
    AppLocalizations l10n,
    ItemProvider provider,
    Iterable<MapEntry<String, String>> categoryChips,
    Map<String, String> categoryNames,
    bool isOwner,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final all = provider.items;
    // A filter for a category that no longer exists shows everything
    final filter =
        _categoryFilter != null && (categoryNames.containsKey(_categoryFilter) || _categoryFilter == widget.initialCategoryId)
            ? _categoryFilter
            : null;
    final q = _query.trim().toLowerCase();
    final visible =
        all.where((item) {
            if (filter != null && item.categoryId != filter) return false;
            return q.isEmpty || item.name.toLowerCase().contains(q);
          }).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: CustomScrollView(
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
                if (categoryChips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(l10n.posAll),
                            selected: filter == null,
                            onSelected: (_) => setState(() => _categoryFilter = null),
                          ),
                        ),
                        for (final entry in categoryChips)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: const Icon(Icons.folder_outlined, size: 16),
                              label: Text(entry.value),
                              selected: filter == entry.key,
                              onSelected: (_) => setState(() => _categoryFilter = entry.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.summaryItemsTitle(visible.length),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: _buildEmpty(l10n, failed: provider.error != null && all.isEmpty, filtered: q.isNotEmpty || filter != null),
            )
          else
            SliverPadding(
              // Bottom padding keeps the last card clear of the FAB
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder:
                    (context, i) =>
                        _buildCard(visible[i], l10n, categoryNames[visible[i].categoryId] ?? visible[i].category?.name, isOwner),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, {required bool failed, required bool filtered}) {
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
                : filtered
                ? l10n.summaryNoItemsMatch
                : l10n.noItemsFound,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
          if (failed) TextButton.icon(onPressed: _loadAll, icon: const Icon(Icons.refresh), label: Text(l10n.retry)),
        ],
      ),
    );
  }

  Widget _buildCard(Item item, AppLocalizations l10n, String? categoryName, bool isOwner) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fractions = item.fractions ?? const <Fraction>[];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.inventory_2_outlined, size: 20, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 13, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${categoryName ?? l10n.noCategory} · ${l10n.catalogUnitsCount(fractions.length)}',
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
                  PopupMenuButton<_ItemAction>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case _ItemAction.edit:
                          _openItemForm(item);
                        case _ItemAction.units:
                          _manageUnits(item);
                        case _ItemAction.delete:
                          _deleteItem(item);
                      }
                    },
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            value: _ItemAction.edit,
                            child: ListTile(
                              leading: const Icon(Icons.edit_outlined),
                              title: Text(l10n.editItem),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: _ItemAction.units,
                            child: ListTile(
                              leading: const Icon(Icons.straighten_rounded),
                              title: Text(l10n.manageUnits),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: _ItemAction.delete,
                            child: ListTile(
                              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                              title: Text(l10n.deleteItem, style: TextStyle(color: scheme.error)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              if (fractions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final f in fractions) _UnitPill(fraction: f, showCost: isOwner, money: _money)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One unit of an item with its selling price (and cost for owners).
class _UnitPill extends StatelessWidget {
  final Fraction fraction;
  final bool showCost;
  final NumberFormat money;

  const _UnitPill({required this.fraction, required this.showCost, required this.money});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = l10n.currencySymbol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: fraction.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(
                  text: '  $symbol ${money.format(fraction.sellingPrice)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                ),
              ],
            ),
            style: theme.textTheme.labelMedium,
          ),
          if (showCost)
            Text(
              '${l10n.catalogCost} $symbol ${money.format(fraction.purchasePrice)}',
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Add or edit an item. A new item also gets its first (base) unit. Pops with the saved item.
class _ItemFormDialog extends StatefulWidget {
  final Item? item;
  final String? initialCategoryId;

  const _ItemFormDialog({this.item, this.initialCategoryId});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  static final _decimal = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.item?.name ?? '');
  final _unitNameController = TextEditingController();
  final _ratioController = TextEditingController(text: '1');
  final _sellingPriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  String? _categoryId;
  bool _isSubmitting = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.item?.categoryId ?? widget.initialCategoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitNameController.dispose();
    _ratioController.dispose();
    _sellingPriceController.dispose();
    _purchasePriceController.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    // The categories page opens its add form and pops with the new category's id
    final id = await Navigator.of(
      context,
    ).push<String?>(MaterialPageRoute(builder: (_) => const CategoriesScreen(), settings: const RouteSettings(arguments: true)));
    if (id != null && mounted) setState(() => _categoryId = id);
  }

  static Item? _findById(List<Item> items, String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<ItemProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = _nameController.text.trim();

    setState(() => _isSubmitting = true);
    Item? saved;
    if (_isNew) {
      if (await provider.createItem(name, _categoryId!, [])) {
        // The provider appends the created item; take the newest one with this name
        final created = provider.items.lastWhere((i) => i.name.trim() == name, orElse: () => provider.items.last);
        final unitOk = await provider.createFraction(
          created.id,
          _unitNameController.text.trim(),
          double.parse(_ratioController.text),
          double.parse(_sellingPriceController.text),
          double.parse(_purchasePriceController.text),
          isUnit: true,
        );
        // The item exists even if its unit failed; units can still be added from its page
        if (!unitOk) messenger.showSnackBar(SnackBar(content: Text(provider.error ?? l10n.error)));
        saved = _findById(provider.items, created.id) ?? created;
      }
    } else {
      if (await provider.updateItem(widget.item!.id, name, _categoryId!)) {
        saved = _findById(provider.items, widget.item!.id) ?? widget.item;
      }
    }

    if (saved != null) {
      navigator.pop(saved);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(provider.error ?? l10n.error)));
    if (mounted) setState(() => _isSubmitting = false);
  }

  String? _required(String? v, AppLocalizations l10n) => (v == null || v.trim().isEmpty) ? l10n.required : null;

  String? _validRatio(String? v, AppLocalizations l10n) {
    if (v == null || v.trim().isEmpty) return l10n.pleaseEnterRatio;
    final n = double.tryParse(v);
    if (n == null) return l10n.pleaseEnterValidNumber;
    if (n <= 0) return l10n.catalogRatioMustBePositive;
    return null;
  }

  String? _validPrice(String? v, AppLocalizations l10n) {
    if (v == null || v.trim().isEmpty) return l10n.pleaseEnterPrice;
    final n = double.tryParse(v);
    if (n == null) return l10n.pleaseEnterValidNumber;
    if (n < 0) return l10n.catalogPriceNotNegative;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final categories = context.watch<CategoryProvider>().categories;
    // The dropdown asserts its value is one of the items
    final selected = categories.any((c) => c.id == _categoryId) ? _categoryId : null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(_isNew ? l10n.addItem : l10n.editItem),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: authInputDecoration(context, label: l10n.name, icon: Icons.inventory_2_outlined),
                  validator: (v) => _required(v, l10n),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selected,
                        isExpanded: true,
                        decoration: authInputDecoration(context, label: l10n.category, icon: Icons.folder_outlined),
                        items: [
                          for (final c in categories)
                            DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: _isSubmitting ? null : (v) => setState(() => _categoryId = v),
                        validator: (v) => (v == null || v.isEmpty) ? l10n.required : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton.filledTonal(
                        onPressed: _isSubmitting ? null : _addCategory,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        tooltip: l10n.catalogAddCategory,
                      ),
                    ),
                  ],
                ),
                if (_isNew) ...[
                  const SizedBox(height: 20),
                  AuthSectionLabel(text: l10n.catalogFirstUnitTitle, icon: Icons.straighten_rounded),
                  const SizedBox(height: 6),
                  Text(
                    l10n.addPrimarySellingUnitDescription,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _unitNameController,
                          enabled: !_isSubmitting,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: authInputDecoration(
                            context,
                            label: l10n.unitName,
                          ).copyWith(hintText: l10n.catalogUnitNameHint),
                          validator: (v) => (v == null || v.trim().isEmpty) ? l10n.pleaseEnterName : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _ratioController,
                          enabled: !_isSubmitting,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_decimal],
                          decoration: authInputDecoration(context, label: l10n.ratio),
                          validator: (v) => _validRatio(v, l10n),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _sellingPriceController,
                          enabled: !_isSubmitting,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_decimal],
                          decoration: authInputDecoration(context, label: l10n.soldPriceLabel),
                          validator: (v) => _validPrice(v, l10n),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePriceController,
                          enabled: !_isSubmitting,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_decimal],
                          decoration: authInputDecoration(context, label: l10n.purchasePrice),
                          validator: (v) => _validPrice(v, l10n),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child:
              _isSubmitting
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                  : Text(l10n.save),
        ),
      ],
    );
  }
}
