import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized data service for the Vault financial dashboard.
///
/// Reads from EXISTING collections (platform_earnings, transactions, jobs,
/// users, admin settings) — no new collections needed for core metrics.
class VaultService {
  static final _db = FirebaseFirestore.instance;

  // ── Period helpers ─────────────────────────────────────────────────────────

  static DateTime periodStart(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'day':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        final weekday = now.weekday % 7; // Sunday = 0
        return DateTime(now.year, now.month, now.day - weekday);
      case 'month':
        return DateTime(now.year, now.month, 1);
      case 'year':
        return DateTime(now.year, 1, 1);
      default:
        return DateTime(now.year, now.month, now.day);
    }
  }

  static DateTime previousPeriodStart(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'day':
        return DateTime(now.year, now.month, now.day - 1);
      case 'week':
        final weekday = now.weekday % 7;
        return DateTime(now.year, now.month, now.day - weekday - 7);
      case 'month':
        return DateTime(now.year, now.month - 1, 1);
      case 'year':
        return DateTime(now.year - 1, 1, 1);
      default:
        return DateTime(now.year, now.month, now.day - 1);
    }
  }

  // ── Platform Balance ───────────────────────────────────────────────────────

  static Stream<Map<String, dynamic>> streamAdminSettings() {
    return _db
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings')
        .snapshots()
        .map((s) => s.data() ?? {});
  }

  // ── Platform Earnings (commission records) ─────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamEarnings(String period) {
    final start = periodStart(period);
    return _db
        .collection('platform_earnings')
        .where('timestamp', isGreaterThan: Timestamp.fromDate(start))
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  static Future<List<Map<String, dynamic>>> getEarningsForRange(
      DateTime start, DateTime end) async {
    final snap = await _db
        .collection('platform_earnings')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .limit(500)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // ── Transactions ───────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamTransactions(
    String period, {
    String? typeFilter,
    String? statusFilter,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('transactions')
        .where('timestamp',
            isGreaterThan:
                Timestamp.fromDate(periodStart(period)));

    if (typeFilter != null) {
      q = q.where('type', isEqualTo: typeFilter);
    }
    if (statusFilter != null) {
      q = q.where('payoutStatus', isEqualTo: statusFilter);
    }

    return q
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  static Stream<List<Map<String, dynamic>>> streamRecentTransactions({
    int limit = 20,
  }) {
    return _db
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  // ── Active Jobs (escrow / in-progress) ─────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamActiveJobs() {
    return _db
        .collection('jobs')
        .where('status', whereIn: [
          'paid_escrow',
          'expert_completed',
          'disputed',
        ])
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  // ── Completed Jobs (for GMV / metrics) ─────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCompletedJobs(
      String period) async {
    final snap = await _db
        .collection('jobs')
        .where('status', isEqualTo: 'completed')
        .where('completedAt',
            isGreaterThan: Timestamp.fromDate(periodStart(period)))
        .limit(500)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // ── Withdrawals ────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamWithdrawals({
    String? status,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('withdrawals');
    if (status != null) {
      q = q.where('status', isEqualTo: status);
    }
    return q
        .orderBy('requestedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  // ── Top Providers ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getTopProviders({
    int limit = 10,
  }) async {
    final snap = await _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .limit(100)
        .get();

    final providers = snap.docs.map((d) {
      final data = d.data();
      data['uid'] = d.id;
      return data;
    }).toList();

    providers.sort((a, b) {
      final aRev = (a['orderCount'] as num? ?? 0).toDouble();
      final bRev = (b['orderCount'] as num? ?? 0).toDouble();
      return bRev.compareTo(aRev);
    });

    return providers.take(limit).toList();
  }

  // ── Activity Feed ──────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamActivityFeed({
    int limit = 15,
  }) {
    return _db
        .collection('activity_log')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  // ── User / Provider Counts ─────────────────────────────────────────────────

  static Future<Map<String, int>> getCounts() async {
    final usersSnap = await _db.collection('users').count().get();
    final providersSnap = await _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .count()
        .get();
    final pendingSnap = await _db
        .collection('users')
        .where('isPendingExpert', isEqualTo: true)
        .count()
        .get();
    return {
      'users': usersSnap.count ?? 0,
      'providers': providersSnap.count ?? 0,
      'pending': pendingSnap.count ?? 0,
    };
  }

  // ── Computed Metrics ───────────────────────────────────────────────────────

  static double sumField(List<Map<String, dynamic>> docs, String field) {
    return docs.fold<double>(
        0, (s, d) => s + ((d[field] as num?) ?? 0).toDouble());
  }

  static double changePercent(double current, double previous) {
    if (previous == 0) return current > 0 ? 100 : 0;
    return ((current - previous) / previous * 100);
  }

  /// Compute daily revenue breakdown from earnings docs.
  static Map<String, double> dailyBreakdown(
      List<Map<String, dynamic>> earnings) {
    final map = <String, double>{};
    for (final e in earnings) {
      final ts = e['timestamp'] as Timestamp?;
      if (ts == null) continue;
      final d = ts.toDate();
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + ((e['amount'] as num?) ?? 0).toDouble();
    }
    return map;
  }

  /// Compute hourly activity distribution from earnings docs.
  static List<int> hourlyDistribution(List<Map<String, dynamic>> docs) {
    final hours = List.filled(24, 0);
    for (final d in docs) {
      final ts = d['timestamp'] as Timestamp?;
      if (ts == null) continue;
      hours[ts.toDate().hour]++;
    }
    return hours;
  }

  /// Category breakdown from platform_earnings or transactions.
  static Map<String, double> categoryBreakdown(
      List<Map<String, dynamic>> docs) {
    final map = <String, double>{};
    for (final d in docs) {
      final cat =
          (d['category'] as String?) ?? (d['serviceType'] as String?) ?? 'אחר';
      final amt = ((d['amount'] as num?) ?? 0).toDouble();
      map[cat] = (map[cat] ?? 0) + amt;
    }
    return map;
  }

  /// Pipeline stage counts from active jobs.
  static Map<String, int> pipelineCounts(List<Map<String, dynamic>> jobs) {
    final counts = <String, int>{
      'paid_escrow': 0,
      'expert_completed': 0,
      'disputed': 0,
    };
    for (final j in jobs) {
      final status = j['status'] as String? ?? '';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  /// Health score (0-100) computed from real metrics.
  static Map<String, double> computeHealthScore({
    required double revenueGrowth,
    required int completedJobs,
    required int cancelledJobs,
    required int activeProviders,
    required double avgSettlementHours,
  }) {
    final totalJobs = completedJobs + cancelledJobs;
    final completionRate =
        totalJobs > 0 ? completedJobs / totalJobs * 100 : 100.0;

    final growth = (revenueGrowth.clamp(-100, 200) + 100) / 3;
    final retention = completionRate.clamp(0, 100);
    final settlement = (100 - avgSettlementHours.clamp(0, 100)).clamp(0, 100);
    final diversity = (activeProviders.clamp(0, 50) / 50 * 100).clamp(0, 100);

    final total =
        growth * 0.3 + retention * 0.3 + settlement * 0.2 + diversity * 0.2;

    return {
      'total': total.clamp(0.0, 100.0),
      'growth': growth.clamp(0.0, 100.0),
      'retention': retention.toDouble().clamp(0.0, 100.0),
      'settlement': settlement.toDouble().clamp(0.0, 100.0),
      'diversity': diversity.toDouble().clamp(0.0, 100.0),
    };
  }
}
