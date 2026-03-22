import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages AnySkill Pro status.
///
/// Firestore:
///   system_settings/pro  — thresholds doc
///   users/{uid}          — isAnySkillPro: bool, proManualOverride: bool,
///                          avgResponseMinutes: int (optional, default = fast)
class ProService {
  ProService._();

  static final _db = FirebaseFirestore.instance;

  // ── Thresholds ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchThresholds() async {
    final doc = await _db.collection('system_settings').doc('pro').get();
    final d = doc.data() ?? {};
    return {
      'minRating':           (d['minRating']           as num?)?.toDouble() ?? 4.8,
      'minOrders':           (d['minOrders']           as num?)?.toInt()    ?? 20,
      'maxResponseMinutes':  (d['maxResponseMinutes']  as num?)?.toInt()    ?? 15,
    };
  }

  static Stream<Map<String, dynamic>> streamThresholds() =>
      _db.collection('system_settings').doc('pro').snapshots().map((s) {
        final d = s.data() ?? {};
        return {
          'minRating':          (d['minRating']          as num?)?.toDouble() ?? 4.8,
          'minOrders':          (d['minOrders']          as num?)?.toInt()    ?? 20,
          'maxResponseMinutes': (d['maxResponseMinutes'] as num?)?.toInt()    ?? 15,
        };
      });

  static Future<void> saveThresholds({
    required double minRating,
    required int    minOrders,
    required int    maxResponseMinutes,
  }) =>
      _db.collection('system_settings').doc('pro').set({
        'minRating':          minRating,
        'minOrders':          minOrders,
        'maxResponseMinutes': maxResponseMinutes,
      }, SetOptions(merge: true));

  // ── Eligibility check ─────────────────────────────────────────────────────

  /// Evaluates [uid] against current thresholds and writes `isAnySkillPro`
  /// back to the user document. Returns the computed value.
  /// Skips the write (and returns current value) when admin has manually overridden.
  static Future<bool> checkAndRefreshProStatus(String uid) async {
    if (uid.isEmpty) return false;

    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      fetchThresholds(),
      _countCompletedOrders(uid),
      _countRecentExpertCancellations(uid),
    ]);

    final userData = (results[0] as DocumentSnapshot).data()
            as Map<String, dynamic>? ??
        {};
    final thresholds    = results[1] as Map<String, dynamic>;
    final completedCnt  = results[2] as int;
    final cancelCnt     = results[3] as int;

    // Admin manual override — don't touch the flag
    if (userData['proManualOverride'] == true) {
      return userData['isAnySkillPro'] == true;
    }

    final rating            = (userData['rating']              as num?)?.toDouble() ?? 0.0;
    final avgResponseMins   = (userData['avgResponseMinutes']  as num?)?.toInt()    ?? 0;
    final minRating         = thresholds['minRating']          as double;
    final minOrders         = thresholds['minOrders']          as int;
    final maxResponseMins   = thresholds['maxResponseMinutes'] as int;

    // avgResponseMinutes == 0 → no data yet → don't penalise
    final responseOk = avgResponseMins == 0 || avgResponseMins <= maxResponseMins;

    final isPro = rating >= minRating &&
        completedCnt >= minOrders &&
        responseOk &&
        cancelCnt == 0;

    await _db.collection('users').doc(uid).update({'isAnySkillPro': isPro});
    return isPro;
  }

  // ── Manual override ───────────────────────────────────────────────────────

  /// Admin grants or revokes Pro manually. Sets `proManualOverride: true` so
  /// the automatic check won't overwrite the decision.
  static Future<void> setManualOverride(String uid, {required bool isPro}) =>
      _db.collection('users').doc(uid).update({
        'isAnySkillPro':      isPro,
        'proManualOverride':  true,
      });

  /// Removes the manual override so automatic checks resume.
  static Future<void> clearManualOverride(String uid) =>
      _db.collection('users').doc(uid).update({
        'proManualOverride': false,
      });

  // ── Provider metrics snapshot ─────────────────────────────────────────────

  /// Returns a full [ProMetrics] snapshot for the given [uid].
  /// Used by the provider-facing AI insights screen.
  static Future<ProMetrics> fetchProviderMetrics(String uid) async {
    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      fetchThresholds(),
      _countCompletedOrders(uid),
      _countRecentExpertCancellations(uid),
    ]);

    final userData      = (results[0] as DocumentSnapshot).data()
            as Map<String, dynamic>? ?? {};
    final thresholds    = results[1] as Map<String, dynamic>;
    final completedCnt  = results[2] as int;
    final cancelCnt     = results[3] as int;

    return ProMetrics(
      rating:                 (userData['rating']             as num?)?.toDouble() ?? 0.0,
      avgResponseMinutes:     (userData['avgResponseMinutes'] as num?)?.toInt()    ?? 0,
      completedOrders:        completedCnt,
      recentCancellations:    cancelCnt,
      isManualOverride:       userData['proManualOverride']  == true,
      isAnySkillPro:          userData['isAnySkillPro']      == true,
      thresholdMinRating:     thresholds['minRating']        as double,
      thresholdMinOrders:     thresholds['minOrders']        as int,
      thresholdMaxResponseMins: thresholds['maxResponseMinutes'] as int,
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static Future<int> _countCompletedOrders(String uid) async {
    final snap = await _db
        .collection('jobs')
        .where('expertId', isEqualTo: uid)
        .where('status',   isEqualTo: 'completed')
        .get();
    return snap.docs.length;
  }

  /// Counts jobs where the expert cancelled within the last 30 days.
  /// Filters cancelledBy + cancelledAt client-side to avoid composite indexes.
  static Future<int> _countRecentExpertCancellations(String uid) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final snap = await _db
        .collection('jobs')
        .where('expertId', isEqualTo: uid)
        .where('status',   isEqualTo: 'cancelled')
        .get();
    int count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['cancelledBy'] != 'expert') continue;
      final ts = d['cancelledAt'];
      DateTime? cancelledAt;
      if (ts is Timestamp) cancelledAt = ts.toDate();
      if (cancelledAt != null && cancelledAt.isAfter(cutoff)) count++;
    }
    return count;
  }
}

