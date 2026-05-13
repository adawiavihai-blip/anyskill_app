// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: AnySkill Pro — evaluateAnySkillProStatus decision logic
//
// Tests the BUSINESS LOGIC of the Pro badge evaluation using
// fake_cloud_firestore. Mirrors the production logic in lib/services/
// pro_service.dart (checkAndRefreshProStatus) and will match the
// forthcoming server-side Cloud Function `evaluateProStatus`.
//
// Covered edge cases (from the spec):
//   1) Boundary grant  — rating == 4.8 + 20 completed → SHOULD grant
//   2) Boundary deny   — rating == 4.79 → SHOULD NOT grant (even if
//                        orders/response/cancellations are perfect)
//   3) Immediate revoke — provider already holds the badge; a single
//                         expert-side cancellation in the last 30 days
//                         must revoke the badge.
//   4) Idempotency      — provider who already holds the badge and still
//                         meets every criterion → no write must happen
//                         on re-evaluation (so notifications/audit-log
//                         triggers don't fire twice).
//
// Run:  flutter test test/unit/pro_service_test.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── Fixture helpers ─────────────────────────────────────────────────────────

Future<void> _seedThresholds(FakeFirebaseFirestore db, {
  double minRating = 4.8,
  int    minOrders = 20,
  int    maxResponseMinutes = 15,
}) async {
  await db.collection('system_settings').doc('pro').set({
    'minRating':          minRating,
    'minOrders':          minOrders,
    'maxResponseMinutes': maxResponseMinutes,
  });
}

Future<void> _seedProvider(FakeFirebaseFirestore db, String uid, {
  required double rating,
  required int    avgResponseMinutes,
  bool isAnySkillPro = false,
  bool proManualOverride = false,
}) async {
  await db.collection('users').doc(uid).set({
    'name': 'Provider $uid',
    'isProvider': true,
    'rating': rating,
    'avgResponseMinutes': avgResponseMinutes,
    'isAnySkillPro': isAnySkillPro,
    'proManualOverride': proManualOverride,
  });
}

Future<void> _seedCompletedJobs(
  FakeFirebaseFirestore db,
  String expertId,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    await db.collection('jobs').doc('$expertId-completed-$i').set({
      'expertId': expertId,
      'status':   'completed',
      'totalAmount': 100,
    });
  }
}

/// Seeds a single expert-initiated cancellation [daysAgo] days before now.
Future<void> _seedExpertCancellation(
  FakeFirebaseFirestore db,
  String expertId, {
  int daysAgo = 5,
}) async {
  final cancelledAt =
      Timestamp.fromDate(DateTime.now().subtract(Duration(days: daysAgo)));
  await db.collection('jobs').add({
    'expertId': expertId,
    'status': 'cancelled',
    'cancelledBy': 'expert',
    'cancelledAt': cancelledAt,
    'totalAmount': 100,
  });
}

// ── Decision function under test ────────────────────────────────────────────
// Mirrors lib/services/pro_service.dart :: ProService.checkAndRefreshProStatus
// exactly. Returns the outcome of ONE evaluation pass:
//   { isPro: bool, wrote: bool }
// `wrote` is true when a Firestore write actually happened — used by the
// idempotency test to assert a no-op on stable state.

Future<_EvalOutcome> _evaluateAnySkillProStatus(
  FakeFirebaseFirestore db,
  String uid,
) async {
  if (uid.isEmpty) return const _EvalOutcome(isPro: false, wrote: false);

  final results = await Future.wait([
    db.collection('users').doc(uid).get(),
    db.collection('system_settings').doc('pro').get(),
    _countCompletedOrders(db, uid),
    _countRecentExpertCancellations(db, uid),
  ]);

  final userData = (results[0] as DocumentSnapshot).data()
          as Map<String, dynamic>? ??
      {};
  final thrDoc       = (results[1] as DocumentSnapshot).data()
          as Map<String, dynamic>? ??
      {};
  final completedCnt = results[2] as int;
  final cancelCnt    = results[3] as int;

  if (userData['proManualOverride'] == true) {
    return _EvalOutcome(
      isPro: userData['isAnySkillPro'] == true,
      wrote: false,
    );
  }

  final rating          = (userData['rating']             as num?)?.toDouble() ?? 0.0;
  final avgResponseMins = (userData['avgResponseMinutes'] as num?)?.toInt()    ?? 0;
  final minRating       = (thrDoc['minRating']            as num?)?.toDouble() ?? 4.8;
  final minOrders       = (thrDoc['minOrders']            as num?)?.toInt()    ?? 20;
  final maxResponseMins = (thrDoc['maxResponseMinutes']   as num?)?.toInt()    ?? 15;

  final responseOk = avgResponseMins == 0 || avgResponseMins <= maxResponseMins;

  final isPro = rating >= minRating &&
      completedCnt >= minOrders &&
      responseOk &&
      cancelCnt == 0;

  final wasPro = userData['isAnySkillPro'] == true;
  if (wasPro != isPro) {
    await db.collection('users').doc(uid).update({'isAnySkillPro': isPro});
    return _EvalOutcome(isPro: isPro, wrote: true);
  }
  return _EvalOutcome(isPro: isPro, wrote: false);
}

