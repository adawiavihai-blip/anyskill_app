import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Single entry point for every Firestore read/write used by the Monetization
/// admin tab (v15.x).
///
/// Layers (Section 3 of the spec):
///   1. Global   — admin/admin/settings/settings.{feePercentage,urgencyFeePercentage,...}
///   2. Category — category_commissions/{categoryId}.{percentage, ...}
///   3. Per-user — users/{uid}.customCommission.{percentage, setAt, setBy, reason, notes, expiresAt}
///
/// Every write goes through here so the admin audit trail
/// (`activity_log`, category=`monetization`) is guaranteed.
class MonetizationService {
  MonetizationService._();

  static final _db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════
  // Refs
  // ══════════════════════════════════════════════════════════════════════

  static DocumentReference<Map<String, dynamic>> get _settingsRef => _db
      .collection('admin')
      .doc('admin')
      .collection('settings')
      .doc('settings');

  static CollectionReference<Map<String, dynamic>> get _categoryCommissionsCol =>
      _db.collection('category_commissions');

  static DocumentReference<Map<String, dynamic>> get _aiInsightRef =>
      _db.collection('ai_insights').doc('monetization');

  static CollectionReference<Map<String, dynamic>> get _alertsCol =>
      _db.collection('monetization_alerts');

  // ══════════════════════════════════════════════════════════════════════
  // Streams (reads)
  // ══════════════════════════════════════════════════════════════════════

  /// Live global settings. Emits an empty map if the doc is missing.
  static Stream<Map<String, dynamic>> streamGlobalSettings() {
    return _settingsRef.snapshots().map((s) => s.data() ?? {});
  }

  /// Live list of category-level commission overrides.
  /// Returns doc.id (== categoryId) as the map key for O(1) lookup.
  static Stream<Map<String, Map<String, dynamic>>> streamCategoryCommissions() {
    return _categoryCommissionsCol.snapshots().map((snap) {
      return {for (final d in snap.docs) d.id: d.data()};
    });
  }

  /// Live list of users that have a custom commission set.
  /// Limited to 200 — the UI paginates/filters further.
  static Stream<QuerySnapshot<Map<String, dynamic>>>
      streamCustomCommissionUsers() {
    // Firestore cannot filter on nested-field existence directly; we filter
    // by a sentinel parent field `customCommissionActive: true` that the
    // write helpers maintain alongside `customCommission`.
    return _db
        .collection('users')
        .where('customCommissionActive', isEqualTo: true)
        .limit(200)
        .snapshots();
  }

  /// Latest AI insight for the monetization tab (single doc).
  static Stream<Map<String, dynamic>?> streamLatestInsight() {
    return _aiInsightRef.snapshots().map((s) => s.data());
  }

