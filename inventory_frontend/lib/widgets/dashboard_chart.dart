import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Daily sales line chart. [data] is a list of `{date: 'yyyy-MM-dd', total: num}`.
class DashboardChart extends StatelessWidget {
  final List<dynamic> data;
  final String? emptyText;
  final String currencySymbol;

  const DashboardChart({
    super.key,
    required this.data,
    this.emptyText,
    this.currencySymbol = '\$',
  });

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    if (data.isEmpty) {
      return Center(child: Text(emptyText ?? '', style: TextStyle(color: muted)));
    }

    final spots = [for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), _num(data[i]['total']))];
    final peak = spots.map((s) => s.y).reduce(math.max);
    final interval = _niceInterval(peak);
    final maxY = (peak / interval).ceil() * interval;
    final labelEvery = math.max(1, (data.length / 5).ceil());
    final compact = NumberFormat.compact();
    final money = NumberFormat('#,##0');

    DateTime? dateAt(int i) => (i >= 0 && i < data.length) ? DateTime.tryParse('${data[i]['date']}') : null;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(color: muted.withValues(alpha: 0.15), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == meta.max && value != 0 && (meta.max / interval) % 1 != 0) return const SizedBox();
                return Text(compact.format(value), style: TextStyle(fontSize: 10, color: muted));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                final isLast = i == data.length - 1;
                if (value != i || (i % labelEvery != 0 && !isLast)) return const SizedBox();
                // Avoid the last label colliding with the previous one
                if (!isLast && data.length - 1 - i < labelEvery / 2) return const SizedBox();
                final date = dateAt(i);
                if (date == null) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat.MMMd().format(date), style: TextStyle(fontSize: 10, color: muted)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: scheme.inverseSurface,
            getTooltipItems: (touched) => touched.map((t) {
              final date = dateAt(t.x.toInt());
              return LineTooltipItem(
                '${date != null ? DateFormat.MMMd().format(date) : ''}\n',
                TextStyle(color: scheme.onInverseSurface.withValues(alpha: 0.8), fontSize: 11),
                children: [
                  TextSpan(
                    text: '$currencySymbol ${money.format(t.y)}',
                    style: TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) => spot.x == spots.last.x,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: scheme.primary,
                strokeWidth: 2,
                strokeColor: scheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primary.withValues(alpha: 0.28), scheme.primary.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rounds the axis step to 1/2/5 x 10^n so labels read cleanly.
  static double _niceInterval(double peak) {
    if (peak <= 0) return 1;
    final raw = peak / 4;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final residual = raw / magnitude;
    final nice = residual <= 1 ? 1 : residual <= 2 ? 2 : residual <= 5 ? 5 : 10;
    return nice * magnitude;
  }
}
