import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/monetization/provider_commission_table.dart';

/// Loads every provider + GMV aggregation + health score for the
/// "ספקים — שליטה ובריאות" table (section 7).
///
/// Cost profile (per CLAUDE.md Section 17 Rule 1-3):
///   • 1 query for `users where isProvider=true` (limit 500)
///   • 1 query for `jobs where completedAt >= 30d ago` (limit 2000)
///   • 1 query for `monetization_alerts where resolved=false` (limit 500)
///   • 1 query for `category_commissions` (small collection)
/// Total: 4 reads regardless of provider count. Call `load()` on mount
/// and refresh on a 60-second cadence alongside the KPI snapshot.
class MonetizationProviderService {
  MonetizationProviderService._();

  static final _db = FirebaseFirestore.instance;

  static Future<List<ProviderTableRow>> load({
    required double globalPct,
  }) async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final results = await Future.wait([
      _db
          .collection('users')
          .where('isProvider', isEqualTo: true)
          .limit(500)
          .get(),
      _db
          .collection('jobs')
          .where('completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .limit(2000)
          .get(),
      _db
          .collection('monetization_alerts')
          .where('resolved', isEqualTo: false)
          .limit(500)
          .get(),
      _db.collection('category_commissions').get(),
    ]);

    final usersSnap = results[0];
    final jobsSnap = results[1];
    final alertsSnap = results[2];
    final catCommissionsSnap = results[3];

    // ── Index: category name → pct override ────────────────────────────
    final categoryPct = <String, double>{};
    for (final d in catCommissionsSnap.docs) {
      final p = (d.data()['percentage'] as num?)?.toDouble();
      if (p != null) categoryPct[d.id] = p;
    }

    // ── Index: aggregated GMV + job counts per provider ────────────────
    final gmvPerUid = <String, double>{};
    final jobCountPerUid = <String, int>{};
    final cancelledPerUid = <String, int>{};
    for (final d in jobsSnap.docs) {
      final data = d.data();
      final uid = (data['expertId'] ?? '').toString();
      if (uid.isEmpty) continue;
      final status = (data['status'] ?? '').toString();
      final amount = ((data['totalAmount'] ?? 0) as num).toDouble();

      if (status == 'completed') {
        gmvPerUid.update(uid, (v) => v + amount, ifAbsent: () => amount);
        jobCountPerUid.update(uid, (v) => v + 1, ifAbsent: () => 1);
      } else if (status == 'cancelled' ||
          status == 'cancelled_with_penalty' ||
          status == 'refunded') {
        cancelledPerUid.update(uid, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    // ── Index: churn-risk / anomaly flags per uid ──────────────────────
    final churnUids = <String>{};
    final anomalyUids = <String>{};
    for (final d in alertsSnap.docs) {
      final data = d.data();
      if ((data['entityType'] ?? '').toString() != 'user') continue;
      final uid = (data['entityId'] ?? '').toString();
      if (uid.isEmpty) continue;
      final type = (data['type'] ?? '').toString();
      if (type == 'churn_risk') churnUids.add(uid);
      if (type == 'anomaly') anomalyUids.add(uid);
    }

    // ── Top 10% by GMV threshold ───────────────────────────────────────
    final gmvs = gmvPerUid.values.toList()..sort();
    final topThreshold = gmvs.isEmpty
        ? double.infinity
        : gmvs[(gmvs.length * 0.9).floor().clamp(0, gmvs.length - 1)];

    // ── Build rows ─────────────────────────────────────────────────────
    final rows = <ProviderTableRow>[];
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final uid = doc.id;
      final category = (data['serviceType'] ?? '').toString();

      // Effective pct (custom → category → global)
      double effectivePct;
      String source;
      final customActive = data['customCommissionActive'] == true;
      final custom = data['customCommission'];
      if (customActive && custom is Map) {
        final pct = (custom['percentage'] as num?)?.toDouble();
        if (pct != null) {
          effectivePct = pct;
          source = 'custom';
        } else if (categoryPct.containsKey(category)) {
          effectivePct = categoryPct[category]!;
          source = 'category';
        } else {
          effectivePct = globalPct;
          source = 'global';
        }
      } else if (categoryPct.containsKey(category)) {
        effectivePct = categoryPct[category]!;
        source = 'category';
      } else {
        effectivePct = globalPct;
        source = 'global';
      }

      final gmv30d = gmvPerUid[uid] ?? 0;
      final completedJobs30d = jobCountPerUid[uid] ?? 0;
      final cancelled30d = cancelledPerUid[uid] ?? 0;
      final rating = ((data['rating'] ?? 5) as num).toDouble();
      final lifetimeOrders =
          ((data['orderCount'] ?? 0) as num).toInt();
      final lastActive = _toDate(
        data['lastActiveAt'] ?? data['lastOnlineAt'] ?? data['lastSeen'],
      );
      final daysSinceActive = lastActive == null
          ? 999
          : now.difference(lastActive).inDays;

      final health = _healthScore(
        completedJobs30d: completedJobs30d,
        cancelled30d: cancelled30d,
        rating: rating,
        daysSinceActive: daysSinceActive,
      );

      final isChurn = churnUids.contains(uid) || daysSinceActive >= 14;
      final isTop = gmv30d >= topThreshold && gmv30d > 0;
      final isVip = data['isPromoted'] == true;

      rows.add(ProviderTableRow(
        uid: uid,
        name: (data['name'] ?? uid).toString(),
        avatarUrl: data['profileImage']?.toString(),
        category: category.isEmpty ? '—' : category,
        gmv30d: gmv30d,
        effectivePct: effectivePct,
        commissionSource: source,
        healthScore: health,
        isVip: isVip,
        isChurnRisk: isChurn,
        isTopPerformer: isTop,
        completedJobs: lifetimeOrders,
        joinedAt: data['createdAt'] is Timestamp
            ? data['createdAt'] as Timestamp
            : null,
        trendLast7Days: const [],
      ));
    }

    // Sort by GMV descending so the UI opens on "most important first".
    rows.sort((a, b) => b.gmv30d.compareTo(a.gmv30d));
    return rows;
  }

  /// Spec's formula, tuned for the fields we actually have.
  ///
  /// Starts at 50, adjusts based on recent activity, rating, cancellations,
  /// and recency of last login.
  static double _healthScore({
    required int completedJobs30d,
    required int cancelled30d,
    required double rating,
    required int daysSinceActive,
  }) {
    double score = 50;

    // Recent activity — up to +20
    score += (completedJobs30d / 30 * 20).clamp(0, 20);

    // Rating — up to +15
    score += (rating / 5 * 15).clamp(0, 15);

    // Cancellations — cancelRate = cancels / (cancels+completed), up to -15
    final totalJobs = completedJobs30d + cancelled30d;
    final cancelRate = totalJobs == 0 ? 0 : cancelled30d / totalJobs;
    score -= (cancelRate * 15).clamp(0, 15);

    // Inactivity penalty
    if (daysSinceActive > 14) {
      score -= 20;
    } else if (daysSinceActive > 7) {
      score -= 10;
    }

    return score.clamp(0, 100);
  }

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
