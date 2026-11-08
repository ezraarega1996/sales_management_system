import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/business.dart';
import 'package:inventory_frontend/models/sales_data.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/business_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/widgets/dashboard_chart.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';

/// Dashboard shared by owners and salesmen.
///
/// The server scopes the numbers by role (`GET /sales/dashboard`): owners see the whole business
/// with profit, shops and salesmen; a salesman sees their own sales and their shop's stock.
class DashboardView extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final VoidCallback onViewSales;
  final VoidCallback onViewStock;

  /// Owner only.
  final VoidCallback? onViewShops;

  /// Salesman only: shows a prominent "Sell item" button in the header.
  final VoidCallback? onSell;

  const DashboardView({
    super.key,
    required this.isLoading,
    required this.onRefresh,
    required this.onViewSales,
    required this.onViewStock,
    this.onViewShops,
    this.onSell,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sales = context.watch<SalesProvider>();
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.isOwner || auth.isAdmin;
    // Owners load the full business; the login payload already carries the name for salesmen
    final business = context.watch<BusinessProvider>().currentBusiness ?? auth.user?.business;
    final userName = auth.user?.name;
    final shopName = auth.user?.shop?.name;
    final stats = sales.dashboardStats;
    final fmt = _Fmt(l10n.currencySymbol);
    Widget header(Map<String, dynamic>? s) => _Header(
      business: business,
      userName: userName,
      shopName: isOwner ? null : shopName,
      isOwner: isOwner,
      stats: s,
      fmt: fmt,
      onSell: onSell,
    );

    final List<Widget> children;
    if (isLoading && stats == null) {
      children = [
        header(null),
        const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
      ];
    } else if (sales.error != null && stats == null) {
      children = [header(null), const SizedBox(height: 16), _ErrorCard(message: sales.error!, onRetry: onRefresh)];
    } else {
      final s = stats ?? const <String, dynamic>{};
      children = [
        header(s),
        const SizedBox(height: 16),
        _AllTimeCard(stats: s, fmt: fmt, isOwner: isOwner),
        const SizedBox(height: 16),
        _SectionCard(
          title: l10n.salesTrend,
          child: SizedBox(
            height: 190,
            child: DashboardChart(
              data: (s['salesByDay'] as List?) ?? const [],
              emptyText: l10n.noData,
              currencySymbol: l10n.currencySymbol,
            ),
          ),
        ),
        if (isOwner) ...[
          const SizedBox(height: 16),
          _ShopsCard(shops: (s['salesByShop'] as List?) ?? const [], fmt: fmt, onViewAll: onViewShops),
          const SizedBox(height: 16),
          _SalesmenCard(data: sales.todaySalesData, fmt: fmt),
        ],
        const SizedBox(height: 16),
        _TopItemsCard(items: (s['topItems'] as List?) ?? const [], fmt: fmt, onViewAll: onViewSales),
        const SizedBox(height: 16),
        _LowStockCard(items: (s['lowStock'] as List?) ?? const [], onViewAll: onViewStock),
        const SizedBox(height: 24),
      ];
    }

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class _Fmt {
  final String symbol;
  final NumberFormat _whole = NumberFormat('#,##0');
  final NumberFormat _qty = NumberFormat('#,##0.##');
  _Fmt(this.symbol);

  String money(dynamic v) => '$symbol ${_whole.format(_num(v))}';
  String qty(dynamic v) => _qty.format(_num(v));
  String percent(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v.abs() >= 10 ? 0 : 1)}%';
}

/// Sum of the last 7 days vs the 7 days before that, from salesByDay.
double? _weekOverWeek(List days) {
  if (days.isEmpty) return null;
  final today = DateTime.now();
  final startThis = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 6));
  final startPrev = startThis.subtract(const Duration(days: 7));
  double thisWeek = 0, prevWeek = 0;
  for (final d in days) {
    final date = DateTime.tryParse('${d['date']}');
    if (date == null) continue;
    if (!date.isBefore(startThis)) {
      thisWeek += _num(d['total']);
    } else if (!date.isBefore(startPrev)) {
      prevWeek += _num(d['total']);
    }
  }
  if (prevWeek == 0) return null;
  return (thisWeek - prevWeek) / prevWeek * 100;
}

