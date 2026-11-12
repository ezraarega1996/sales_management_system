import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/category.dart';
import 'package:inventory_frontend/providers/category_provider.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/screens/owner/items_screen.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

enum _CategoryAction { edit, delete }

/// Item categories: search, add, rename, delete; tapping one opens its items.
///
/// Shown inside the owner dashboard ([showAppBar] false) and pushed as its own page. When pushed
/// with route arguments `true` (from the item form), it opens the add form right away and pops
/// with the new category's id once it is saved.
class CategoriesScreen extends StatefulWidget {
  final bool showAppBar;
  const CategoriesScreen({super.key, this.showAppBar = true});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _isLoading = true;
  bool _returnNewId = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _returnNewId = ModalRoute.of(context)?.settings.arguments == true;
      _loadCategories();
      if (_returnNewId) _openForm();
    });
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    final provider = context.read<CategoryProvider>();
    // Keep showing the current list while refreshing; only show a spinner when there is nothing yet
    setState(() => _isLoading = provider.categories.isEmpty);
    await provider.fetchCategories();
    if (mounted) setState(() => _isLoading = false);
  }

  /// Add (no [category]) or rename a category.
  Future<void> _openForm([Category? category]) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final savedId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryFormDialog(category: category),
    );
    if (savedId == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.success)));
    // Opened from the item form to add a category: hand the new id back
    if (category == null && _returnNewId) navigator.pop(savedId);
  }

  Future<void> _deleteCategory(Category category) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CategoryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.catalogDeleteCategory),
            content: Text(l10n.catalogDeleteCategoryConfirm(category.name)),
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
    // The provider removes the category itself, so there is no need to reload
    final ok = await provider.deleteCategory(category.id);
    messenger.showSnackBar(SnackBar(content: Text(ok ? l10n.success : (provider.error ?? l10n.error))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar:
          widget.showAppBar
              ? AppBar(
                title: Text(l10n.categories),
                actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadCategories)],
              )
              : null,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildList(l10n)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : () => _openForm(),
        tooltip: l10n.catalogAddCategory,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<CategoryProvider>();
    final all = provider.categories;

    // Item counts come from items already loaded elsewhere; no extra request is made for them
    final items = context.watch<ItemProvider>().items;
    final Map<String, int>? counts;
    if (items.isEmpty) {
      counts = null;
    } else {
      counts = <String, int>{};
      for (final item in items) {
        counts[item.categoryId] = (counts[item.categoryId] ?? 0) + 1;
      }
    }

    final q = _query.trim().toLowerCase();
    final visible =
        all.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return RefreshIndicator(
      onRefresh: _loadCategories,
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
                    hintText: l10n.catalogSearchCategories,
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.catalogCategoriesTitle(visible.length),
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
            SliverToBoxAdapter(child: _buildEmpty(l10n, failed: provider.error != null && all.isEmpty, searching: q.isNotEmpty))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _buildCard(visible[i], l10n, counts?[visible[i].id] ?? (counts == null ? null : 0)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, {required bool failed, required bool searching}) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 80, left: 32, right: 32),
      child: Column(
        children: [
          Icon(failed ? Icons.cloud_off_rounded : Icons.folder_off_outlined, size: 44, color: color),
          const SizedBox(height: 12),
          Text(
            failed
                ? l10n.loadFailedNoData
                : searching
                ? l10n.catalogNoCategoriesMatch
                : l10n.catalogNoCategories,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
          if (failed)
            TextButton.icon(onPressed: _loadCategories, icon: const Icon(Icons.refresh), label: Text(l10n.retry)),
        ],
      ),
    );
  }

  Widget _buildCard(Category category, AppLocalizations l10n, int? itemCount) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => ItemsScreen(initialCategoryId: category.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.folder_outlined, size: 20, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (itemCount != null)
                      Text(
                        l10n.catalogItemsCount(itemCount),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<_CategoryAction>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) {
                  switch (action) {
                    case _CategoryAction.edit:
                      _openForm(category);
                    case _CategoryAction.delete:
                      _deleteCategory(category);
                  }
                },
                itemBuilder:
                    (_) => [
                      PopupMenuItem(
                        value: _CategoryAction.edit,
                        child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(l10n.catalogEditCategory),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: _CategoryAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                          title: Text(l10n.catalogDeleteCategory, style: TextStyle(color: scheme.error)),
                          contentPadding: EdgeInsets.zero,
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

/// Add or rename a category. Pops with the saved category's id.
class _CategoryFormDialog extends StatefulWidget {
  final Category? category;
  const _CategoryFormDialog({this.category});

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.category?.name ?? '');
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CategoryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = _nameController.text.trim();

    setState(() => _isSubmitting = true);
    String? savedId;
    if (widget.category == null) {
      if (await provider.createCategory(name)) {
        // The provider appends the created category; take the newest one with this name
        final all = provider.categories;
        savedId = all.lastWhere((c) => c.name.trim() == name, orElse: () => all.last).id;
      }
    } else if (await provider.updateCategory(widget.category!.id, name)) {
      savedId = widget.category!.id;
    }

    if (savedId != null) {
      navigator.pop(savedId);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(provider.error ?? l10n.error)));
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.category == null ? l10n.catalogAddCategory : l10n.catalogEditCategory),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _nameController,
            autofocus: true,
            enabled: !_isSubmitting,
            textCapitalization: TextCapitalization.sentences,
            decoration: authInputDecoration(context, label: l10n.name, icon: Icons.folder_outlined),
            validator: (v) => (v == null || v.trim().isEmpty) ? l10n.required : null,
            onFieldSubmitted: (_) => _submit(),
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
