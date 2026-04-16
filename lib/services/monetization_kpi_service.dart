import 'package:cloud_firestore/cloud_firestore.dart';

/// Cached aggregations powering the 4 KPI cards (Section 3 of the
/// Monetization tab). Built with one-shot `.get()` queries — no streams —
/// per CLAUDE.md Section 17 Rule 3 (reads that don't need sub-second
/// freshness should use `.get()` with caching).
///
/// Refresh cadence is controlled by the caller; the tab invokes
/// [load] on mount and then every 60 seconds via a `Timer.periodic`.
class MonetizationKpiService {
  MonetizationKpiService._();

  static final _db = FirebaseFirestore.instance;

  /// Main entry point. Runs ~6 queries in parallel and packages the
  /// result into a [MonetizationKpis] snapshot.
  static Future<MonetizationKpis> load() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final prevMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
    final last30Days = now.subtract(const Duration(days: 30));

    // ── Parallel reads ──────────────────────────────────────────────────
    final results = await Future.wait([
      _db
          .collection('platform_earnings')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .limit(500)
          .get(),
      _db
          .collection('platform_earnings')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(prevMonthStart))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(prevMonthEnd))
          .limit(500)
          .get(),
      _db
          .collection('platform_earnings')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(last30Days))
          .orderBy('timestamp')
          .limit(1000)
          .get(),
      _db
          .collection('jobs')
          .where('status', isEqualTo: 'paid_escrow')
          .limit(200)
          .get(),
      _db
          .collection('users')
          .where('customCommissionActive', isEqualTo: true)
          .limit(200)
          .get(),
      _db
          .collection('transactions')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(last30Days))
          .limit(2000)
          .get(),
    ]);

    final thisMonthEarnings = results[0];
    final prevMonthEarnings = results[1];
    final last30EarningsSnap = results[2];
    final escrowSnap = results[3];
    final customSnap = results[4];
    final last30TxSnap = results[5];

    // ── KPI 1: month earnings + delta + projection ──────────────────────
    double month = 0;
    double monthGmv = 0;
    for (final d in thisMonthEarnings.docs) {
      final data = d.data();
      final fee =
          ((data['platformFee'] ?? data['amount'] ?? 0) as num).toDouble();
      final gmv = ((data['sourceAmount'] ?? data['amount'] ?? 0) as num)
          .toDouble();
      month += fee;
      monthGmv += gmv;
    }

    double prevMonth = 0;
    for (final d in prevMonthEarnings.docs) {
      final data = d.data();
      final fee =
          ((data['platformFee'] ?? data['amount'] ?? 0) as num).toDouble();
      prevMonth += fee;
    }

    // Linear projection: earnings so far × (daysInMonth / daysPassed).
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed = now.day.clamp(1, daysInMonth);
    final projection = month / daysPassed * daysInMonth;
    final monthDeltaPct =
        prevMonth > 0 ? ((month - prevMonth) / prevMonth) * 100 : 0.0;

    // ── Sparkline: sum earnings per day for the last 30 days ────────────
    final spark = _buildDailySparkline(last30EarningsSnap.docs, now);

    // ── KPI 2: escrow total + oldest wait ───────────────────────────────
    double escrowTotal = 0;
    final waits = <Duration>[];
    for (final d in escrowSnap.docs) {
      final data = d.data();
      escrowTotal += ((data['totalAmount'] ?? 0) as num).toDouble();
      final ts = data['createdAt'];
      if (ts is Timestamp) waits.add(now.difference(ts.toDate()));
    }
    final escrowCount = escrowSnap.size;
    final avgWait = waits.isEmpty
        ? Duration.zero
        : Duration(
            minutes:
                waits.map((w) => w.inMinutes).reduce((a, b) => a + b) ~/
                    waits.length,
          );

    // ── KPI 3: weighted effective fee % ─────────────────────────────────
    final weightedFeePct = monthGmv > 0 ? (month / monthGmv) * 100 : 0.0;

    // ── KPI 4: custom commissions ───────────────────────────────────────
    final customCount = customSnap.size;
    // Revenue-share from custom-commission providers:
    // (sum platform_earnings by sourceExpertId within custom set) / total month earnings.
    final customUids =
        customSnap.docs.map((d) => d.id).toSet();
    double customRevenue = 0;
    final customRevenuesPerUser = <String, double>{};
    for (final d in thisMonthEarnings.docs) {
      final data = d.data();
      final uid = (data['sourceExpertId'] ?? '').toString();
      if (customUids.contains(uid)) {
        final fee =
            ((data['platformFee'] ?? data['amount'] ?? 0) as num).toDouble();
        customRevenue += fee;
        customRevenuesPerUser.update(uid, (v) => v + fee,
            ifAbsent: () => fee);
      }
    }
    final customShare = month > 0 ? customRevenue / month : 0.0;
    final topCustomRevenues = customRevenuesPerUser.values.toList()
      ..sort((a, b) => b.compareTo(a));

    // ── Revenue chart series ────────────────────────────────────────────
    // 3 lines: current-month daily, prev-month daily, projection tail.
    final daysInPrevMonth =
        DateTime(prevMonthStart.year, prevMonthStart.month + 1, 0).day;

    final currentDaily = _dailyBuckets(
      docs: thisMonthEarnings.docs,
      bucketCount: daysInMonth,
    );
    final prevDaily = _dailyBuckets(
      docs: prevMonthEarnings.docs,
      bucketCount: daysInPrevMonth,
    );

    // Projection: after today's day, extrapolate the remaining buckets
    // using the current month's daily average so far.
    final projectionDaily = List<double>.filled(daysInMonth, 0);
    final cumulativeSoFar =
        currentDaily.take(daysPassed).fold<double>(0, (a, b) => a + b);
    final dailyRate =
        daysPassed > 0 ? cumulativeSoFar / daysPassed : 0.0;
    // Anchor the projection line at today's cumulative sum (so it starts
    // from where the solid line ends) and step forward at `dailyRate`.
    final anchorIdx = (daysPassed - 1).clamp(0, daysInMonth - 1);
    projectionDaily[anchorIdx] =
        currentDaily[anchorIdx] == 0
            ? dailyRate
            : currentDaily[anchorIdx];
    for (int i = anchorIdx + 1; i < daysInMonth; i++) {
      projectionDaily[i] = projectionDaily[i - 1] + dailyRate;
    }

    // Peak day of current month (for annotation)
    int peakDay = 0;
    double peakValue = 0;
    for (int i = 0; i < currentDaily.length; i++) {
      if (currentDaily[i] > peakValue) {
        peakValue = currentDaily[i];
        peakDay = i + 1;
      }
    }

    // ── Heatmap: day-of-week × hour-bucket from last 30d transactions ───
    // 4 buckets (08/12/16/20) × 7 days (Sun..Sat). Counts tx volume.
    final heatmap = List.generate(4, (_) => List<double>.filled(7, 0));
    for (final d in last30TxSnap.docs) {
      final data = d.data();
      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      // Flutter: weekday 1=Mon..7=Sun. Hebrew calendar: 0=Sun..6=Sat.
      final hebrewDay = dt.weekday % 7;
      final hourBucket = _hourBucket(dt.hour);
      heatmap[hourBucket][hebrewDay] += 1;
    }
    // Peak bucket insight
    int peakRow = 0, peakCol = 0;
    double peakCount = 0;
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 7; c++) {
        if (heatmap[r][c] > peakCount) {
          peakCount = heatmap[r][c];
          peakRow = r;
          peakCol = c;
        }
      }
    }
    String? heatmapInsight;
    if (peakCount > 0) {
      const hourLabels = ['08:00', '12:00', '16:00', '20:00'];
      const dayLabels = ['ראשון', 'שני', 'שלישי', 'רביעי',
          'חמישי', 'שישי', 'שבת'];
      heatmapInsight =
          'שיא הפעילות: יום ${dayLabels[peakCol]} בשעות ${hourLabels[peakRow]}-'
          '${hourLabels[(peakRow + 1) % 4]} (${peakCount.toInt()} עסקאות). '
          'שקול תוספת דחיפות של +2-3% בחלון זה.';
    }

    return MonetizationKpis(
      monthEarnings: month,
      prevMonthEarnings: prevMonth,
      monthDeltaPct: monthDeltaPct,
      projectedEndOfMonth: projection,
      dailyEarningsSparkline: spark,
      escrowTotal: escrowTotal,
      escrowCount: escrowCount,
      avgEscrowWait: avgWait,
      escrowWaitTimes: waits,
      weightedFeePct: weightedFeePct,
      customCommissionCount: customCount,
      customCommissionRevenueShare: customShare,
      topCustomProviderRevenues:
          topCustomRevenues.take(8).toList(),
      currentMonthDaily: currentDaily,
      prevMonthDaily: prevDaily,
      projectionDaily: projectionDaily,
      peakDayOfMonth: peakDay,
      peakDayValue: peakValue,
      heatmap: heatmap,
      heatmapInsight: heatmapInsight,
    );
  }

  /// Groups `platform_earnings` docs into day-of-month buckets (1..bucketCount).
  /// Used by the revenue chart for current + prev month series.
  static List<double> _dailyBuckets({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required int bucketCount,
  }) {
    final buckets = List<double>.filled(bucketCount, 0);
    for (final d in docs) {
      final data = d.data();
      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;
      final day = ts.toDate().day; // 1..31
      final idx = day - 1;
      if (idx < 0 || idx >= bucketCount) continue;
      final fee =
          ((data['platformFee'] ?? data['amount'] ?? 0) as num).toDouble();
      buckets[idx] += fee;
    }
    return buckets;
  }

  /// Maps an hour (0..23) into the 4 heatmap rows.
  ///   0 → 08:00-12:00 (morning)
  ///   1 → 12:00-16:00 (afternoon)
  ///   2 → 16:00-20:00 (evening)
  ///   3 → 20:00-08:00 (night)
  static int _hourBucket(int hour) {
    if (hour >= 8 && hour < 12) return 0;
    if (hour >= 12 && hour < 16) return 1;
    if (hour >= 16 && hour < 20) return 2;
    return 3;
  }

  static List<double> _buildDailySparkline(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) {
    // 30 buckets, oldest → newest.
    final buckets = List<double>.filled(30, 0);
    for (final d in docs) {
      final data = d.data();
      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;
      final daysAgo = now.difference(ts.toDate()).inDays;
      final idx = 29 - daysAgo;
      if (idx < 0 || idx >= 30) continue;
      final fee =
          ((data['platformFee'] ?? data['amount'] ?? 0) as num).toDouble();
      buckets[idx] += fee;
    }
    return buckets;
  }
}

