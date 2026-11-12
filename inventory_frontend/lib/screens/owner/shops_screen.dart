import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/shop.dart';
import 'package:inventory_frontend/providers/shop_provider.dart';
import 'package:inventory_frontend/screens/owner/shop_detail_screen.dart';
import 'package:inventory_frontend/screens/owner/users_screen.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

/// The owner's shops: search, open, add, edit and delete.
///
/// Shown inside the owner dashboard (pass [showAppBar] false there, the dashboard has its own).
class ShopsScreen extends StatefulWidget {
  final bool showAppBar;

  const ShopsScreen({super.key, this.showAppBar = true});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadShops());
  }

  Future<void> _loadShops() async {
    if (!mounted) return;
    final shopProvider = context.read<ShopProvider>();
    // Keep the current list visible while refreshing; only show a spinner when there is nothing yet
    setState(() => _isLoading = shopProvider.shops.isEmpty);
    await shopProvider.getShops();
    if (mounted) setState(() => _isLoading = false);
  }

  void _openShop(Shop shop) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopDetailScreen(shop: shop)));
  }

  Future<void> _openForm([Shop? shop]) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _ShopForm(shop: shop),
    );
    if (saved == true && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(shop == null ? l10n.shopCreatedSuccess : l10n.peopleShopUpdated)));
    }
  }

  Future<void> _deleteShop(Shop shop) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final shopProvider = context.read<ShopProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(l10n.deleteShopTitle),
          content: Text(l10n.deleteShopContent(shop.name)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final success = await shopProvider.deleteShop(shop.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(success ? l10n.shopDeletedSuccess : shopProvider.error ?? l10n.shopDeletedFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar:
          widget.showAppBar
              ? AppBar(
                title: Text(l10n.shops),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: l10n.refresh,
                    onPressed: _isLoading ? null : _loadShops,
                  ),
                ],
              )
              : null,
      body:
          _isLoading
              ? const Column(children: [OfflineBanner(), Expanded(child: Center(child: CircularProgressIndicator()))])
              : _buildList(context, l10n),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: l10n.createNewShop,
        child: const Icon(Icons.add_business_rounded),
      ),
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final shopProvider = context.watch<ShopProvider>();
    final all = shopProvider.shops;
    final q = _query.trim().toLowerCase();
    final visible =
        q.isEmpty
            ? all
            : all.where((s) => s.name.toLowerCase().contains(q) || s.address.toLowerCase().contains(q)).toList();
    final failed = shopProvider.error != null && all.isEmpty;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadShops,
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
                          hintText: l10n.peopleSearchShops,
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.peopleShopsCount(visible.length),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: PeopleEmptyState(
                      icon: failed ? Icons.cloud_off_rounded : Icons.storefront_outlined,
                      text:
                          failed
                              ? l10n.loadFailedNoData
                              : all.isNotEmpty
                              ? l10n.peopleNoShopsMatch
                              : l10n.noShopsFound,
                      hint: !failed && all.isEmpty ? l10n.createFirstShopToGetStarted : null,
                      onRetry: failed ? _loadShops : null,
                    ),
                  )
                else
                  SliverPadding(
                    // Leave room under the last card for the add button
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final shop = visible[i];
                        return _ShopCard(
                          shop: shop,
                          onOpen: () => _openShop(shop),
                          onEdit: () => _openForm(shop),
                          onDelete: () => _deleteShop(shop),
                        );
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
}

class _ShopCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ShopCard({required this.shop, required this.onOpen, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final salespeople = shop.salespeople ?? const [];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: shop.isActive ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: shop.isActive ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
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
                            shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!shop.isActive) ...[
                          const SizedBox(width: 8),
                          PeopleBadge(text: l10n.inactive, color: scheme.error),
                        ],
                      ],
                    ),
                    if (shop.address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: PeopleInfo(icon: Icons.place_outlined, text: shop.address),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.people_alt_outlined, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            l10n.peopleSalespeopleCount(salespeople.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'view':
                      onOpen();
                    case 'edit':
                      onEdit();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder:
                    (_) => [
                      PopupMenuItem(
                        value: 'view',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.visibility_outlined),
                          title: Text(l10n.viewDetails),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(l10n.edit),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                          title: Text(l10n.delete, style: TextStyle(color: scheme.error)),
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

/// Create / edit form for a shop, shown in a bottom sheet. Pops `true` once saved.
class _ShopForm extends StatefulWidget {
  final Shop? shop;

  const _ShopForm({this.shop});

  @override
  State<_ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends State<_ShopForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.shop?.name);
  late final _addressController = TextEditingController(text: widget.shop?.address);
  bool _isSubmitting = false;
  String? _error;

  bool get _isEdit => widget.shop != null;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final shopProvider = context.read<ShopProvider>();
    final navigator = Navigator.of(context);
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final success =
        _isEdit
            ? await shopProvider.updateShop(widget.shop!.id, name, address)
            : await shopProvider.createShop(name, address);

    if (!mounted) return;
    if (success) {
      navigator.pop(true);
    } else {
      // Keep the sheet open so nothing typed is lost
      setState(() {
        _isSubmitting = false;
        _error = shopProvider.error ?? (_isEdit ? l10n.peopleShopUpdateFailed : l10n.shopCreatedFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                _isEdit ? l10n.peopleEditShop : l10n.createNewShop,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                enabled: !_isSubmitting,
                autofocus: !_isEdit,
                decoration: authInputDecoration(context, label: l10n.shopNameLabel, icon: Icons.storefront_outlined),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? l10n.pleaseEnterShopName : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                enabled: !_isSubmitting,
                decoration: authInputDecoration(context, label: l10n.shopAddressLabel, icon: Icons.place_outlined),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => (v == null || v.trim().isEmpty) ? l10n.pleaseEnterShopAddress : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child:
                    _isSubmitting
                        ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
                        )
                        : Text(l10n.save, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
