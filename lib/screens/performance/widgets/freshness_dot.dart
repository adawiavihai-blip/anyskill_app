import 'package:flutter/material.dart';

import '_design.dart';

/// Freshness indicator for the performance snapshot.
///
/// States:
///   🟢 green  — data < 1 hour old (fresh)
///   🟡 yellow — data 1–5 hours old (stale but usable)
///   🔴 red    — data > 5 hours old (CF probably not running)
///   ⏳ gray   — no data yet (waiting for first snapshot)
enum FreshnessLevel { fresh, stale, old, missing }

class FreshnessDot extends StatelessWidget {
  final DateTime? lastUpdated;
  final double size;

  const FreshnessDot({
    super.key,
    required this.lastUpdated,
    this.size = 9,
  });

  FreshnessLevel get _level {
    final t = lastUpdated;
    if (t == null) return FreshnessLevel.missing;
    final age = DateTime.now().difference(t);
    if (age.inMinutes < 60) return FreshnessLevel.fresh;
    if (age.inHours < 5) return FreshnessLevel.stale;
    return FreshnessLevel.old;
  }

  Color get _color => switch (_level) {
        FreshnessLevel.fresh => PerfDesign.statusGreen,
        FreshnessLevel.stale => PerfDesign.statusYellow,
        FreshnessLevel.old => PerfDesign.statusRed,
        FreshnessLevel.missing => PerfDesign.textLo,
      };

  @override
  Widget build(BuildContext context) {
    if (_level == FreshnessLevel.missing) {
      return Icon(
        Icons.hourglass_empty_rounded,
        size: size + 3,
        color: _color,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color,
        boxShadow: [
          BoxShadow(
            color: _color.withValues(alpha: 0.45),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Banner shown at the top of the Performance tab when no snapshot has
/// ever been written (fresh deploy, CF not yet fired).
class WaitingForSnapshotBanner extends StatelessWidget {
  const WaitingForSnapshotBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: PerfDesign.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PerfDesign.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: PerfDesign.orange.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_bottom_rounded,
              color: PerfDesign.orange,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  '⏳ ממתין לעדכון ראשון',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: PerfDesign.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'updateMetricsSnapshot רץ כל 5 דקות. '
                  'אם אתה רואה את זה יותר מ-10 דקות — בדוק firebase functions:log.',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: PerfDesign.textMid,
                    fontSize: 12,
                    height: 1.45,
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
