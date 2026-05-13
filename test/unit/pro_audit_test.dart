// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: AnySkill Pro — audit log shape + previousGrantedAt + reasons
//
// Mirrors functions/pro_service.js :: evaluateProStatus (the server-side
// helper called by every Pro trigger/callable). The logic under test is
// embedded below so the Dart test can exercise it against
// fake_cloud_firestore without a live Node runtime.
//
// Verified invariants:
//   1. A grant writes an `admin_audit_log` entry with:
//        action = 'pro_granted'
//        targetUserId = uid
//        source       = 'auto' (or caller-provided)
//        metricsSnapshot.* populated
//        previousGrantedAt = null on FIRST grant
//   2. A re-grant (revoke → grant cycle) carries the OLD grant timestamp
//      in `previousGrantedAt`.
//   3. A revoke writes an entry with `revocationReason` populated by the
//      FIRST failing criterion in this order:
//          expert_cancellation_30d → rating_below_threshold
//          → insufficient_orders   → slow_response
//   4. Idempotent no-op evaluations write NO audit-log row.
//   5. Manual-override providers write NO audit-log row.
//
// Run:  flutter test test/unit/pro_audit_test.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── Fixture helpers (identical to pro_service_test.dart) ────────────────────

Future<void> _seedThresholds(FakeFirebaseFirestore db, {
  double minRating = 4.8,
  int    minOrders = 20,
  int    maxResponseMinutes = 15,
}) =>
    db.collection('system_settings').doc('pro').set({
      'minRating':          minRating,
      'minOrders':          minOrders,
      'maxResponseMinutes': maxResponseMinutes,
    });

Future<void> _seedProvider(FakeFirebaseFirestore db, String uid, {
  required double rating,
  required int    avgResponseMinutes,
  bool   isAnySkillPro = false,
  bool   proManualOverride = false,
  String name = 'Test Provider',
  Timestamp? anySkillProGrantedAt,
}) async {
  final data = <String, dynamic>{
    'name': name,
    'isProvider': true,
    'rating': rating,
    'avgResponseMinutes': avgResponseMinutes,
    'isAnySkillPro': isAnySkillPro,
    'proManualOverride': proManualOverride,
  };
  if (anySkillProGrantedAt != null) {
    data['anySkillProGrantedAt'] = anySkillProGrantedAt;
  }
  await db.collection('users').doc(uid).set(data);
}

Future<void> _seedCompletedJobs(
  FakeFirebaseFirestore db,
  String expertId,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    await db.collection('jobs').doc('$expertId-c-$i').set({
      'expertId': expertId,
      'status':   'completed',
    });
  }
}

Future<void> _seedExpertCancellation(
  FakeFirebaseFirestore db,
  String expertId, {
  int daysAgo = 5,
}) async {
  await db.collection('jobs').add({
    'expertId':    expertId,
    'status':      'cancelled',
    'cancelledBy': 'expert',
    'cancelledAt': Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: daysAgo)),
    ),
  });
}

// ── Logic under test — mirrors functions/pro_service.js exactly ─────────────
// Writes the user doc update AND the admin_audit_log entry. Returns the
// resolved state for inspection.

