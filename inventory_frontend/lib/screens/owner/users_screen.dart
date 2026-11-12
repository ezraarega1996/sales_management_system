import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/shop.dart';
import 'package:inventory_frontend/models/user.dart';
import 'package:inventory_frontend/providers/shop_provider.dart';
import 'package:inventory_frontend/providers/user_provider.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

/// The owner's salespeople: search, filter by shop, add, edit and delete.
///
/// Shown inside the owner dashboard (pass [showAppBar] false there, the dashboard has its own).
class UsersScreen extends StatefulWidget {
  final bool showAppBar;

  const UsersScreen({super.key, this.showAppBar = true});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  /// Shop filter value for "no shop assigned".
  static const _noShop = '\u0000none';

  bool _isLoading = true;
  String _query = '';
  String? _shopFilter; // null = all

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    final shopProvider = context.read<ShopProvider>();
    // Keep the current list visible while refreshing; only show a spinner when there is nothing yet
    setState(() => _isLoading = userProvider.users.isEmpty);
    await Future.wait([
      userProvider.fetchUsers(),
      // Shops are only needed for names and the shop picker; reuse them when already loaded
      if (shopProvider.shops.isEmpty) shopProvider.getShops(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refresh() async {
    final userProvider = context.read<UserProvider>();
    final shopProvider = context.read<ShopProvider>();
    await Future.wait([userProvider.fetchUsers(), shopProvider.getShops()]);
  }

  Future<void> _openForm([User? user]) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _SalespersonForm(user: user),
    );
    if (saved == true && mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(user == null ? l10n.peopleSalespersonAdded : l10n.peopleSalespersonUpdated)),
      );
    }
  }

  Future<void> _deleteUser(User user) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final userProvider = context.read<UserProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(l10n.peopleDeleteSalespersonTitle),
          content: Text(l10n.peopleDeleteSalespersonContent(user.name)),
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

    // The provider removes the user from its list, so no reload is needed
    final success = await userProvider.deleteUser(user.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(success ? l10n.peopleSalespersonDeleted : userProvider.error ?? l10n.error)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final Widget body;
    if (_isLoading) {
      body = const Column(children: [OfflineBanner(), Expanded(child: Center(child: CircularProgressIndicator()))]);
    } else {
      body = _buildList(context, l10n, scheme);
    }

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: Text(l10n.salesPerson)) : null,
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : () => _openForm(),
        tooltip: l10n.peopleAddSalesperson,
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n, ColorScheme scheme) {
    final userProvider = context.watch<UserProvider>();
    final shops = context.watch<ShopProvider>().shops;
    final shopNames = {for (final s in shops) s.id: s.name};

    final all = userProvider.users.where((u) => u.role == 'salesman').toList();
    final shopFilter =
        _shopFilter == null || _shopFilter == _noShop || shopNames.containsKey(_shopFilter) ? _shopFilter : null;
    final q = _query.trim().toLowerCase();
    final visible =
        all.where((u) {
          if (shopFilter == _noShop && u.shopId != null) return false;
          if (shopFilter != null && shopFilter != _noShop && u.shopId != shopFilter) return false;
          if (q.isEmpty) return true;
          return u.name.toLowerCase().contains(q) || u.username.toLowerCase().contains(q) || u.phone.contains(q);
        }).toList();
    final failed = userProvider.error != null && all.isEmpty;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
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
                          hintText: l10n.peopleSearchSalespeople,
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (shops.isNotEmpty && all.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _chip(l10n.stockAllShops, shopFilter == null, null),
                              for (final s in shops)
                                _chip(s.name, shopFilter == s.id, s.id, icon: Icons.storefront_outlined),
                              _chip(l10n.noShopAssigned, shopFilter == _noShop, _noShop),
                            ],
                          ),
                        ),
                      ],
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.peopleSalespeopleCount(visible.length),
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
                      icon: failed ? Icons.cloud_off_rounded : Icons.people_outline_rounded,
                      text:
                          failed
                              ? l10n.loadFailedNoData
                              : all.isNotEmpty
                              ? l10n.peopleNoSalespeopleMatch
                              : l10n.noSalespeopleFound,
                      hint: !failed && all.isEmpty ? l10n.peopleAddFirstSalesperson : null,
                      onRetry: failed ? _load : null,
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
                        final user = visible[i];
                        return _SalespersonCard(
                          user: user,
                          shopName: user.shopId == null ? null : shopNames[user.shopId] ?? user.shop?.name,
                          onEdit: () => _openForm(user),
                          onDelete: () => _deleteUser(user),
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

  Widget _chip(String label, bool selected, String? value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon != null ? Icon(icon, size: 16) : null,
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _shopFilter = value),
      ),
    );
  }
}

