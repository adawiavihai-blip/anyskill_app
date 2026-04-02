import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Data-layer for the admin billing / vault dashboard.
///
/// Encapsulates all Firestore reads and Cloud Function calls.
/// UI widgets never import `cloud_firestore` — they consume this repository
/// through Riverpod providers.
class AdminBillingRepository {
  AdminBillingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  // ── Real-time billing KPI stream ───────────────────────────────────────

  /// Stream the `system_stats/billing` doc for live KPI updates.
  Stream<Map<String, dynamic>> watchBillingStats() {
    return _db
        .collection('system_stats')
        .doc('billing')
        .snapshots()
        .map((snap) => snap.data() ?? {});
  }

  // ── Monthly revenue (one-shot) ─────────────────────────────────────────

  /// Sum `platform_earnings` for the current calendar month.
  Future<double> fetchMonthlyRevenue() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final snap = await _db
        .collection('platform_earnings')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .limit(500)
        .get();

    double total = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      total +=
          (d['amount'] as num? ?? d['commission'] as num? ?? 0).toDouble();
    }
    return total;
  }

  // ── Admin actions ──────────────────────────────────────────────────────

  /// Save budget settings via Cloud Function.
  Future<void> saveBudgetSettings({
    double? budgetLimit,
    double? killSwitchLimit,
  }) async {
    await _fn.httpsCallable('setBillingSettings').call({
      if (budgetLimit != null) 'budgetLimit': budgetLimit,
      if (killSwitchLimit != null) 'killSwitchLimit': killSwitchLimit,
    });
  }

  /// Toggle the AI kill-switch on/off.
  Future<void> toggleKillSwitch(bool newValue) async {
    await _fn
        .httpsCallable('setBillingSettings')
        .call({'killSwitchActive': newValue});
  }
}