Future<Map<String, dynamic>> _evaluateProStatusWithAudit(
  FakeFirebaseFirestore db,
  String uid, {
  String source = 'auto',
  String? triggerReason,
  String? adminUid,
}) async {
  if (uid.isEmpty) return {'transition': 'unchanged', 'skipped': 'empty-uid'};

  final userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) return {'transition': 'unchanged', 'skipped': 'no-user'};
  final userData = userSnap.data() ?? {};

  if (userData['proManualOverride'] == true) {
    return {
      'transition': 'manual_override_skip',
      'isPro': userData['isAnySkillPro'] == true,
    };
  }

  final thrSnap = await db.collection('system_settings').doc('pro').get();
  final thr = thrSnap.data() ?? {};
  final minRating       = (thr['minRating']          as num?)?.toDouble() ?? 4.8;
  final minOrders       = (thr['minOrders']           as num?)?.toInt()    ?? 20;
  final maxResponseMins = (thr['maxResponseMinutes']  as num?)?.toInt()    ?? 15;

  final completedCnt = (await db.collection('jobs')
          .where('expertId', isEqualTo: uid)
          .where('status',   isEqualTo: 'completed').get())
      .size;
  final cancelCutoff = DateTime.now().subtract(const Duration(days: 30));
  final cancelSnap = await db.collection('jobs')
      .where('expertId', isEqualTo: uid)
      .where('status',   isEqualTo: 'cancelled').get();
  int cancelCnt = 0;
  for (final d in cancelSnap.docs) {
    final j = d.data();
    if (j['cancelledBy'] != 'expert') continue;
    final ts = j['cancelledAt'];
    if (ts is Timestamp && ts.toDate().isAfter(cancelCutoff)) cancelCnt++;
  }

  final rating          = (userData['rating']             as num?)?.toDouble() ?? 0.0;
  final avgResponseMins = (userData['avgResponseMinutes'] as num?)?.toInt()    ?? 0;
  final responseOk      = avgResponseMins == 0 || avgResponseMins <= maxResponseMins;

  final isPro = rating >= minRating &&
      completedCnt >= minOrders &&
      responseOk &&
      cancelCnt == 0;
  final wasPro = userData['isAnySkillPro'] == true;
  if (wasPro == isPro) return {'transition': 'unchanged', 'isPro': isPro};

  // State transition — write doc + audit.
  final previousGrantedAt = userData['anySkillProGrantedAt'];
  final update = <String, dynamic>{'isAnySkillPro': isPro};
  if (isPro) {
    update['anySkillProGrantedAt'] = Timestamp.now();
  }
  await db.collection('users').doc(uid).update(update);

  String? revokeReason;
  if (!isPro) {
    if (cancelCnt > 0) {
      revokeReason = 'expert_cancellation_30d (count=$cancelCnt)';
    } else if (rating < minRating) {
      revokeReason =
          'rating_below_threshold (current=${rating.toStringAsFixed(2)}, min=$minRating)';
    } else if (completedCnt < minOrders) {
      revokeReason =
          'insufficient_orders (current=$completedCnt, min=$minOrders)';
    } else if (avgResponseMins > maxResponseMins) {
      revokeReason =
          'slow_response (current=${avgResponseMins}min, max=${maxResponseMins}min)';
    } else {
      revokeReason = 'unknown';
    }
  }

  await db.collection('admin_audit_log').add({
    'action':           isPro ? 'pro_granted' : 'pro_revoked',
    'targetUserId':     uid,
    'targetUserName':   userData['name'],
    'source':           source,
    'triggerReason':    triggerReason,
    'adminUid':         adminUid,
    'revocationReason': revokeReason,
    'metricsSnapshot': {
      'rating':              rating,
      'completedOrders':     completedCnt,
      'avgResponseMinutes':  avgResponseMins,
      'recentCancellations': cancelCnt,
      'thresholds': {
        'minRating':          minRating,
        'minOrders':          minOrders,
        'maxResponseMinutes': maxResponseMins,
      },
    },
    'previousGrantedAt': previousGrantedAt,
    'createdAt':         Timestamp.now(),
  });

  return {
    'transition':  isPro ? 'granted' : 'revoked',
    'isPro':       isPro,
    'revokeReason': revokeReason,
  };
}

