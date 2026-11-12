import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/category_provider.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/widgets/fraction_management_dialog.dart';

/// One item: its category and every unit with prices (and cost and margin for owners).
class ItemDetailScreen extends StatelessWidget {
  final Item item;

  const ItemDetailScreen({super.key, required this.item});

  static final _money = NumberFormat('#,##0.00');
  static final _num = NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Follow the provider so new units show up; fall back to the passed item if it is gone
    final current = context.select<ItemProvider, Item>((p) {
      for (final i in p.items) {
        if (i.id == item.id) return i;
      }
      return item;
    });
    final categoryName = context.select<CategoryProvider, String?>((p) {
      for (final c in p.categories) {
        if (c.id == current.categoryId) return c.name;
      }
      return current.category?.name;
    });
    final isOwner = context.select<AuthProvider, bool>((a) => a.isOwner);
    final fractions = current.fractions ?? const <Fraction>[];

    return Scaffold(
      appBar: AppBar(title: Text(current.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Header
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.inventory_2_outlined, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                categoryName ?? l10n.noCategory,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                            Text(
                              '  ·  ${l10n.catalogUnitsCount(fractions.length)}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Units section
          Row(
            children: [
              Icon(Icons.straighten_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.units.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showDialog(context: context, builder: (_) => FractionManagementDialog(item: current)),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.manageUnits),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (fractions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Icon(Icons.straighten_rounded, size: 44, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(l10n.noUnitsAddedYet, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          else
            for (final f in fractions)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildUnitCard(context, l10n, f, isOwner)),
        ],
      ),
    );
  }

  Widget _buildUnitCard(BuildContext context, AppLocalizations l10n, Fraction f, bool isOwner) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = l10n.currencySymbol;
    final margin = f.sellingPrice == 0 ? 0.0 : (f.sellingPrice - f.purchasePrice) / f.sellingPrice * 100;
    final marginColor = margin < 0 ? scheme.error : (margin == 0 ? Colors.orange.shade800 : Colors.green.shade700);

    Widget stat(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(f.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (f.isUnit)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      l10n.catalogBaseUnit,
                      style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                Text(
                  '${l10n.ratio} ×${_num.format(f.ratio)}',
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                stat(l10n.soldPriceLabel, '$symbol ${_money.format(f.sellingPrice)}', color: scheme.primary),
                if (isOwner) ...[
                  stat(l10n.purchasePrice, '$symbol ${_money.format(f.purchasePrice)}'),
                  stat(l10n.profitMargin, '${margin.toStringAsFixed(1)}%', color: marginColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
