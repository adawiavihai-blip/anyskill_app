/// AnyTasks 3.0 — Anti-Fraud Service
///
/// Implements Gap #2 from the AnyTasks spec:
///   1. Self-assignment prevention (creatorId != providerId + device check)
///   2. Device fingerprint tracking
///   3. Suspension enforcement
///   4. Fraud audit trail logging
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AnytaskAntifraudService {
  AnytaskAntifraudService._();

  static final _db = FirebaseFirestore.instance;

  // ── Self-Assignment Prevention ─────────────────────────────────────────

  /// Checks if the provider is trying to claim their own task.
  /// Returns a Hebrew error string if blocked, null if OK.
  static String? blockSelfAssignment({
    required String creatorId,
    required String providerId,
  }) {
    if (creatorId == providerId) {
      return 'לא ניתן לתפוס משימה שפרסמת בעצמך';
    }
    return null;
  }

  /// Checks if the provider's device matches the task creator's device.
  /// Returns a Hebrew error string if blocked, null if OK.
  static Future<String?> checkDeviceCollision({
    required String? creatorDeviceId,
    required String providerId,
  }) async {
    if (creatorDeviceId == null || creatorDeviceId.isEmpty) return null;

    try {
      final providerDoc = await _db.collection('users').doc(providerId).get();
      final providerData = providerDoc.data() ?? {};
      final providerDevices = providerData['deviceFingerprints'] as List<dynamic>? ?? [];
      final providerCurrentDevice = providerData['deviceFingerprint'] as String? ?? '';

      if (providerCurrentDevice == creatorDeviceId ||
          providerDevices.contains(creatorDeviceId)) {
        // Log fraud attempt
        await _logFraudAttempt(
          userId: providerId,
          type: 'device_collision',
          details: 'Provider device matches task creator device',
        );
        return 'זוהה ניסיון חריג — לא ניתן לתפוס משימה זו';
      }
    } catch (e) {
      debugPrint('[AnytaskAntifraud] checkDeviceCollision error: $e');
      // Don't block on check failure — log and allow
    }

    return null;
  }

  // ── Suspension Enforcement ─────────────────────────────────────────────

  /// Checks if the provider is currently suspended from AnyTasks.
  /// Returns a Hebrew error string with the remaining suspension time, or null.
  static Future<String?> checkSuspension(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      final data = userDoc.data() ?? {};
      final suspendedUntil = data['anytaskSuspendedUntil'] as Timestamp?;

      if (suspendedUntil == null) return null;

      final suspendDate = suspendedUntil.toDate();
      if (DateTime.now().isAfter(suspendDate)) {
        // Suspension expired — clear it
        await _db.collection('users').doc(userId).update({
          'anytaskSuspendedUntil': FieldValue.delete(),
        });
        return null;
      }

      final remaining = suspendDate.difference(DateTime.now());
      if (remaining.inHours >= 24) {
        final days = (remaining.inHours / 24).ceil();
        return 'חשבונך מושעה מ-AnyTasks לעוד $days ימים';
      }
      return 'חשבונך מושעה מ-AnyTasks לעוד ${remaining.inHours} שעות';
    } catch (e) {
      debugPrint('[AnytaskAntifraud] checkSuspension error: $e');
      return null; // Don't block on check failure
    }
  }

  // ── Cancellation Score Check ───────────────────────────────────────────

  /// Returns the provider's current AnyTask cancellation score (0.0–1.0).
  /// 1.0 = perfect, 0.0 = terrible. Default for new users: 1.0.
  static Future<double> getCancellationScore(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      final data = doc.data() ?? {};
      return (data['anytaskCancellationScore'] as num? ?? 1.0).toDouble();
    } catch (e) {
      debugPrint('[AnytaskAntifraud] getCancellationScore error: $e');
      return 1.0;
    }
  }

  // ── Fraud Audit Trail ──────────────────────────────────────────────────

  /// Logs a fraud attempt or suspicious activity.
  static Future<void> _logFraudAttempt({
    required String userId,
    required String type,
    required String details,
  }) async {
    try {
      await _db.collection('anytask_fraud_log').add({
        'userId':    userId,
        'type':      type,
        'details':   details,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AnytaskAntifraud] _logFraudAttempt error: $e');
    }
  }

  /// Logs a specific fraud flag on the user document for admin visibility.
  static Future<void> flagUser(String userId, String flagType) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fraudFlags': FieldValue.arrayUnion([flagType]),
      });
    } catch (e) {
      debugPrint('[AnytaskAntifraud] flagUser error: $e');
    }
  }
}
