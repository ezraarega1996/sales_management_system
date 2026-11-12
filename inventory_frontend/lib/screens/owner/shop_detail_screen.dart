import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/shop.dart';
import 'package:inventory_frontend/models/user.dart';
import 'package:inventory_frontend/providers/shop_provider.dart';
import 'package:inventory_frontend/screens/available_items_screen.dart';
import 'package:inventory_frontend/screens/owner/users_screen.dart';

/// One shop: a header with its details, its salespeople (assign / remove) and its stock.
class ShopDetailScreen extends StatefulWidget {
  final Shop shop;

  const ShopDetailScreen({super.key, required this.shop});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ShopProvider>().getAvailableSalespeople();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final shopProvider = context.read<ShopProvider>();
    await Future.wait([shopProvider.getShops(), shopProvider.getAvailableSalespeople()]);
  }

  /// The latest copy of this shop from the provider (it is refreshed after assign / remove).
  Shop _currentShop(List<Shop> shops) {
    for (final s in shops) {
      if (s.id == widget.shop.id) return s;
    }
    return widget.shop;
  }

  Future<void> _assignSalesperson(User salesperson) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final shopProvider = context.read<ShopProvider>();
    setState(() => _busy = true);
    final success = await shopProvider.assignSalespersonToShop(widget.shop.id, salesperson.id);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? l10n.salespersonAssigned(salesperson.name, widget.shop.name)
              : shopProvider.error ?? l10n.failedToAssignSalesperson,
        ),
      ),
    );
  }

  Future<void> _removeSalesperson(User salesperson) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final shopProvider = context.read<ShopProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(l10n.removeSalespersonTitle),
          content: Text(l10n.removeSalespersonContent(salesperson.name, widget.shop.name)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final success = await shopProvider.removeSalespersonFromShop(widget.shop.id, salesperson.id);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? l10n.salespersonRemoved(salesperson.name, widget.shop.name)
              : shopProvider.error ?? l10n.failedToRemoveSalesperson,
        ),
      ),
    );
  }

  Future<void> _showAssignSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final available = context.read<ShopProvider>().availableSalespeople;

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noAvailableSalespeople)));
      return;
    }

    final picked = await showModalBottomSheet<User>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  l10n.assignSalespersonTitle,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: available.length,
                  itemBuilder: (context, i) {
                    final person = available[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: PersonAvatar(name: person.name, radius: 20),
                      title: Text(person.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [if (person.username.isNotEmpty) '@${person.username}', if (person.phone.isNotEmpty) person.phone]
                            .join(' · '),
                      ),
                      trailing: Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary),
                      onTap: () => Navigator.of(context).pop(person),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) await _assignSalesperson(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final shop = _currentShop(context.watch<ShopProvider>().shops);

    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.refresh,
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: _ShopHeader(shop: shop)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(28)),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(24)),
                labelColor: scheme.onSecondaryContainer,
                unselectedLabelColor: scheme.onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                splashBorderRadius: BorderRadius.circular(24),
                tabs: [
                  Tab(
                    height: 40,
                    child: _TabLabel(icon: Icons.people_alt_outlined, text: l10n.salespeopleTab),
                  ),
                  Tab(
                    height: 40,
                    child: _TabLabel(icon: Icons.inventory_2_outlined, text: l10n.availableItemsTab),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildSalespeopleTab(context, shop, l10n), AvailableItemsScreen(shopId: widget.shop.id)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalespeopleTab(BuildContext context, Shop shop, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final salespeople = shop.salespeople ?? const <User>[];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.peopleSalespeopleCount(salespeople.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _showAssignSheet,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(l10n.assignLabel),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
          ),
          if (salespeople.isEmpty)
            SliverToBoxAdapter(
              child: PeopleEmptyState(
                icon: Icons.people_outline_rounded,
                text: l10n.noSalespeopleAssigned,
                hint: l10n.assignSalespeopleToShop,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList.separated(
                itemCount: salespeople.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final person = salespeople[i];
                  return Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                      child: Row(
                        children: [
                          PersonAvatar(name: person.name, dimmed: !person.isActive),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (person.username.isNotEmpty)
                                  Text(
                                    '@${person.username}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                if (person.phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  PeopleInfo(icon: Icons.phone_outlined, text: person.phone),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.remove,
                            icon: Icon(Icons.person_remove_outlined, color: scheme.error),
                            onPressed: _busy ? null : () => _removeSalesperson(person),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Gradient card with the shop's name, address and status, styled like the dashboard header.
class _ShopHeader extends StatelessWidget {
  final Shop shop;

  const _ShopHeader({required this.shop});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onHeader = scheme.onPrimary;
    final count = shop.salespeople?.length ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.55)!],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: onHeader.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.storefront_rounded, color: onHeader, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: onHeader, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                if (shop.address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, size: 14, color: onHeader.withValues(alpha: 0.85)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            shop.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: onHeader.withValues(alpha: 0.85), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _HeaderChip(icon: Icons.people_alt_outlined, text: l10n.peopleSalespeopleCount(count), color: onHeader),
                    _HeaderChip(
                      icon: shop.isActive ? Icons.check_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                      text: shop.isActive ? l10n.active : l10n.inactive,
                      color: onHeader,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _HeaderChip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
