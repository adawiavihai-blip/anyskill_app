/// AnyTasks 3.0 — Cancellation & Penalty Service
///
/// Implements Gap #3: Tiered cancellation penalties based on time since
/// assignment. Provider reliability scoring and escalating suspensions.
///
/// Penalty tiers (provider cancels):
///   - 0–30 min:   Free (warning only)
///   - 30 min–2h:  Score -0.10
///   - 2h+:        Score -0.20 + possible suspension
///
/// Penalty tiers (creator cancels):
///   - Before claim (open): Free, full refund
///   - Within 30 min:       5% fee
///   - 30 min–2h:           15% fee
///   - 2h+:                 25% fee
///   - After proof_submitted: Must confirm or dispute (no cancel)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Result of a cancellation penalty calculation.
class CancellationPenalty {
  /// Hebrew description of the penalty for the warning dialog.
  final String description;

  /// Score impact on provider's anytaskCancellationScore (0.0 for no impact).
  final double scoreImpact;

  /// Monetary penalty as a fraction of the task amount (0.0–0.25).
  final double feeFraction;

  /// Penalty tier name for audit trail.
  final String tier;

  /// Whether this cancellation should trigger a suspension check.
  final bool checkSuspension;

  const CancellationPenalty({
    required this.description,
    required this.scoreImpact,
    required this.feeFraction,
    required this.tier,
    this.checkSuspension = false,
  });
}

class AnytaskCancellationService {
  AnytaskCancellationService._();

  static final _db = FirebaseFirestore.instance;

  // ── Constants ──────────────────────────────────────────────────────────

  /// Cancellation score threshold below which provider gets suspended.
  static const double suspensionThreshold = 0.3;

  /// Score recovery per completed task.
  static const double scoreRecoveryPerTask = 0.02;

  /// Escalating suspension durations based on how many times suspended.
  static const List<Duration> suspensionDurations = [
    Duration(days: 1),   // 1st suspension
    Duration(days: 3),   // 2nd
    Duration(days: 7),   // 3rd
    Duration(days: 30),  // 4th+
  ];

  // ── Penalty Calculation ────────────────────────────────────────────────

  /// Calculates the cancellation penalty based on who is cancelling and
  /// how long since the task was claimed.
  ///
  /// [cancelledBy]: 'creator' or 'provider'
  /// [status]: current task status
  /// [claimedAt]: when the task was claimed (null if still open)
  static CancellationPenalty calculatePenalty({
    required String cancelledBy,
    required String status,
    required DateTime? claimedAt,
  }) {
    // ── Open task (no claim yet) → always free ────────────────────────
    if (status == 'open') {
      return const CancellationPenalty(
        description: 'ביטול חופשי — המשימה טרם נתפסה',
        scoreImpact: 0,
        feeFraction: 0,
        tier: 'free',
      );
    }

    // ── After proof submitted → cannot cancel ─────────────────────────
    if (status == 'proof_submitted') {
      return const CancellationPenalty(
        description: 'לא ניתן לבטל — נותן השירות כבר שלח הוכחה. אשר או פתח מחלוקת.',
        scoreImpact: 0,
        feeFraction: 0,
        tier: 'blocked',
      );
    }

    final minutesSinceClaim = claimedAt != null
        ? DateTime.now().difference(claimedAt).inMinutes
        : 0;

    // ── Provider cancels ──────────────────────────────────────────────
    if (cancelledBy == 'provider') {
      if (minutesSinceClaim <= 30) {
        return const CancellationPenalty(
          description: 'ביטול חופשי (תוך 30 דקות מהתפיסה)',
          scoreImpact: 0,
          feeFraction: 0,
          tier: 'provider_free',
        );
      }
      if (minutesSinceClaim <= 120) {
        return const CancellationPenalty(
          description: 'ביטול לאחר 30 דקות — ציון האמינות שלך ירד ב-0.10',
          scoreImpact: -0.10,
          feeFraction: 0,
          tier: 'provider_light',
        );
      }
      return const CancellationPenalty(
        description: 'ביטול מאוחר — ציון האמינות שלך ירד ב-0.20 ואתה עלול להיות מושהה',
        scoreImpact: -0.20,
        feeFraction: 0,
        tier: 'provider_heavy',
        checkSuspension: true,
      );
    }

    // ── Creator cancels (after claim) ────────────────────────────────
    if (minutesSinceClaim <= 30) {
      return const CancellationPenalty(
        description: 'ביטול תוך 30 דקות — עמלה של 5%',
        scoreImpact: 0,
        feeFraction: 0.05,
        tier: 'creator_light',
      );
    }
    if (minutesSinceClaim <= 120) {
      return const CancellationPenalty(
        description: 'ביטול לאחר 30 דקות — עמלה של 15%',
        scoreImpact: 0,
        feeFraction: 0.15,
        tier: 'creator_medium',
      );
    }
    return const CancellationPenalty(
      description: 'ביטול מאוחר — עמלה של 25%',
      scoreImpact: 0,
      feeFraction: 0.25,
      tier: 'creator_heavy',
    );
  }

