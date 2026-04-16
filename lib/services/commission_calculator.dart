import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirror of the server-side `getEffectiveCommission` helper in
/// `functions/index.js`. Used by the simulator + dialog previews so the UI
/// doesn't have to roundtrip a Cloud Function for every slider tick.
///
/// **Authoritative computation still runs on the server** (inside
/// `processPaymentRelease` / `EscrowService.payQuote`). This class is a
/// client-side preview — if the rules ever diverge, the server wins.
///
/// All percentages are in the **0-100** scale (UI-friendly). The server
/// stores `feePercentage` as a 0-1 fraction; callers are responsible for
/// converting (see `MonetizationService.updateGlobalCommission`).
class CommissionCalculator {
  CommissionCalculator._();

  /// Resolves the effective percentage in the priority order:
  ///   custom (on user) → category override → global default.
  ///
  /// If any layer returns null, the next layer is consulted. The final
  /// fallback is 10% (the historical AnySkill default).
  static EffectiveCommission resolve({
    required Map<String, dynamic>? userData,
    required double? categoryPct,
    required double? globalPct,
  }) {
    final custom = userData?['customCommission'];
    final active = userData?['customCommissionActive'] == true;
    if (active && custom is Map) {
      final pct = (custom['percentage'] as num?)?.toDouble();
      final expiresAt = custom['expiresAt'];
      DateTime? expiresDt;
      if (expiresAt is Timestamp) expiresDt = expiresAt.toDate();
      final live = expiresDt == null || expiresDt.isAfter(DateTime.now());
      if (pct != null && live) {
        return EffectiveCommission(
          percentage: pct,
          source: CommissionSource.custom,
          reason: custom['reason']?.toString(),
        );
      }
    }

    if (categoryPct != null) {
      return EffectiveCommission(
        percentage: categoryPct,
        source: CommissionSource.category,
      );
    }

    return EffectiveCommission(
      percentage: globalPct ?? 10.0,
      source: CommissionSource.global,
    );
  }

  /// Convenience wrapper that reads Firestore directly. Prefer the pure
  /// [resolve] variant inside tight UI loops (slider dragging) — this one
  /// is for one-shot previews.
  static Future<EffectiveCommission> resolveFromFirestore({
    required String userId,
    String? categoryId,
  }) async {
    final db = FirebaseFirestore.instance;

    // Global default (0-100 scale)
    final settingsSnap = await db
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings')
        .get();
    final globalFraction =
        (settingsSnap.data()?['feePercentage'] as num?)?.toDouble() ?? 0.10;
    final globalPct = globalFraction * 100;

    // User
    final userSnap = await db.collection('users').doc(userId).get();
    final userData = userSnap.data();

    // Category override
    double? categoryPct;
    if (categoryId != null && categoryId.isNotEmpty) {
      final catSnap =
          await db.collection('category_commissions').doc(categoryId).get();
      categoryPct = (catSnap.data()?['percentage'] as num?)?.toDouble();
    }

    return resolve(
      userData: userData,
      categoryPct: categoryPct,
      globalPct: globalPct,
    );
  }

  /// Applies smart-rule adjustments on top of the resolved commission.
  /// Used by the simulator preview and by the order summary screen (future).
  ///
  /// [completedJobs] — number of completed jobs by this provider.
  /// [monthGmv] — provider's rolling 30-day GMV in ₪.
  /// [bookingTime] — when the booking happens (used for weekend boost).
  static double applySmartRules({
    required double basePct,
    required Map<String, dynamic> settings,
    int? completedJobs,
    double? monthGmv,
    DateTime? bookingTime,
  }) {
    double pct = basePct;

    // Rule 1: waive fee for first N jobs.
    final waive = (settings['waiveFeeFirstNJobs'] as num?)?.toInt() ?? 0;
    if (waive > 0 && completedJobs != null && completedJobs < waive) {
      return 0;
    }

    // Rule 2: tiered volume discount (subtractive, percentage points).
    final tiered = settings['tieredCommission'];
    if (tiered is Map && tiered['enabled'] == true && monthGmv != null) {
      final tiers = (tiered['tiers'] as List?) ?? const [];
      double bestDiscount = 0;
      for (final tier in tiers) {
        if (tier is! Map) continue;
        final minGmv = (tier['minGMV'] as num?)?.toDouble() ?? 0;
        final discount = (tier['discount'] as num?)?.toDouble() ?? 0;
        if (monthGmv >= minGmv && discount > bestDiscount) {
          bestDiscount = discount;
        }
      }
      pct = (pct - bestDiscount).clamp(0, pct);
    }

    // Rule 3: weekend boost (additive).
    final boost = settings['weekendBoost'];
    if (boost is Map && boost['enabled'] == true && bookingTime != null) {
      final days = (boost['daysOfWeek'] as List?)?.cast<num>() ?? const [];
      // Flutter's DateTime.weekday: 1=Mon..7=Sun. The spec uses 0=Sun..6=Sat.
      // We translate: Flutter weekday % 7 == spec dayIndex.
      final specIdx = bookingTime.weekday % 7;
      if (days.any((d) => d.toInt() == specIdx)) {
        final extra = (boost['extraPercentage'] as num?)?.toDouble() ?? 0;
        pct = pct + extra;
      }
    }

    return pct.clamp(0, 100).toDouble();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum CommissionSource { custom, category, global }

extension CommissionSourceX on CommissionSource {
  String get hebrewLabel => switch (this) {
        CommissionSource.custom => 'מותאם',
        CommissionSource.category => 'מקטגוריה',
        CommissionSource.global => 'ברירת מחדל',
      };
}

class EffectiveCommission {
  final double percentage; // 0-100 scale
  final CommissionSource source;
  final String? reason;

  const EffectiveCommission({
    required this.percentage,
    required this.source,
    this.reason,
  });

  double asFraction() => percentage / 100;
}
