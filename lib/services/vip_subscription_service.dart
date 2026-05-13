import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/vip_subscription_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// VIP subscription service — single abstraction over `vip_subscriptions/`.
/// Phase 3 surface: read streams + admin-comp grant + revoke. Paid
/// subscriptions arrive via the `purchaseVipWithCredits` Cloud Function
/// in Phase 5; this client never writes a `type: 'paid'` doc directly.
///
/// **Capacity model:**
///   - Hard cap = 30 simultaneous active subscriptions
///   - Admin-comp grants always succeed even when capacity is "full",
///     per spec — they temporarily expand the cap. (Cloud Function in
///     Phase 6 reconciles the carousel rotation across all paying
///     subscribers when actual count > 30.)
///
/// **CSAT note:** every admin-comp grant writes to `admin_audit_log/{id}`
/// (CLAUDE.md §50 audit-trail rule). Revokes also write to audit log.
/// ═══════════════════════════════════════════════════════════════════════════
class VipSubscriptionService {
  VipSubscriptionService._();
  static final VipSubscriptionService instance = VipSubscriptionService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('vip_subscriptions');

  /// Hard cap — also enforced by the Phase 6 rotation CF.
  static const int maxSlots = 30;

  /// Stream every subscription. Phase 3 caps at 200; capacity is 30 so
  /// going above means there's a backlog of expired/waitlist docs that
  /// the rotation CF will eventually clean up.
  Stream<List<VipSubscription>> watchAll() {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map(_safeMap);
  }

  /// Stream only the active subscriptions (paid OR admin-comp). This
  /// drives the 30-slot grid + capacity ring on the VIP screen.
  Stream<List<VipSubscription>> watchActive() {
    return _col
        .where('status', isEqualTo: VipSubscriptionStatus.active.dbValue)
        .limit(60) // 30 cap + a buffer for race conditions
        .snapshots()
        .map(_safeMap);
  }

  /// Stream the waitlist queue, ordered by `waitlistPosition` ASC.
  Stream<List<VipSubscription>> watchWaitlist() {
    return _col
        .where('status', isEqualTo: VipSubscriptionStatus.waitlist.dbValue)
        .limit(100)
        .snapshots()
        .map((snap) {
      final list = _safeMap(snap)
        ..sort((a, b) {
          final ap = a.waitlistPosition ?? 999999;
          final bp = b.waitlistPosition ?? 999999;
          return ap.compareTo(bp);
        });
      return list;
    });
  }

  static List<VipSubscription> _safeMap(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final out = <VipSubscription>[];
    for (final doc in snap.docs) {
      try {
        out.add(VipSubscription.fromDoc(doc));
      } catch (e) {
        // ignore: avoid_print
        print('[VipService] Skipped malformed doc "${doc.id}": $e');
      }
    }
    return out;
  }

  // ─── Admin-comp grants ────────────────────────────────────────────

  /// Grant a free VIP slot to a provider. Admin-only flow — caller is
  /// expected to have `isAdmin == true` (rule-enforced).
  ///
  /// Returns the new subscription doc id. Writes an audit log entry.
  /// Caller can choose `notify=true` to push an in-app notification to
  /// the provider — Phase 3 implements the notification side as a TODO
  /// (a CF trigger on subscription create would be cleaner; deferred to
  /// Phase 6).
  Future<String> grantAdminComp({
    required String providerId,
    required String providerName,
    required VipCompDuration duration,
    required String reason,
    bool autoRenew = false,
  }) async {
    final caller = FirebaseAuth.instance.currentUser;
    if (caller == null) {
      throw StateError('not-authenticated');
    }
    if (reason.trim().length < 5) {
      throw ArgumentError('reason must be at least 5 chars');
    }

    final now = DateTime.now();
    final endDate = duration.days == null
        ? null
        : now.add(Duration(days: duration.days!));

    final draft = VipSubscription(
      id: '',
      providerId: providerId,
      status: VipSubscriptionStatus.active,
      type: VipSubscriptionType.adminComp,
      startDate: now,
      endDate: endDate,
      autoRenew: false, // Always false for admin-comp
      pricePerMonth: 0,
      compDuration: duration,
      compReason: reason,
      grantedBy: caller.uid,
      grantedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    final ref = _col.doc();
    final data = draft.toFirestore();
    data.remove('id');
    await ref.set(data);

    // Audit log entry — best effort, doesn't fail the grant on error.
    try {
      await _db.collection('admin_audit_log').add({
        'action': 'vip_grant_admin_comp',
        'targetUserId': providerId,
        'targetName': providerName,
        'adminUid': caller.uid,
        'adminName': caller.displayName ?? caller.email ?? 'admin',
        'reason': reason.trim(),
        'metadata': {
          'subscriptionId': ref.id,
          'duration': duration.dbValue,
          'endDate': endDate?.toIso8601String(),
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('[VipService] audit_log write failed (non-fatal): $e');
    }

    return ref.id;
  }

  /// Revoke a subscription (manual cancellation by admin). Sets status
  /// to `expired`, writes `endDate=now`, and logs to audit.
  Future<void> revoke({
    required String subscriptionId,
    required String reason,
  }) async {
    final caller = FirebaseAuth.instance.currentUser;
    if (caller == null) {
      throw StateError('not-authenticated');
    }
    final snap = await _col.doc(subscriptionId).get();
    if (!snap.exists) return;
    final before = VipSubscription.fromDoc(snap);

    await _col.doc(subscriptionId).update({
      'status': VipSubscriptionStatus.expired.dbValue,
      'endDate': Timestamp.fromDate(DateTime.now()),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await _db.collection('admin_audit_log').add({
        'action': 'vip_revoke',
        'targetUserId': before.providerId,
        'adminUid': caller.uid,
        'adminName': caller.displayName ?? caller.email ?? 'admin',
        'reason': reason.trim(),
        'metadata': {
          'subscriptionId': subscriptionId,
          'previousStatus': before.status.dbValue,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('[VipService] audit_log write failed: $e');
    }
  }

  /// Toggle a paid subscription's auto-renew flag. Caller must be either
  /// the subscription owner OR an admin (rule-enforced in Phase 5).
  Future<void> setAutoRenew(String subscriptionId, bool autoRenew) {
    return _col.doc(subscriptionId).update({
      'autoRenew': autoRenew,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Promote the waitlist row at [position] (1-indexed) to the active
  /// pool — used by the waitlist card's "↑ קדם" button. Phase 3 does the
  /// flip client-side; Phase 6's rotation CF will re-shuffle positions.
  Future<void> promoteFromWaitlist(String subscriptionId) async {
    await _col.doc(subscriptionId).update({
      'status': VipSubscriptionStatus.active.dbValue,
      'waitlistPosition': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
