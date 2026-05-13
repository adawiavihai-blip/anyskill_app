import 'package:flutter/material.dart';

import '../services/metrics_calculator.dart';
import '_design.dart';

/// Scale Readiness Score (0-100) — static reflection of which Milestones
/// are active. At Milestone 1 expect ~68. Rebuilds when the infra flags
/// in `CURRENT_STATUS.md` flip.
///
/// Intentionally NOT live-checked against actual infra — flags must be set
/// manually by Claude Code when a Milestone completes.
class ScaleReadinessWidget extends StatelessWidget {
  final bool hasRedis;
  final bool hasBigQuery;
  final bool hasSharding;
  final bool hasMultiRegion;
  final bool hasAiAgents;

  const ScaleReadinessWidget({
    super.key,
    this.hasRedis = false,
    this.hasBigQuery = false,
    this.hasSharding = false,
    this.hasMultiRegion = false,
    this.hasAiAgents = false,
  });

  @override
  Widget build(BuildContext context) {
    final score = ScaleAlertEngine.scaleReadinessScore(
      hasRedis: hasRedis,
      hasBigQuery: hasBigQuery,
      hasSharding: hasSharding,
      hasMultiRegion: hasMultiRegion,
      hasAiAgents: hasAiAgents,
    );
    final scoreColor = _scoreColor(score);

    final items = <_ReadinessItem>[
      const _ReadinessItem(
        label: 'Firestore Auto-scaling',
        status: _ItemStatus.done,
        note: 'מובנה בפלטפורמה',
      ),
      const _ReadinessItem(
        label: 'Daily backups (Firestore)',
        status: _ItemStatus.done,
        note: 'scheduledFirestoreBackup פעיל',
      ),
      const _ReadinessItem(
        label: 'Sentry + Crashlytics + Watchtower',
        status: _ItemStatus.done,
        note: 'שלושה ערוצי ניטור פעילים',
      ),
      _ReadinessItem(
        label: 'Redis Cache',
        status: hasRedis ? _ItemStatus.done : _ItemStatus.pending,
        note:
            hasRedis ? 'Hit rate > 80%' : 'מופעל ב-Milestone 2 (DAU > 10K)',
      ),
      _ReadinessItem(
        label: 'BigQuery Pipeline',
        status:
            hasBigQuery ? _ItemStatus.done : _ItemStatus.pending,
        note: hasBigQuery
            ? 'מטריקות נקראות מ-BigQuery'
            : 'מופעל ב-Milestone 3 (DAU > 50K)',
      ),
      _ReadinessItem(
        label: 'Firestore Sharding (×10)',
        status:
            hasSharding ? _ItemStatus.done : _ItemStatus.missing,
        note: hasSharding
            ? '10 shards פעילים'
            : 'מופעל ב-Milestone 4 (DAU > 500K)',
      ),
      _ReadinessItem(
        label: 'Multi-region deployment',
        status:
            hasMultiRegion ? _ItemStatus.done : _ItemStatus.missing,
        note: hasMultiRegion ? 'IL + US + EU' : 'מופעל ב-Milestone 4',
      ),
      _ReadinessItem(
        label: 'AI Agents + Chaos Engineering',
        status:
            hasAiAgents ? _ItemStatus.done : _ItemStatus.missing,
        note: hasAiAgents
            ? '5 סוכנים פעילים'
            : 'מופעל ב-Milestone 5 (DAU > 5M)',
      ),
    ];

    return PerfDesign.glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScoreRing(score: score, color: scoreColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'מוכנות לסקייל',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: PerfDesign.textHi,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _scoreLabel(score),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'הציון עולה כשמפעילים Milestones נוספים',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: PerfDesign.textLo,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ReadinessRow(item: it),
              )),
        ],
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 85) return PerfDesign.statusGreen;
    if (score >= 60) return PerfDesign.statusYellow;
    return PerfDesign.statusRed;
  }

  String _scoreLabel(int score) {
    if (score >= 85) return 'מוכן לסקייל מלא';
    if (score >= 60) return 'מוכן לצמיחה';
    return 'נדרשות שדרוגים';
  }
}

enum _ItemStatus { done, pending, missing }

extension _ItemStatusX on _ItemStatus {
  Color get color => switch (this) {
        _ItemStatus.done => PerfDesign.statusGreen,
        _ItemStatus.pending => PerfDesign.statusYellow,
        _ItemStatus.missing => PerfDesign.statusRed,
      };
  IconData get icon => switch (this) {
        _ItemStatus.done => Icons.check_circle_rounded,
        _ItemStatus.pending => Icons.schedule_rounded,
        _ItemStatus.missing => Icons.close_rounded,
      };
}

class _ReadinessItem {
  final String label;
  final _ItemStatus status;
  final String note;
  const _ReadinessItem({
    required this.label,
    required this.status,
    required this.note,
  });
}

class _ReadinessRow extends StatelessWidget {
  final _ReadinessItem item;
  const _ReadinessRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PerfDesign.glassFillStrong,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(item.status.icon, color: item.status.color, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.label,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: PerfDesign.textHi,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.note,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: PerfDesign.textLo,
                    fontSize: 11.5,
                    height: 1.4,
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

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  const _ScoreRing({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$score',
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  '/100',
                  style: TextStyle(
                    color: PerfDesign.textLo,
                    fontSize: 10,
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