Future<int> _countCompletedOrders(FakeFirebaseFirestore db, String uid) async {
  final snap = await db
      .collection('jobs')
      .where('expertId', isEqualTo: uid)
      .where('status',   isEqualTo: 'completed')
      .get();
  return snap.docs.length;
}

Future<int> _countRecentExpertCancellations(
  FakeFirebaseFirestore db,
  String uid,
) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final snap = await db
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

class _EvalOutcome {
  final bool isPro;
  final bool wrote;
  const _EvalOutcome({required this.isPro, required this.wrote});
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('evaluateAnySkillProStatus — decision logic', () {
    test(
        'GRANT at lower bound: rating == 4.8 + exactly 20 completed jobs + '
        'zero cancellations + fast response', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_boundary_pass';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.8, avgResponseMinutes: 14, isAnySkillPro: false);
      await _seedCompletedJobs(db, uid, 20);

      final outcome = await _evaluateAnySkillProStatus(db, uid);

      expect(outcome.isPro, isTrue,
          reason: '4.8 (== threshold) + 20 orders (== threshold) must grant');
      expect(outcome.wrote, isTrue,
          reason: 'State transitioned false → true, must write');
      final after = await db.collection('users').doc(uid).get();
      expect(after.data()!['isAnySkillPro'], isTrue);
    });

    test(
        'DENY below rating boundary: rating == 4.79 must NOT grant even when '
        'all other criteria are perfect', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_boundary_fail';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.79, avgResponseMinutes: 10, isAnySkillPro: false);
      await _seedCompletedJobs(db, uid, 50); // well above 20

      final outcome = await _evaluateAnySkillProStatus(db, uid);

      expect(outcome.isPro, isFalse,
          reason: '4.79 < 4.8 — rating criterion fails, denial required');
      expect(outcome.wrote, isFalse,
          reason: 'State was already false, re-writing false is a no-op');
      final after = await db.collection('users').doc(uid).get();
      expect(after.data()!['isAnySkillPro'], isFalse);
    });

    test(
        'IMMEDIATE REVOKE: provider holds the badge and commits ONE expert-side '
        'cancellation in the last 30 days → badge must be revoked', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_revoke_on_cancel';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.9,
          avgResponseMinutes: 5,
          isAnySkillPro: true); // already Pro
      await _seedCompletedJobs(db, uid, 40);
      // One expert-initiated cancellation, 3 days ago
      await _seedExpertCancellation(db, uid, daysAgo: 3);

      final outcome = await _evaluateAnySkillProStatus(db, uid);

      expect(outcome.isPro, isFalse,
          reason:
              'Even with stellar rating/orders/response, 1 expert cancellation '
              'in 30d must revoke');
      expect(outcome.wrote, isTrue,
          reason: 'State transitioned true → false, write required');
      final after = await db.collection('users').doc(uid).get();
      expect(after.data()!['isAnySkillPro'], isFalse);
    });

    test(
        'IDEMPOTENCY: provider who already holds the badge and still meets '
        'every criterion → no Firestore write must fire on re-evaluation',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_idempotent';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.95,
          avgResponseMinutes: 3,
          isAnySkillPro: true); // already Pro, stable
      await _seedCompletedJobs(db, uid, 35);

      final outcome = await _evaluateAnySkillProStatus(db, uid);

      expect(outcome.isPro, isTrue,
          reason: 'All criteria still met, badge stays');
      expect(outcome.wrote, isFalse,
          reason:
              'No state change means no write — critical for downstream '
              'audit-log + notification triggers (no spam re-sends)');
      final after = await db.collection('users').doc(uid).get();
      expect(after.data()!['isAnySkillPro'], isTrue);
    });

    // ── Bonus safety net: expert cancellation > 30 days ago must NOT revoke ─
    test(
        'SAFETY: expert cancellation OLDER than 30 days does not revoke',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_old_cancel_ok';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.9,
          avgResponseMinutes: 4,
          isAnySkillPro: false);
      await _seedCompletedJobs(db, uid, 25);
      // Cancellation 60 days ago — outside the 30-day window
      await _seedExpertCancellation(db, uid, daysAgo: 60);

      final outcome = await _evaluateAnySkillProStatus(db, uid);

      expect(outcome.isPro, isTrue,
          reason: 'Cancellation outside 30-day window is ignored');
    });

    // ── Manual override must freeze automatic decisions ─────────────────────
    test(
        'MANUAL OVERRIDE: proManualOverride == true freezes the current badge '
        'state even when criteria say otherwise', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_manual_override';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 2.0,           // terrible rating
          avgResponseMinutes: 60, // slow
          isAnySkillPro: true,   // admin manually granted
          proManualOverride: true);
      // No completed jobs at all.

      final outcome = await _evaluateAnySkillProStatus(db, uid);

      expect(outcome.isPro, isTrue,
          reason: 'Manual override forces the badge to stay ON');
      expect(outcome.wrote, isFalse,
          reason: 'Automatic evaluation must NOT write when override active');
    });
  });
}