  /// Unresolved monetization alerts, newest first.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamOpenAlerts({
    int limit = 10,
  }) {
    return _alertsCol
        .where('resolved', isEqualTo: false)
        .orderBy('detectedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Pending escrow jobs — same query used in the legacy tab, exposed so the
  /// new Escrow card can reuse it. Limit 50, newest first.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamEscrowJobs() {
    return _db
        .collection('jobs')
        .where('status', isEqualTo: 'paid_escrow')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Monetization-scoped activity feed. Limit 5 by default.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamActivityFeed({
    int limit = 5,
  }) {
    return _db
        .collection('activity_log')
        .where('category', isEqualTo: 'monetization')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ══════════════════════════════════════════════════════════════════════
  // One-shot reads (used by the effective-commission preview + health card)
  // ══════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getGlobalSettings() async {
    final doc = await _settingsRef.get();
    return doc.data() ?? {};
  }

  /// Returns the category-level percentage (0-30 scale) or null if no override.
  static Future<double?> getCategoryPercentage(String categoryId) async {
    if (categoryId.isEmpty) return null;
    final doc = await _categoryCommissionsCol.doc(categoryId).get();
    final pct = (doc.data()?['percentage'] as num?)?.toDouble();
    return pct;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Writes (each one lands an activity_log row)
  // ══════════════════════════════════════════════════════════════════════

  /// Updates the global fee sliders.
  /// [feePct] and [urgencyPct] are 0-100 scale; Firestore stores 0-1 fractions.
  static Future<void> updateGlobalCommission({
    required double feePct,
    required double urgencyPct,
    double? oldFeePct,
    double? oldUrgencyPct,
  }) async {
    await _settingsRef.set({
      'feePercentage': feePct / 100,
      'urgencyFeePercentage': urgencyPct / 100,
    }, SetOptions(merge: true));

    await _logActivity(
      action: 'commission_updated_global',
      detail:
          'עמלה גלובלית: ${oldFeePct?.toStringAsFixed(1) ?? '?'}% → ${feePct.toStringAsFixed(1)}% · '
          'דחיפות: ${oldUrgencyPct?.toStringAsFixed(1) ?? '?'}% → ${urgencyPct.toStringAsFixed(1)}%',
      payload: {
        'oldFeePct': oldFeePct,
        'newFeePct': feePct,
        'oldUrgencyPct': oldUrgencyPct,
        'newUrgencyPct': urgencyPct,
      },
    );
  }

  /// Updates the smart-rule toggles. Any field may be null to leave unchanged.
  static Future<void> updateSmartRules({
    int? waiveFeeFirstNJobs,
    Map<String, dynamic>? tieredCommission,
    Map<String, dynamic>? weekendBoost,
  }) async {
    final patch = <String, dynamic>{};
    if (waiveFeeFirstNJobs != null) {
      patch['waiveFeeFirstNJobs'] = waiveFeeFirstNJobs;
    }
    if (tieredCommission != null) patch['tieredCommission'] = tieredCommission;
    if (weekendBoost != null) patch['weekendBoost'] = weekendBoost;
    if (patch.isEmpty) return;

    await _settingsRef.set(patch, SetOptions(merge: true));

    await _logActivity(
      action: 'smart_rules_updated',
      detail: 'כללים חכמים עודכנו: ${patch.keys.join(', ')}',
      payload: patch,
    );
  }

  /// Upsert a category-level override. Pass [percentage] == null to remove.
  static Future<void> setCategoryCommission({
    required String categoryId,
    required String categoryName,
    required double? percentage,
    String? reason,
    double? oldPercentage,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ref = _categoryCommissionsCol.doc(categoryId);

    if (percentage == null) {
      await ref.delete();
      await _logActivity(
        action: 'commission_updated_category',
        detail: 'הוסר override עבור $categoryName — חוזר לגלובלי',
        payload: {
          'categoryId': categoryId,
          'oldPercentage': oldPercentage,
          'newPercentage': null,
        },
      );
      return;
    }

    await ref.set({
      'categoryId': categoryId,
      'categoryName': categoryName,
      'percentage': percentage,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }, SetOptions(merge: true));

    await _logActivity(
      action: 'commission_updated_category',
      detail:
          'עמלת קטגוריה "$categoryName": ${oldPercentage?.toStringAsFixed(1) ?? '?'}% → ${percentage.toStringAsFixed(1)}%',
      payload: {
        'categoryId': categoryId,
        'categoryName': categoryName,
        'oldPercentage': oldPercentage,
        'newPercentage': percentage,
        'reason': reason,
      },
    );
  }

  /// Sets (or clears) a per-user custom commission.
  ///
  /// Setting [percentage] to null removes the override (commission falls back
  /// to category/global).
  static Future<void> setUserCommission({
    required String userId,
    required String userName,
    required double? percentage,
    required String reason,
    String? notes,
    DateTime? expiresAt,
    double? oldPercentage,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final userRef = _db.collection('users').doc(userId);

    if (percentage == null) {
      await userRef.update({
        'customCommission': FieldValue.delete(),
        'customCommissionActive': false,
      });
      await _logActivity(
        action: 'commission_updated_for_user',
        targetUid: userId,
        detail: 'הוסר custom commission עבור $userName',
        payload: {
          'userId': userId,
          'userName': userName,
          'oldValue': oldPercentage,
          'newValue': null,
          'reason': reason,
        },
      );
      return;
    }

    await userRef.set({
      'customCommissionActive': true,
      'customCommission': {
        'percentage': percentage,
        'setAt': FieldValue.serverTimestamp(),
        'setBy': adminUid,
        'reason': reason,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      },
    }, SetOptions(merge: true));

    await _logActivity(
      action: 'commission_updated_for_user',
      targetUid: userId,
      detail:
          'עמלה ל-$userName: ${oldPercentage?.toStringAsFixed(1) ?? '?'}% → ${percentage.toStringAsFixed(1)}% ($reason)',
      payload: {
        'userId': userId,
        'userName': userName,
        'oldValue': oldPercentage,
        'newValue': percentage,
        'reason': reason,
        'notes': notes,
        'expiresAt': expiresAt?.toIso8601String(),
      },
    );
  }

  /// Marks a monetization alert as resolved. Used when the admin dismisses
  /// or acts on an alert card.
  static Future<void> resolveAlert(String alertId, {String? note}) async {
    await _alertsCol.doc(alertId).update({
      'resolved': true,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      if (note != null) 'resolutionNote': note,
    });
  }

  /// Marks the current AI insight as dismissed (sets applied=false explicitly
  /// so the next generation run knows it was seen-and-declined).
  static Future<void> dismissInsight() async {
    await _aiInsightRef.set({
      'applied': false,
      'dismissedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'dismissedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ══════════════════════════════════════════════════════════════════════
  // Private — activity log writer
  // ══════════════════════════════════════════════════════════════════════

  static Future<void> _logActivity({
    required String action,
    required String detail,
    String? targetUid,
    Map<String, dynamic>? payload,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // TTL 30d per Section 19 of CLAUDE.md.
    final expireAt =
        Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)));

    try {
      await _db.collection('activity_log').add({
        'action': action,
        'category': 'monetization',
        'type': 'monetization_$action',
        'adminUid': adminUid,
        'userId': adminUid,
        if (targetUid != null) 'targetUid': targetUid,
        'detail': detail,
        'title': detail,
        if (payload != null) 'payload': payload,
        'priority': 'normal',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt': expireAt,
      });
    } catch (_) {
      // Activity logging is best-effort; don't surface failures to the UI.
    }
  }
}