// ---------------------------------------------------------------------------
// Header: greeting + today's numbers
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final Business? business;
  final String? userName;
  final String? shopName;
  final bool isOwner;
  final Map<String, dynamic>? stats;
  final _Fmt fmt;
  final VoidCallback? onSell;

  const _Header({
    required this.business,
    required this.userName,
    required this.shopName,
    required this.isOwner,
    required this.stats,
    required this.fmt,
    required this.onSell,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting =
        hour < 12
            ? l10n.dashGoodMorning
            : hour < 17
            ? l10n.dashGoodAfternoon
            : l10n.dashGoodEvening;
    final firstName = userName?.split(' ').first;
    final onHeader = scheme.onPrimary;

    final todaySales = _num(stats?['todaySales']);
    final todayProfit = _num(stats?['todayProfit']);
    final todayCount = (stats?['todayCount'] as num?)?.toInt() ?? 0;
    final margin = todaySales > 0 ? todayProfit / todaySales * 100 : null;
    final averageSale = todayCount > 0 ? todaySales / todayCount : 0;
    // Owners see the plan; salesmen see which shop they sell for
    final chip =
        isOwner
            ? (business == null
                ? null
                : l10n.dashPlan(toBeginningOfSentenceCase(business!.subscriptionPlan) ?? business!.subscriptionPlan))
            : shopName;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstName != null ? '$greeting, $firstName' : greeting,
                      style: TextStyle(color: onHeader.withValues(alpha: 0.85), fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      business?.name ?? l10n.dashboard,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onHeader, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (chip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: onHeader.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(chip, style: TextStyle(color: onHeader, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${l10n.dashTodayOverview} · ${DateFormat.MMMd().format(DateTime.now())}',
            style: TextStyle(color: onHeader.withValues(alpha: 0.8), fontSize: 12, letterSpacing: 0.3),
          ),
          const SizedBox(height: 4),
          Text(
            fmt.money(todaySales),
            style: TextStyle(color: onHeader, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child:
                    isOwner
                        ? _HeaderStat(
                          icon: Icons.trending_up_rounded,
                          label: l10n.dashProfit,
                          value: fmt.money(todayProfit),
                          hint: margin != null ? l10n.dashMargin('${margin.toStringAsFixed(0)}%') : null,
                          color: onHeader,
                        )
                        : _HeaderStat(
                          icon: Icons.calculate_outlined,
                          label: l10n.dashAverageSale,
                          value: fmt.money(averageSale),
                          color: onHeader,
                        ),
              ),
              Container(width: 1, height: 36, color: onHeader.withValues(alpha: 0.25)),
              const SizedBox(width: 16),
              Expanded(
                child: _HeaderStat(
                  icon: Icons.receipt_long_rounded,
                  label: l10n.dashTransactions,
                  value: '$todayCount',
                  color: onHeader,
                ),
              ),
            ],
          ),
          if (onSell != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSell,
                style: FilledButton.styleFrom(
                  backgroundColor: onHeader,
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.point_of_sale),
                label: Text(l10n.sellItem, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final Color color;

  const _HeaderStat({required this.icon, required this.label, required this.value, this.hint, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color.withValues(alpha: 0.85)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11)),
              Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
              if (hint != null) Text(hint!, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onViewAll;

  const _SectionCard({required this.title, this.subtitle, required this.child, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(AppLocalizations.of(context)!.dashViewAll),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AllTimeCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final _Fmt fmt;
  final bool isOwner;

  const _AllTimeCard({required this.stats, required this.fmt, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final change = _weekOverWeek((stats['salesByDay'] as List?) ?? const []);
    final up = (change ?? 0) >= 0;
    final changeColor = up ? Colors.green.shade700 : scheme.error;
    final count = (stats['salesCount'] as num?)?.toInt() ?? 0;
    final average = count > 0 ? _num(stats['totalSales']) / count : 0;

    return _SectionCard(
      title: isOwner ? l10n.dashAllTime : l10n.dashYourSales,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Metric(
                label: l10n.dashRevenue,
                value: fmt.money(stats['totalSales']),
                icon: Icons.payments_outlined,
                color: scheme.primary,
              ),
              if (isOwner)
                _Metric(
                  label: l10n.dashProfit,
                  value: fmt.money(stats['totalProfit']),
                  icon: Icons.savings_outlined,
                  color: Colors.green.shade700,
                ),
              _Metric(
                label: l10n.dashTransactions,
                value: '$count',
                icon: Icons.shopping_bag_outlined,
                color: scheme.tertiary,
              ),
              if (!isOwner)
                _Metric(
                  label: l10n.dashAverageSale,
                  value: fmt.money(average),
                  icon: Icons.calculate_outlined,
                  color: Colors.green.shade700,
                ),
            ],
          ),
          if (change != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: changeColor),
                  const SizedBox(width: 4),
                  Text(
                    l10n.dashVsPrevWeek(fmt.percent(change)),
                    style: TextStyle(color: changeColor, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _Metric({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _ShareBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: 6,
        color: color,
        backgroundColor: color.withValues(alpha: 0.12),
      ),
    );
  }
}

class _ShopsCard extends StatelessWidget {
  final List shops;
  final _Fmt fmt;
  final VoidCallback? onViewAll;

  const _ShopsCard({required this.shops, required this.fmt, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final total = shops.fold<double>(0, (sum, s) => sum + _num(s['total']));

    return _SectionCard(
      title: l10n.dashSalesByShop,
      subtitle: l10n.dashLast30Days,
      onViewAll: onViewAll,
      child:
          shops.isEmpty
              ? _Empty(text: l10n.noData)
              : Column(
                children: [
                  for (final s in shops)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.storefront_outlined, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${s['shopName']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Text(fmt.money(s['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _ShareBar(
                            fraction: total > 0 ? _num(s['total']) / total : 0,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${l10n.dashSalesCount('${s['count']}')} · ${total > 0 ? (_num(s['total']) / total * 100).toStringAsFixed(0) : 0}%',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
    );
  }
}

class _SalesmenCard extends StatelessWidget {
  final List<SalesData> data;
  final _Fmt fmt;

  const _SalesmenCard({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ranked = [...data]..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    const medals = [Color(0xFFF2B01E), Color(0xFF9EA7B3), Color(0xFFC7804A)];

    return _SectionCard(
      title: l10n.todaysSalesBySalesman,
      child:
          ranked.isEmpty
              ? _Empty(text: l10n.noSalesToday)
              : Column(
                children: [
                  for (var i = 0; i < ranked.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == ranked.length - 1 ? 0 : 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                i < 3 ? medals[i].withValues(alpha: 0.2) : theme.colorScheme.surfaceContainerHighest,
                            child: Text(
                              ranked[i].salesmanName.isNotEmpty ? ranked[i].salesmanName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: i < 3 ? medals[i] : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ranked[i].salesmanName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  l10n.dashSalesCount('${ranked[i].totalTransactions}'),
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Text(fmt.money(ranked[i].totalAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
    );
  }
}

class _TopItemsCard extends StatelessWidget {
  final List items;
  final _Fmt fmt;
  final VoidCallback onViewAll;

  const _TopItemsCard({required this.items, required this.fmt, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final best = items.isEmpty ? 0.0 : items.map((e) => _num(e['totalAmount'])).reduce(math.max);

    return _SectionCard(
      title: l10n.topSellingItems,
      onViewAll: onViewAll,
      child:
          items.isEmpty
              ? _Empty(text: l10n.noItemsFound)
              : Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${items[i]['Item']?['name'] ?? '-'}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(
                                      fmt.money(items[i]['totalAmount']),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _ShareBar(
                                  fraction: best > 0 ? _num(items[i]['totalAmount']) / best : 0,
                                  color: theme.colorScheme.tertiary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.dashSold(fmt.qty(items[i]['totalQuantity'])),
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final List items;
  final VoidCallback onViewAll;

  const _LowStockCard({required this.items, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final qtyFmt = NumberFormat('#,##0.##');

    return _SectionCard(
      title: l10n.dashLowStock,
      onViewAll: onViewAll,
      child:
          items.isEmpty
              ? _Empty(text: l10n.dashLowStockEmpty, icon: Icons.check_circle_outline)
              : Column(
                children: [
                  for (final item in items)
                    Builder(
                      builder: (context) {
                        final qty = _num(item['quantity']);
                        final critical = qty <= 10;
                        final color = critical ? theme.colorScheme.error : Colors.orange.shade800;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                critical ? Icons.error_outline : Icons.warning_amber_rounded,
                                color: color,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${item['itemName']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      '${item['shopName']}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                l10n.dashLeft(qtyFmt.format(qty), '${item['unit'] ?? ''}'),
                                style: TextStyle(color: color, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Empty({required this.text, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
            IconButton(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, color: scheme.onErrorContainer),
              tooltip: AppLocalizations.of(context)!.refresh,
            ),
          ],
        ),
      ),
    );
  }
}