// ─────────────────────────────────────────────────────────────────────────

class MonetizationKpis {
  final double monthEarnings;
  final double prevMonthEarnings;
  final double monthDeltaPct;
  final double projectedEndOfMonth;
  final List<double> dailyEarningsSparkline;

  final double escrowTotal;
  final int escrowCount;
  final Duration avgEscrowWait;
  final List<Duration> escrowWaitTimes;

  final double weightedFeePct;

  final int customCommissionCount;
  final double customCommissionRevenueShare; // 0-1
  final List<double> topCustomProviderRevenues;

  // ── Revenue chart (section 6 / stage 6) ────────────────────────────
  final List<double> currentMonthDaily; // day 1..daysInMonth
  final List<double> prevMonthDaily;    // prev month buckets
  final List<double> projectionDaily;   // linear projection tail
  final int peakDayOfMonth;             // 1..daysInMonth (0 = none)
  final double peakDayValue;

  // ── Heatmap (4 hour-buckets × 7 days) ──────────────────────────────
  final List<List<double>> heatmap;
  final String? heatmapInsight;

  const MonetizationKpis({
    required this.monthEarnings,
    required this.prevMonthEarnings,
    required this.monthDeltaPct,
    required this.projectedEndOfMonth,
    required this.dailyEarningsSparkline,
    required this.escrowTotal,
    required this.escrowCount,
    required this.avgEscrowWait,
    required this.escrowWaitTimes,
    required this.weightedFeePct,
    required this.customCommissionCount,
    required this.customCommissionRevenueShare,
    required this.topCustomProviderRevenues,
    required this.currentMonthDaily,
    required this.prevMonthDaily,
    required this.projectionDaily,
    required this.peakDayOfMonth,
    required this.peakDayValue,
    required this.heatmap,
    required this.heatmapInsight,
  });

  factory MonetizationKpis.empty() => const MonetizationKpis(
        monthEarnings: 0,
        prevMonthEarnings: 0,
        monthDeltaPct: 0,
        projectedEndOfMonth: 0,
        dailyEarningsSparkline: [],
        escrowTotal: 0,
        escrowCount: 0,
        avgEscrowWait: Duration.zero,
        escrowWaitTimes: [],
        weightedFeePct: 0,
        customCommissionCount: 0,
        customCommissionRevenueShare: 0,
        topCustomProviderRevenues: [],
        currentMonthDaily: [],
        prevMonthDaily: [],
        projectionDaily: [],
        peakDayOfMonth: 0,
        peakDayValue: 0,
        heatmap: [],
        heatmapInsight: null,
      );
}
