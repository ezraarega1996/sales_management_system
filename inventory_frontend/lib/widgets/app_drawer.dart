import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/business_provider.dart';

/// One tappable destination in the drawer. [index] is the dashboard's screen index.
class AppDrawerItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;

  const AppDrawerItem({required this.icon, IconData? selectedIcon, required this.label, required this.index})
    : selectedIcon = selectedIcon ?? icon;
}

/// A titled group of destinations.
class AppDrawerSection {
  final String? title;
  final List<AppDrawerItem> items;

  const AppDrawerSection({this.title, required this.items});
}

/// Side menu shared by the owner and salesman dashboards: a gradient profile header
/// (matching the dashboard header), grouped destinations with a pill highlight for
/// the open screen, and account actions pinned to the bottom.
class AppDrawer extends StatelessWidget {
  final List<AppDrawerSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final VoidCallback? onChangePassword;

  const AppDrawer({
    super.key,
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Drawer(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: Column(
        children: [
          const _DrawerHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              children: [
                for (final section in sections) ...[
                  if (section.title != null) _SectionLabel(section.title!),
                  for (final item in section.items)
                    _DrawerTile(
                      icon: item.index == selectedIndex ? item.selectedIcon : item.icon,
                      label: item.label,
                      selected: item.index == selectedIndex,
                      onTap: () {
                        Navigator.pop(context);
                        onSelect(item.index);
                      },
                    ),
                ],
              ],
            ),
          ),
          Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
          // Keep the account actions above the phone's navigation bar so they can be tapped
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset + 8),
            child: Column(
              children: [
                if (onChangePassword != null)
                  _DrawerTile(
                    icon: Icons.lock_outline_rounded,
                    label: l10n.changePasswordMenu,
                    onTap: () {
                      Navigator.pop(context);
                      onChangePassword!();
                    },
                  ),
                _DrawerTile(
                  icon: Icons.logout_rounded,
                  label: l10n.logout,
                  color: scheme.error,
                  onTap: () {
                    Navigator.pop(context);
                    onLogout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final business = context.watch<BusinessProvider>().currentBusiness ?? user?.business;
    final onHeader = scheme.onPrimary;

    final name = (user?.name.trim().isNotEmpty ?? false) ? user!.name.trim() : l10n.menu;
    final initials = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    final role =
        auth.isAdmin
            ? 'Admin'
            : auth.isOwner
            ? l10n.drawerOwner
            : l10n.salesman;
    // Owners see their business; salesmen see the shop they sell for
    final place = auth.isOwner ? business?.name : user?.shop?.name ?? business?.name;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.55)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: onHeader.withValues(alpha: 0.25)),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: onHeader,
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: onHeader, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (user != null && user.email.isNotEmpty)
            Text(
              user.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onHeader.withValues(alpha: 0.8), fontSize: 13),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _HeaderChip(icon: Icons.badge_outlined, text: role, color: onHeader),
              if (place != null && place.isNotEmpty) _HeaderChip(icon: Icons.storefront_outlined, text: place, color: onHeader),
            ],
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
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _DrawerTile({required this.icon, required this.label, this.selected = false, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? (selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color ?? (selected ? scheme.onSecondaryContainer : scheme.onSurface),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