// ── Provider metrics snapshot ─────────────────────────────────────────────────

class ProMetrics {
  final double rating;
  final int    avgResponseMinutes;
  final int    completedOrders;
  final int    recentCancellations;
  final bool   isManualOverride;
  final bool   isAnySkillPro;
  final double thresholdMinRating;
  final int    thresholdMinOrders;
  final int    thresholdMaxResponseMins;

  const ProMetrics({
    required this.rating,
    required this.avgResponseMinutes,
    required this.completedOrders,
    required this.recentCancellations,
    required this.isManualOverride,
    required this.isAnySkillPro,
    required this.thresholdMinRating,
    required this.thresholdMinOrders,
    required this.thresholdMaxResponseMins,
  });

  bool get ratingOk    => rating >= thresholdMinRating;
  bool get ordersOk    => completedOrders >= thresholdMinOrders;
  bool get responseOk  => avgResponseMinutes == 0 || avgResponseMinutes <= thresholdMaxResponseMins;
  bool get cancelOk    => recentCancellations == 0;
  bool get eligibleForPro => ratingOk && ordersOk && responseOk && cancelOk;

  /// 0.0–1.0 overall progress toward Pro (average of 4 criteria).
  double get overallProgress {
    double score = 0;
    score += ratingOk    ? 1.0 : (rating / thresholdMinRating).clamp(0.0, 1.0);
    score += ordersOk    ? 1.0 : (completedOrders / thresholdMinOrders).clamp(0.0, 1.0);
    score += responseOk  ? 1.0 : 0.3;  // partial credit for response time
    score += cancelOk    ? 1.0 : 0.0;
    return score / 4.0;
  }
}
