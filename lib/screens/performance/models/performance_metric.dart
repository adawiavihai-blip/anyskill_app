import 'package:cloud_firestore/cloud_firestore.dart';

/// Snapshot of platform metrics. Produced by `updateMetricsSnapshot` CF
/// (scheduled every 5 min) and read live by every widget on the tab.
class PerformanceMetric {
  final int dailyActiveUsers;
  final int monthlyActiveUsers;
  final int totalRegistered;
  final int newSignupsToday;

  final int bookingsToday;
  final int bookingsThisWeek;
  final int bookingsThisMonth;

  final double revenueToday;
  final double revenueThisWeek;
  final double revenueThisMonth;

  final int completedJobs;
  final int totalJobs;
  final int cancelledJobs;

  final int errorsLastHour;
  final int errorsLast24h;
  final int openDisputes;

  final int happinessScore; // 0-100
  final int churnRiskCount;

  final double firestoreMonthlyCostUsd;
  final int firestoreReadsPerDay;
  final int firestoreWritesPerDay;
  final int firestorePeakWritesPerSec;

  final int dashboardLoadTimeMs;
  final int apiP95LatencyMs;
  final double errorRatePercent;
  final double uptimePercent;

  final DateTime? lastUpdated;

  const PerformanceMetric({
    this.dailyActiveUsers = 0,
    this.monthlyActiveUsers = 0,
    this.totalRegistered = 0,
    this.newSignupsToday = 0,
    this.bookingsToday = 0,
    this.bookingsThisWeek = 0,
    this.bookingsThisMonth = 0,
    this.revenueToday = 0,
    this.revenueThisWeek = 0,
    this.revenueThisMonth = 0,
    this.completedJobs = 0,
    this.totalJobs = 0,
    this.cancelledJobs = 0,
    this.errorsLastHour = 0,
    this.errorsLast24h = 0,
    this.openDisputes = 0,
    this.happinessScore = 100,
    this.churnRiskCount = 0,
    this.firestoreMonthlyCostUsd = 0,
    this.firestoreReadsPerDay = 0,
    this.firestoreWritesPerDay = 0,
    this.firestorePeakWritesPerSec = 0,
    this.dashboardLoadTimeMs = 0,
    this.apiP95LatencyMs = 0,
    this.errorRatePercent = 0,
    this.uptimePercent = 100,
    this.lastUpdated,
  });

  factory PerformanceMetric.empty() => const PerformanceMetric();

  factory PerformanceMetric.fromMap(Map<String, dynamic> m) {
    int i(dynamic v) => v is num ? v.toInt() : 0;
    double d(dynamic v) => v is num ? v.toDouble() : 0;
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return PerformanceMetric(
      dailyActiveUsers: i(m['daily_active_users']),
      monthlyActiveUsers: i(m['monthly_active_users']),
      totalRegistered: i(m['total_registered']),
      newSignupsToday: i(m['new_signups_today']),
      bookingsToday: i(m['bookings_today']),
      bookingsThisWeek: i(m['bookings_this_week']),
      bookingsThisMonth: i(m['bookings_this_month']),
      revenueToday: d(m['revenue_today']),
      revenueThisWeek: d(m['revenue_this_week']),
      revenueThisMonth: d(m['revenue_this_month']),
      completedJobs: i(m['completed_jobs']),
      totalJobs: i(m['total_jobs']),
      cancelledJobs: i(m['cancelled_jobs']),
      errorsLastHour: i(m['errors_last_hour']),
      errorsLast24h: i(m['errors_last_24h']),
      openDisputes: i(m['open_disputes']),
      happinessScore: i(m['happiness_score']).clamp(0, 100),
      churnRiskCount: i(m['churn_risk_count']),
      firestoreMonthlyCostUsd: d(m['firestore_monthly_cost_usd']),
      firestoreReadsPerDay: i(m['firestore_reads_per_day']),
      firestoreWritesPerDay: i(m['firestore_writes_per_day']),
      firestorePeakWritesPerSec: i(m['firestore_peak_writes_per_sec']),
      dashboardLoadTimeMs: i(m['dashboard_load_time_ms']),
      apiP95LatencyMs: i(m['api_p95_latency_ms']),
      errorRatePercent: d(m['error_rate_percent']),
      uptimePercent: m['uptime_percent'] is num
          ? (m['uptime_percent'] as num).toDouble()
          : 100,
      lastUpdated: ts(m['last_updated']),
    );
  }
}
