import 'package:flutter/material.dart';

import '../models/performance_metric.dart';
import '_design.dart';

/// Google SRE 4 Golden Signals: Latency, Traffic, Errors, Saturation.
/// At Milestone 1 we show best-effort values from existing sources. The
/// full infrastructure for p50/p95/p99 + CPU/memory landing in Milestone 3
/// (BigQuery pipeline).
class GoldenSignalsWidget extends StatelessWidget {
  final PerformanceMetric metric;
  const GoldenSignalsWidget({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
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
                    colors: [PerfDesign.indigo, PerfDesign.statusBlue],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monitor_heart_outlined,
                    color: Colors.white, size: 18),
              ),
              const Spacer(),
              const Text(
                '4 האותות הזהובים',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: PerfDesign.textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (ctx, c) {
              final isWide = c.maxWidth >= 560;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isWide ? 2 : 1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isWide ? 2.4 : 3.2,
                children: [
                  _SignalCard(
                    title: 'Latency',
                    hebrewTitle: 'זמן תגובה',
                    value: '${metric.apiP95LatencyMs}ms',
                    subtitle: 'p95 מדשבורד',
                    accent: _latencyColor(metric.apiP95LatencyMs),
                    icon: Icons.timer_outlined,
                    extraNote:
                        'p50/p99 מלא יופיע ב-Milestone 3 (BigQuery)',
                  ),
                  _SignalCard(
                    title: 'Traffic',
                    hebrewTitle: 'תעבורה',
                    value: _fmt(metric.dailyActiveUsers),
                    subtitle: 'DAU',
                    accent: PerfDesign.indigo,
                    icon: Icons.trending_up_rounded,
                    extraNote:
                        'חדשים היום: ${metric.newSignupsToday}',
                  ),
                  _SignalCard(
                    title: 'Errors',
                    hebrewTitle: 'שגיאות',
                    value: '${metric.errorRatePercent.toStringAsFixed(2)}%',
                    subtitle: 'שיעור',
                    accent: _errorColor(metric.errorRatePercent),
                    icon: Icons.error_outline_rounded,
                    extraNote:
                        'שעה אחרונה: ${metric.errorsLastHour} · 24ש: ${metric.errorsLast24h}',
                  ),
                  _SignalCard(
                    title: 'Saturation',
                    hebrewTitle: 'רוויה',
                    value: _saturationLabel(metric),
                    subtitle: 'קיבולת Firestore',
                    accent: _saturationColor(metric),
                    icon: Icons.battery_charging_full_rounded,
                    extraNote:
                        'כתיבות שיא: ${metric.firestorePeakWritesPerSec}/sec · מגבלה: 10K',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  static Color _latencyColor(int ms) {
    if (ms == 0) return PerfDesign.textLo;
    if (ms < 500) return PerfDesign.statusGreen;
    if (ms < 1500) return PerfDesign.statusYellow;
    return PerfDesign.statusRed;
  }

  static Color _errorColor(double pct) {
    if (pct < 0.5) return PerfDesign.statusGreen;
    if (pct < 2) return PerfDesign.statusYellow;
    return PerfDesign.statusRed;
  }

  static Color _saturationColor(PerformanceMetric m) {
    final pct = m.firestorePeakWritesPerSec / 10000;
    if (pct < 0.5) return PerfDesign.statusGreen;
    if (pct < 0.8) return PerfDesign.statusYellow;
    return PerfDesign.statusRed;
  }

  static String _saturationLabel(PerformanceMetric m) {
    final pct = (m.firestorePeakWritesPerSec / 10000 * 100).clamp(0, 100);
    return '${pct.toStringAsFixed(0)}%';
  }
}

class _SignalCard extends StatelessWidget {
  final String title;
  final String hebrewTitle;
  final String value;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final String extraNote;

  const _SignalCard({
    required this.title,
    required this.hebrewTitle,
    required this.value,
    required this.subtitle,
    required this.accent,
    required this.icon,
    required this.extraNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PerfDesign.glassFillStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const Spacer(),
              Text(
                '$hebrewTitle · $title',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: PerfDesign.textMid,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  color: PerfDesign.textLo,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  color: accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Text(
            extraNote,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: PerfDesign.textLo,
              fontSize: 11,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
