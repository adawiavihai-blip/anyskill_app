import 'package:cloud_firestore/cloud_firestore.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class AiStats {
  final int todayCount;
  final int approvedTotal;
  final int rejectedTotal;
  final int pendingTotal;

  const AiStats({
    required this.todayCount,
    required this.approvedTotal,
    required this.rejectedTotal,
    required this.pendingTotal,
  });

  double get approvalRate {
    final reviewed = approvedTotal + rejectedTotal;
    return reviewed == 0 ? 0 : approvedTotal / reviewed;
  }
}

class TrendingSearch {
  final String query;
  final int count;
  final bool zeroResults;

  const TrendingSearch({
    required this.query,
    required this.count,
    required this.zeroResults,
  });
}

class CategoryRevenue {
  final String name;
  final double estimatedRevenue;
  final int providerCount;

  const CategoryRevenue({
    required this.name,
    required this.estimatedRevenue,
    required this.providerCount,
  });
}

class BusinessAiData {
  final AiStats aiStats;
  final List<TrendingSearch> trending;
  final List<TrendingSearch> zeroResults;
  final double weeklyEarnings;
  final double projectedWeekly;
  final List<CategoryRevenue> highValueCategories;
  /// Past 7 days of platform commission, index 0 = oldest day, 6 = today.
  final List<double> dailyEarnings;

  const BusinessAiData({
    required this.aiStats,
    required this.trending,
    required this.zeroResults,
    required this.weeklyEarnings,
    required this.projectedWeekly,
    required this.highValueCategories,
    required this.dailyEarnings,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class BusinessAiService {
  BusinessAiService._();

  static final _db = FirebaseFirestore.instance;

  /// Loads all dashboard data in parallel.
  static Future<BusinessAiData> loadAll() async {
    final results = await Future.wait([
      _getAiStats(),
      _getTrendingSearches(),
      _getWeeklyEarnings(),
      _getHighValueCategories(),
      _getDailyEarnings(),
    ]);

    final stats    = results[0] as AiStats;
    final searches = results[1] as List<TrendingSearch>;
    final earnings = results[2] as double;
    final cats     = results[3] as List<CategoryRevenue>;
    final daily    = results[4] as List<double>;

    // Project weekly earnings: earnings so far ÷ day-of-week × 7
    final dayOfWeek = DateTime.now().weekday; // 1=Mon … 7=Sun
    final projected = dayOfWeek > 0 ? (earnings / dayOfWeek) * 7 : earnings;

    return BusinessAiData(
      aiStats:             stats,
      trending:            searches.where((t) => !t.zeroResults).take(10).toList(),
      zeroResults:         searches.where((t) => t.zeroResults).take(10).toList(),
      weeklyEarnings:      earnings,
      projectedWeekly:     projected,
      highValueCategories: cats.take(8).toList(),
      dailyEarnings:       daily,
    );
  }

  /// Real-time stream of pending-queue count for the badge.
  static Stream<int> pendingQueueStream() => _db
      .collection('categories_pending')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.length);

  // ── Private loaders ─────────────────────────────────────────────────────────

  static Future<AiStats> _getAiStats() async {
    final now        = DateTime.now();
    final todayStart = Timestamp.fromDate(DateTime(now.year, now.month, now.day));

    final snap = await _db.collection('categories_pending').limit(500).get();
    final docs = snap.docs.map((d) => d.data()).toList();

    final todayCount = docs.where((d) {
      final ts = d['createdAt'] as Timestamp?;
      return ts != null && ts.compareTo(todayStart) >= 0;
    }).length;

    return AiStats(
      todayCount:    todayCount,
      approvedTotal: docs.where((d) => d['status'] == 'approved').length,
      rejectedTotal: docs.where((d) => d['status'] == 'rejected').length,
      pendingTotal:  docs.where((d) => d['status'] == 'pending').length,
    );
  }

  static Future<List<TrendingSearch>> _getTrendingSearches() async {
    try {
      final snap = await _db
          .collection('search_logs')
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();

      if (snap.docs.isEmpty) return [];

      final Map<String, int>  counts = {};
      final Map<String, bool> zeros  = {};

      for (final doc in snap.docs) {
        final d = doc.data();
        final q = (d['query'] as String? ?? '').trim().toLowerCase();
        if (q.length < 2) continue;
        counts[q] = (counts[q] ?? 0) + 1;
        if (d['zeroResults'] == true) zeros[q] = true;
      }

      return counts.entries
          .map((e) => TrendingSearch(
                query:       e.key,
                count:       e.value,
                zeroResults: zeros[e.key] ?? false,
              ))
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));
    } catch (_) {
      return []; // collection may not exist yet
    }
  }