class _SalespersonCard extends StatelessWidget {
  final User user;
  final String? shopName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SalespersonCard({required this.user, required this.shopName, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonAvatar(name: user.name, dimmed: !user.isActive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PeopleBadge(
                          text: user.isActive ? l10n.active : l10n.inactive,
                          color: user.isActive ? Colors.green.shade700 : scheme.error,
                        ),
                      ],
                    ),
                    if (user.username.isNotEmpty)
                      Text('@${user.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (user.phone.isNotEmpty) PeopleInfo(icon: Icons.phone_outlined, text: user.phone),
                        if (user.location.isNotEmpty) PeopleInfo(icon: Icons.place_outlined, text: user.location),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ShopTag(name: shopName, fallback: l10n.noShopAssigned),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder:
                    (_) => [
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

class _ShopTag extends StatelessWidget {
  final String? name;
  final String fallback;

  const _ShopTag({required this.name, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final assigned = name != null;
    final fg = assigned ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: assigned ? scheme.secondaryContainer : Colors.transparent,
        border: assigned ? null : Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(assigned ? Icons.storefront_rounded : Icons.store_mall_directory_outlined, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name ?? fallback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Add / edit form for a salesperson, shown in a bottom sheet. Pops `true` once saved.
class _SalespersonForm extends StatefulWidget {
  final User? user;

  const _SalespersonForm({this.user});

  @override
  State<_SalespersonForm> createState() => _SalespersonFormState();
}

class _SalespersonFormState extends State<_SalespersonForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.user?.name);
  late final _phoneController = TextEditingController(text: widget.user?.phone);
  late final _locationController = TextEditingController(text: widget.user?.location);
  late final _usernameController = TextEditingController(text: widget.user?.username);
  final _passwordController = TextEditingController();
  late String? _selectedShopId = widget.user?.shopId;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final userProvider = context.read<UserProvider>();
    final navigator = Navigator.of(context);
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final userData = <String, dynamic>{
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'location': _locationController.text.trim(),
      'role': 'salesman',
    };
    if (_selectedShopId != null) userData['shopId'] = _selectedShopId!;

    final bool success;
    if (_isEdit) {
      if (_passwordController.text.isNotEmpty) userData['password'] = _passwordController.text;
      success = await userProvider.updateUser(widget.user!.id, userData);
    } else {
      userData['username'] = _usernameController.text.trim();
      userData['password'] = _passwordController.text;
      success = await userProvider.createUser(userData);
    }

    if (!mounted) return;
    if (success) {
      navigator.pop(true);
    } else {
      // Keep the sheet open so nothing typed is lost
      setState(() {
        _isSubmitting = false;
        _error = userProvider.error ?? AppLocalizations.of(context)!.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shops = context.watch<ShopProvider>().shops;
    // Keep the dropdown valid if the user's shop isn't in the loaded list
    final shopId = _selectedShopId != null && shops.any((s) => s.id == _selectedShopId) ? _selectedShopId : null;
    String? required(String? v) => (v == null || v.trim().isEmpty) ? l10n.required : null;

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
                _isEdit ? l10n.peopleEditSalesperson : l10n.peopleAddSalesperson,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                enabled: !_isSubmitting,
                decoration: authInputDecoration(context, label: l10n.name, icon: Icons.person_outline_rounded),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: !_isSubmitting,
                decoration: authInputDecoration(context, label: l10n.phone, icon: Icons.phone_outlined),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                enabled: !_isSubmitting,
                decoration: authInputDecoration(context, label: l10n.location, icon: Icons.place_outlined),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                // The username can't be changed after the account is created
                enabled: !_isEdit && !_isSubmitting,
                decoration: authInputDecoration(context, label: l10n.username, icon: Icons.alternate_email_rounded),
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                enabled: !_isSubmitting,
                obscureText: _obscurePassword,
                decoration: authInputDecoration(
                  context,
                  label: l10n.password,
                  icon: Icons.lock_outline_rounded,
                  helper: _isEdit ? l10n.peoplePasswordKeepHint : null,
                  suffix: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                validator: (v) => !_isEdit && (v == null || v.isEmpty) ? l10n.required : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: shopId,
                isExpanded: true,
                decoration: authInputDecoration(context, label: l10n.peopleShopOptional, icon: Icons.storefront_outlined),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(l10n.noShopAssigned)),
                  for (final Shop s in shops)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _isSubmitting ? null : (v) => setState(() => _selectedShopId = v),
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

// ---------------------------------------------------------------------------
// Small pieces shared with the shop screens
// ---------------------------------------------------------------------------

/// Up to two initials from a name, like the drawer header.
String personInitials(String name) {
  final initials =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
  return initials.isEmpty ? '?' : initials;
}

/// Round avatar with a person's initials.
class PersonAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool dimmed;

  const PersonAvatar({super.key, required this.name, this.radius = 22, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: dimmed ? scheme.surfaceContainerHighest : scheme.primaryContainer,
      child: Text(
        personInitials(name),
        style: TextStyle(
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w800,
          color: dimmed ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Small tinted label, e.g. Active / Inactive.
class PeopleBadge extends StatelessWidget {
  final String text;
  final Color color;

  const PeopleBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Icon + muted text, e.g. a phone number.
class PeopleInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const PeopleInfo({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Empty / error state: a 44px icon, a message, an optional hint and a Retry button.
class PeopleEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  final VoidCallback? onRetry;

  const PeopleEmptyState({super.key, required this.icon, required this.text, this.hint, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 80, left: 32, right: 32, bottom: 24),
      child: Column(
        children: [
          Icon(icon, size: 44, color: color),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ],
          if (onRetry != null)
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l10n.retry)),
        ],
      ),
    );
  }
}
