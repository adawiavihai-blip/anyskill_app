import 'package:flutter/material.dart';

import '../models/performance_metric.dart';
import '_design.dart';

/// Live business KPIs — revenue, bookings, active users, happiness, churn risk.
/// Reads from the shared `PerformanceMetric` snapshot. Numbers are aggregated
/// server-side every 5 minutes so this widget is O(1) reads.
class BusinessImpactWidget extends StatelessWidget {
  final PerformanceMetric metric;

  const BusinessImpactWidget({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final cards = <_ImpactTileData>[
      _ImpactTileData(
        icon: Icons.payments_rounded,
        label: 'הכנסות היום',
        value: '₪${_fmt(metric.revenueToday)}',
        accent: PerfDesign.pink,
        sublabel:
            'השבוע: ₪${_fmt(metric.revenueThisWeek)} · חודש: ₪${_fmt(metric.revenueThisMonth)}',
      ),
      _ImpactTileData(
        icon: Icons.shopping_bag_outlined,
        label: 'הזמנות היום',
        value: _fmtInt(metric.bookingsToday),
        accent: PerfDesign.indigo,
        sublabel:
            'שבוע: ${metric.bookingsThisWeek} · חודש: ${metric.bookingsThisMonth}',
      ),
      _ImpactTileData(
        icon: Icons.groups_2_outlined,
        label: 'משתמשים פעילים',
        value: _fmtInt(metric.dailyActiveUsers),
        accent: PerfDesign.purple,
        sublabel: 'חודשי: ${_fmtInt(metric.monthlyActiveUsers)}',
      ),
      _ImpactTileData(
        icon: Icons.sentiment_satisfied_alt_rounded,
        label: 'Happiness Score',
        value: '${metric.happinessScore}/100',
        accent: _happinessColor(metric.happinessScore),
        sublabel: _happinessLabel(metric.happinessScore),
      ),
      _ImpactTileData(
        icon: Icons.trending_down_rounded,
        label: 'סיכון עזיבה',
        value: _fmtInt(metric.churnRiskCount),
        accent: PerfDesign.orange,
        sublabel: 'לא נכנסו 7+ ימים',
      ),
      _ImpactTileData(
        icon: Icons.gavel_outlined,
        label: 'מחלוקות פתוחות',
        value: _fmtInt(metric.openDisputes),
        accent: metric.openDisputes > 0
            ? PerfDesign.rose
            : PerfDesign.statusGreen,
        sublabel: metric.openDisputes > 0 ? 'דורש טיפול' : 'הכל נקי',
      ),
    ];

    return PerfDesign.glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PerfDesign.pink, PerfDesign.rose],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_graph_rounded,
                    color: Colors.white, size: 18),
              ),
              const Spacer(),
              const Text(
                'השפעה עסקית · עכשיו',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: PerfDesign.textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (ctx, c) {
              final isWide = c.maxWidth >= 720;
              final crossAxisCount = isWide ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cards.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: isWide ? 2.3 : 1.65,
                ),
                itemBuilder: (_, i) => _ImpactTile(data: cards[i]),
              );
            },
          ),
        ],
      ),
    );
  }

  static Color _happinessColor(int s) {
    if (s >= 80) return PerfDesign.statusGreen;
    if (s >= 60) return PerfDesign.statusYellow;
    return PerfDesign.statusRed;
  }

  static String _happinessLabel(int s) {
    if (s >= 85) return 'מצוין';
    if (s >= 70) return 'טוב';
    if (s >= 50) return 'בינוני';
    return 'דורש שיפור';
  }

  static String _fmtInt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  static String _fmt(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

class _ImpactTileData {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final String sublabel;

  _ImpactTileData({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.sublabel,
  });
}

class _ImpactTile extends StatelessWidget {
  final _ImpactTileData data;
  const _ImpactTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PerfDesign.glassFillStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: data.accent.withValues(alpha: 0.22),
        ),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            data.accent.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(data.icon, color: data.accent, size: 18),
              const Spacer(),
              Text(
                data.label,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: PerfDesign.textLo,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          Text(
            data.value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: PerfDesign.textHi,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            data.sublabel,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: PerfDesign.textLo,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