Future<List<Map<String, dynamic>>> _auditFor(
  FakeFirebaseFirestore db,
  String uid,
) async {
  final snap = await db
      .collection('admin_audit_log')
      .where('targetUserId', isEqualTo: uid)
      .get();
  return snap.docs.map((d) => d.data()).toList();
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('Pro audit log — invariants', () {
    test('FIRST grant: audit entry has action="pro_granted", null previousGrantedAt',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_first_grant';

      await _seedThresholds(db);
      await _seedProvider(db, uid, rating: 4.9, avgResponseMinutes: 10);
      await _seedCompletedJobs(db, uid, 25);

      final out = await _evaluateProStatusWithAudit(
        db, uid,
        source: 'auto',
        triggerReason: 'job_completed:JOB_123',
      );
      expect(out['transition'], equals('granted'));

      final audit = await _auditFor(db, uid);
      expect(audit, hasLength(1));
      final entry = audit.first;
      expect(entry['action'],           equals('pro_granted'));
      expect(entry['targetUserId'],     equals(uid));
      expect(entry['source'],           equals('auto'));
      expect(entry['triggerReason'],    equals('job_completed:JOB_123'));
      expect(entry['previousGrantedAt'], isNull);
      expect(entry['revocationReason'], isNull);
      final metrics = entry['metricsSnapshot'] as Map;
      expect(metrics['rating'],              equals(4.9));
      expect(metrics['completedOrders'],     equals(25));
      expect(metrics['recentCancellations'], equals(0));
    });

    test('RE-GRANT: audit entry carries OLD grant timestamp in previousGrantedAt',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_regrant';
      final oldGrant = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 60)),
      );

      // Provider previously held the badge (with timestamp) but is currently
      // revoked (isAnySkillPro == false). Now meets all 4 criteria again.
      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.85,
          avgResponseMinutes: 8,
          isAnySkillPro: false,
          anySkillProGrantedAt: oldGrant);
      await _seedCompletedJobs(db, uid, 22);

      final out = await _evaluateProStatusWithAudit(db, uid, source: 'cron');
      expect(out['transition'], equals('granted'));

      final audit = await _auditFor(db, uid);
      expect(audit, hasLength(1));
      expect(audit.first['previousGrantedAt'], equals(oldGrant),
          reason: 'The OLD grant timestamp must be preserved on re-grant');
    });

    test('REVOKE reason priority: cancellation takes precedence over rating/orders/response',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_revoke_cancel';
      await _seedThresholds(db);
      // Simultaneously fails rating (4.5 < 4.8), orders (10 < 20), AND has
      // a cancellation. Cancellation must win in the reason priority.
      await _seedProvider(db, uid,
          rating: 4.5,
          avgResponseMinutes: 30, // also slow
          isAnySkillPro: true);
      await _seedCompletedJobs(db, uid, 10);
      await _seedExpertCancellation(db, uid, daysAgo: 2);

      await _evaluateProStatusWithAudit(db, uid);
      final audit = await _auditFor(db, uid);
      expect(audit, hasLength(1));
      expect(audit.first['action'], equals('pro_revoked'));
      expect(audit.first['revocationReason'],
          startsWith('expert_cancellation_30d'),
          reason:
              'Cancellation must be the reason when it coexists with other '
              'criterion failures — it is the most actionable + severe.');
    });

    test('REVOKE reason: rating-below-threshold identified when that is the only fault',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_rating_fail';
      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.6, avgResponseMinutes: 5, isAnySkillPro: true);
      await _seedCompletedJobs(db, uid, 30); // orders OK
      // no cancellations

      await _evaluateProStatusWithAudit(db, uid);
      final audit = await _auditFor(db, uid);
      expect(audit.first['revocationReason'],
          startsWith('rating_below_threshold'));
    });

    test('IDEMPOTENT: unchanged state writes NO audit entry', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_stable';

      await _seedThresholds(db);
      await _seedProvider(db, uid,
          rating: 4.95, avgResponseMinutes: 3, isAnySkillPro: true);
      await _seedCompletedJobs(db, uid, 40);

      final out = await _evaluateProStatusWithAudit(db, uid);
      expect(out['transition'], equals('unchanged'));

      final audit = await _auditFor(db, uid);
      expect(audit, isEmpty,
          reason:
              'Idempotent evals must not produce audit noise — downstream '
              'consumers (dashboard, notifications) depend on it.');
    });

    test('MANUAL OVERRIDE: evaluation writes neither doc update NOR audit entry',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_manual';

      await _seedThresholds(db);
      // Admin granted manually even though criteria would revoke.
      await _seedProvider(db, uid,
          rating: 2.0,
          avgResponseMinutes: 60,
          isAnySkillPro: true,
          proManualOverride: true);

      final out = await _evaluateProStatusWithAudit(db, uid);
      expect(out['transition'], equals('manual_override_skip'));

      final after = await db.collection('users').doc(uid).get();
      expect(after.data()!['isAnySkillPro'], isTrue);
      final audit = await _auditFor(db, uid);
      expect(audit, isEmpty,
          reason:
              'Manual override freezes the badge; auto-eval must not log.');
    });

    test('ADMIN-triggered audit: source="callable_admin" + adminUid populated',
        () async {
      final db = FakeFirebaseFirestore();
      const uid = 'p_admin_eval';
      const adminUid = 'admin_007';

      await _seedThresholds(db);
      await _seedProvider(db, uid, rating: 4.9, avgResponseMinutes: 7);
      await _seedCompletedJobs(db, uid, 30);

      await _evaluateProStatusWithAudit(
        db, uid,
        source: 'callable_admin',
        adminUid: adminUid,
      );

      final audit = await _auditFor(db, uid);
      expect(audit, hasLength(1));
      expect(audit.first['source'],   equals('callable_admin'));
      expect(audit.first['adminUid'], equals(adminUid));
    });
  });
}