  static Future<double> _getWeeklyEarnings() async {
    try {
      final weekAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 7)),
      );
      final snap = await _db
          .collection('platform_earnings')
          .where('timestamp', isGreaterThan: weekAgo)
          .limit(300)
          .get();
      return snap.docs.fold<double>(
        0,
        (acc, d) => acc + ((d.data()['amount'] as num?) ?? 0).toDouble(),
      );
    } catch (_) {
      return 0;
    }
  }

  /// Returns daily platform commission for the last 7 days.
  /// Index 0 = 6 days ago, index 6 = today.
  static Future<List<double>> _getDailyEarnings() async {
    final now = DateTime.now();
    final sixDaysAgo = now.subtract(const Duration(days: 6));
    final startOfPeriod = DateTime(
        sixDaysAgo.year, sixDaysAgo.month, sixDaysAgo.day);
    try {
      final snap = await _db
          .collection('platform_earnings')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfPeriod))
          .limit(500)
          .get();
      final List<double> daily = List.filled(7, 0.0);
      for (final doc in snap.docs) {
        final ts = (doc.data()['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        final daysAgo = now.difference(ts).inDays.clamp(0, 6);
        daily[6 - daysAgo] +=
            ((doc.data()['amount'] as num?) ?? 0).toDouble();
      }
      return daily;
    } catch (_) {
      return List.filled(7, 0.0);
    }
  }

  static Future<List<CategoryRevenue>> _getHighValueCategories() async {
    final snap = await _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .limit(200)
        .get();

    final Map<String, double> revenue = {};
    final Map<String, int>    counts  = {};

    for (final doc in snap.docs) {
      final d   = doc.data();
      final cat = (d['serviceType'] as String? ?? '').trim();
      if (cat.isEmpty) continue;
      final price    = (d['pricePerHour'] as num? ?? 0).toDouble();
      final bookings = (d['bookingCount'] as num? ?? 0).toDouble();
      revenue[cat] = (revenue[cat] ?? 0) + (price * bookings);
      counts[cat]  = (counts[cat]  ?? 0) + 1;
    }

    return revenue.entries
        .map((e) => CategoryRevenue(
              name:              e.key,
              estimatedRevenue:  e.value,
              providerCount:     counts[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.estimatedRevenue.compareTo(a.estimatedRevenue));
  }
}

// ── Market Alert model ────────────────────────────────────────────────────────

class MarketAlert {
  final String    keyword;
  final int       searchCount;
  final int       totalAlerts;
  final DateTime? lastAlertedAt;

  const MarketAlert({
    required this.keyword,
    required this.searchCount,
    required this.totalAlerts,
    this.lastAlertedAt,
  });
}

// ── Alert threshold & history helpers ────────────────────────────────────────

extension BusinessAiAlerts on BusinessAiService {
  static final _db = FirebaseFirestore.instance;
  static final _settingsRef = FirebaseFirestore.instance
      .collection('admin')
      .doc('admin')
      .collection('settings')
      .doc('settings');

  /// Reads the current alert threshold (default 5).
  static Future<int> getAlertThreshold() async {
    final doc = await _settingsRef.get();
    return (doc.data()?['marketAlertThreshold'] as int?) ?? 5;
  }

  /// Persists a new threshold to Firestore.
  static Future<void> setAlertThreshold(int threshold) =>
      _settingsRef.set(
        {'marketAlertThreshold': threshold},
        SetOptions(merge: true),
      );

  /// Returns the 20 most recent market alerts, newest first.
  static Future<List<MarketAlert>> getRecentAlerts() async {
    try {
      final snap = await _db
          .collection('market_alerts')
          .orderBy('lastAlertedAt', descending: true)
          .limit(20)
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        return MarketAlert(
          keyword:      data['keyword']     as String? ?? d.id,
          searchCount:  (data['searchCount'] as int?)  ?? 0,
          totalAlerts:  (data['totalAlerts'] as int?)  ?? 0,
          lastAlertedAt: (data['lastAlertedAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
