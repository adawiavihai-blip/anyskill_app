import '../models/performance_metric.dart';
import '../models/scale_alert.dart';

/// The core innovation: turns a `PerformanceMetric` snapshot into a prioritized
/// list of `ScaleAlert`s based on the 4 Milestone triggers. The top alert is
/// rendered as the hero banner at the top of the Performance tab.
///
/// Trigger thresholds mirror `scaling_system/CURRENT_STATUS.md`:
/// - Milestone 2 (Redis):    DAU > 10K      OR  Firestore cost > $200/mo
/// - Milestone 3 (BigQuery): DAU > 50K      OR  Dashboard load > 2000ms
/// - Milestone 4 (Sharding): DAU > 500K     OR  Peak writes > 8K/sec
/// - Milestone 5 (V5):       DAU > 5M
class ScaleAlertEngine {
  ScaleAlertEngine._();

  /// Returns all applicable alerts, sorted from most severe to least.
  /// The first alert is what the UI displays prominently.
  static List<ScaleAlert> evaluate(PerformanceMetric m) {
    final alerts = <ScaleAlert>[];

    // ── Milestone 5 (Enterprise V5) ─────────────────────────────────
    if (m.dailyActiveUsers > 5000000) {
      alerts.add(ScaleAlert(
        id: 'milestone_5_dau',
        level: ScaleAlertLevel.critical,
        title: '🚀 הגיע הזמן ל-Enterprise V5!',
        message:
            'עברת 5M DAU. נדרשים AI Agents, Chaos Engineering ו-Session Replay.',
        actionLabel: 'הפעל Milestone 5',
        targetMilestone: 5,
        milestoneFile: '05_ENTERPRISE_V5.md',
        triggerDetail: 'DAU: ${_fmt(m.dailyActiveUsers)} (סף: 5M)',
      ));
    }

    // ── Milestone 4 (Sharding + Multi-region) ─────────────────────
    if (m.firestorePeakWritesPerSec > 8000) {
      alerts.add(ScaleAlert(
        id: 'milestone_4_writes',
        level: ScaleAlertLevel.critical,
        title: '🔴 דחוף: Sharding נדרש!',
        message:
            'שיא הכתיבות ל-Firestore: ${m.firestorePeakWritesPerSec}/sec. '
            'מתקרבים למגבלת 10K. נדרש Sharding ל-10 shards מיידית.',
        actionLabel: 'הפעל Milestone 4',
        targetMilestone: 4,
        milestoneFile: '04_SHARDING_MULTIREGION.md',
        triggerDetail: 'Peak writes: ${m.firestorePeakWritesPerSec}/sec (סף: 8K)',
      ));
    } else if (m.dailyActiveUsers > 500000) {
      alerts.add(ScaleAlert(
        id: 'milestone_4_dau',
        level: ScaleAlertLevel.critical,
        title: '🔴 Sharding + Multi-region נדרש!',
        message:
            'עברת 500K DAU. Firestore בקרוב יגיע לתקרת הכתיבות. נדרש Sharding.',
        actionLabel: 'הפעל Milestone 4',
        targetMilestone: 4,
        milestoneFile: '04_SHARDING_MULTIREGION.md',
        triggerDetail: 'DAU: ${_fmt(m.dailyActiveUsers)} (סף: 500K)',
      ));
    }

    // ── Milestone 3 (BigQuery Pipeline) ───────────────────────────
    if (m.dashboardLoadTimeMs > 2000) {
      alerts.add(ScaleAlert(
        id: 'milestone_3_dashboard',
        level: ScaleAlertLevel.critical,
        title: '🟠 קריטי: BigQuery נדרש!',
        message:
            'טעינת הדשבורד: ${m.dashboardLoadTimeMs}ms — איטי מדי. '
            'העברת המטריקות ל-BigQuery תפחית ב-80%.',
        actionLabel: 'הפעל Milestone 3',
        targetMilestone: 3,
        milestoneFile: '03_BIGQUERY_PIPELINE.md',
        triggerDetail: 'טעינה: ${m.dashboardLoadTimeMs}ms (סף: 2000ms)',
      ));
    } else if (m.dailyActiveUsers > 50000) {
      alerts.add(ScaleAlert(
        id: 'milestone_3_dau',
        level: ScaleAlertLevel.warning,
        title: '🟠 BigQuery Pipeline מומלץ',
        message:
            'עברת 50K DAU. מטריקות ישירות מ-Firestore לא יעמדו בעומס. '
            'העבר ל-BigQuery.',
        actionLabel: 'הפעל Milestone 3',
        targetMilestone: 3,
        milestoneFile: '03_BIGQUERY_PIPELINE.md',
        triggerDetail: 'DAU: ${_fmt(m.dailyActiveUsers)} (סף: 50K)',
      ));
    }

    // ── Milestone 2 (Redis Cache) ─────────────────────────────────
    if (m.firestoreMonthlyCostUsd > 200) {
      alerts.add(ScaleAlert(
        id: 'milestone_2_cost',
        level: ScaleAlertLevel.warning,
        title: '💸 עלויות Firestore עולות!',
        message:
            'החודש: \$${m.firestoreMonthlyCostUsd.toStringAsFixed(0)}. '
            'Redis יחסוך כ-60% על קריאות חוזרות.',
        actionLabel: 'הפעל Milestone 2',
        targetMilestone: 2,
        milestoneFile: '02_REDIS_SETUP.md',
        triggerDetail:
            'עלות Firestore: \$${m.firestoreMonthlyCostUsd.toStringAsFixed(0)}/mo (סף: \$200)',
      ));
    } else if (m.dailyActiveUsers > 10000) {
      alerts.add(ScaleAlert(
        id: 'milestone_2_dau',
        level: ScaleAlertLevel.warning,
        title: '🟡 הגיע הזמן ל-Redis!',
        message:
            'עברת 10K DAU. Redis יחסוך \$100+/חודש ויוריד latency ב-70%.',
        actionLabel: 'הפעל Milestone 2',
        targetMilestone: 2,
        milestoneFile: '02_REDIS_SETUP.md',
        triggerDetail: 'DAU: ${_fmt(m.dailyActiveUsers)} (סף: 10K)',
      ));
    }

    // ── No triggers — all good ────────────────────────────────────
    if (alerts.isEmpty) {
      alerts.add(ScaleAlert(
        id: 'healthy',
        level: ScaleAlertLevel.success,
        title: '✅ הכל תחת שליטה',
        message:
            'נכון לעכשיו: ${_fmt(m.dailyActiveUsers)} DAU, '
            'ללא טריגרים פעילים. המערכת יציבה.',
        targetMilestone: 1,
        triggerDetail: 'Milestone 1 פעיל',
      ));
    }

    return alerts;
  }

  /// Returns the top (most severe) alert — what the hero banner should show.
  static ScaleAlert top(PerformanceMetric m) => evaluate(m).first;

  /// Happiness score: % of jobs that reached "completed" status. Clamped 0-100.
  /// Returns 100 when there are zero jobs (no signal = neutral).
  static int happinessScore(PerformanceMetric m) {
    if (m.totalJobs == 0) return 100;
    final pct = (m.completedJobs / m.totalJobs * 100).round();
    return pct.clamp(0, 100);
  }

  /// Scale Readiness Score (0-100). Static calculation — reflects the
  /// infrastructure flags from CURRENT_STATUS.md. At Milestone 1 expect ~68.
  static int scaleReadinessScore({
    bool hasRedis = false,
    bool hasBigQuery = false,
    bool hasSharding = false,
    bool hasMultiRegion = false,
    bool hasAiAgents = false,
  }) {
    var score = 60; // Firestore + backups baseline
    if (hasRedis) score += 10;
    if (hasBigQuery) score += 10;
    if (hasSharding) score += 10;
    if (hasMultiRegion) score += 5;
    if (hasAiAgents) score += 5;
    return score.clamp(0, 100);
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