  // ── Apply Penalty ──────────────────────────────────────────────────────

  /// Applies the calculated penalty: score decrement + penalty record.
  /// Returns null on success, or a Hebrew error string.
  static Future<String?> applyPenalty({
    required String taskId,
    required String userId,
    required CancellationPenalty penalty,
    required double taskAmount,
  }) async {
    if (penalty.tier == 'free' || penalty.tier == 'provider_free') return null;

    try {
      final batch = _db.batch();

      // ── Write penalty record ───────────────────────────────────────
      final penaltyRef = _db.collection('anytask_penalties').doc();
      batch.set(penaltyRef, {
        'taskId':      taskId,
        'userId':      userId,
        'type':        penalty.tier.startsWith('provider') ? 'provider_cancel' : 'creator_cancel',
        'tier':        penalty.tier,
        'scoreImpact': penalty.scoreImpact,
        'feeAmount':   double.parse((taskAmount * penalty.feeFraction).toStringAsFixed(2)),
        'details':     penalty.description,
        'createdAt':   FieldValue.serverTimestamp(),
      });

      // ── Decrement cancellation score (providers only) ──────────────
      if (penalty.scoreImpact < 0) {
        batch.update(_db.collection('users').doc(userId), {
          'anytaskCancellationScore': FieldValue.increment(penalty.scoreImpact),
        });
      }

      await batch.commit();

      // ── Check if provider should be suspended ──────────────────────
      if (penalty.checkSuspension) {
        await _checkAndSuspend(userId);
      }

      return null;
    } catch (e) {
      debugPrint('[AnytaskCancellation] applyPenalty error: $e');
      return 'שגיאה בהחלת עונש הביטול';
    }
  }

  // ── Suspension Logic ───────────────────────────────────────────────────

  /// If the provider's score drops below [suspensionThreshold], suspend them
  /// for an escalating duration.
  static Future<void> _checkAndSuspend(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      final data = doc.data() ?? {};
      final score = (data['anytaskCancellationScore'] as num? ?? 1.0).toDouble();

      if (score >= suspensionThreshold) return; // Not low enough to suspend

      final suspensionCount = (data['anytaskSuspensionCount'] as num? ?? 0).toInt();
      final durationIndex = suspensionCount.clamp(0, suspensionDurations.length - 1);
      final duration = suspensionDurations[durationIndex];
      final suspendUntil = DateTime.now().add(duration);

      await _db.collection('users').doc(userId).update({
        'anytaskSuspendedUntil':  Timestamp.fromDate(suspendUntil),
        'anytaskSuspensionCount': FieldValue.increment(1),
      });

      // Notify provider
      await _db.collection('notifications').add({
        'userId':    userId,
        'title':     '🚫 חשבונך הושהה מ-AnyTasks',
        'body':      'בשל ביטולים חוזרים, חשבונך מושהה ל-${duration.inDays} ימים.',
        'type':      'anytask_suspended',
        'isRead':    false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[AnytaskCancellation] Suspended $userId for ${duration.inDays} days '
          '(suspension #${suspensionCount + 1})');
    } catch (e) {
      debugPrint('[AnytaskCancellation] _checkAndSuspend error: $e');
    }
  }

  // ── Score Recovery ─────────────────────────────────────────────────────

  /// Call after a provider successfully completes a task to recover score.
  static Future<void> recoverScore(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      final score = ((doc.data() ?? {})['anytaskCancellationScore'] as num? ?? 1.0).toDouble();

      if (score >= 1.0) return; // Already at max

      final newScore = (score + scoreRecoveryPerTask).clamp(0.0, 1.0);
      await _db.collection('users').doc(userId).update({
        'anytaskCancellationScore': newScore,
      });
    } catch (e) {
      debugPrint('[AnytaskCancellation] recoverScore error: $e');
    }
  }
}
