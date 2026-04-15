/// AnySkill — TaskEscrowService (AnyTasks v14.0.0)
///
/// Mirrors the existing `EscrowService.payQuote` pattern (Section 4.1 of
/// CLAUDE.md) for AnyTasks. Client selects a provider → atomic tx charges
/// escrow, marks the task in_progress, credits pendingBalance, logs
/// transaction + platform_earnings. Payment RELEASE happens server-side
/// via the `releaseTaskPayment` CF (Phase 4) — never from the client.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class TaskEscrowService {
  TaskEscrowService._();

  static final _db = FirebaseFirestore.instance;

  /// Called when a client taps "Choose [provider]" on the Compare Offers
  /// screen. Returns null on success, Hebrew error string otherwise.
  ///
  /// [agreedPriceNis] is either the original budget (provider pressed
  /// Accept) or the counter-offer amount (client accepted the counter).
  static Future<String?> chooseProvider({
    required String taskId,
    required String responseId,
    required String providerId,
    required String providerName,
    required String clientId,
    required String clientName,
    required int agreedPriceNis,
    required String taskTitle,
  }) async {
    if (clientId == providerId) {
      return 'לא ניתן להזמין שירות מעצמך';
    }
    if (agreedPriceNis < 10) {
      return 'המחיר חייב להיות לפחות ₪10';
    }

    try {
      final adminSettingsRef = _db
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings');
      final taskRef = _db.collection('any_tasks').doc(taskId);
      final responseRef = taskRef.collection('responses').doc(responseId);

      await _db.runTransaction((tx) async {
        final taskSnap = await tx.get(taskRef);
        final clientSnap = await tx.get(_db.collection('users').doc(clientId));
        final adminSnap = await tx.get(adminSettingsRef);
        final responseSnap = await tx.get(responseRef);

        if (!taskSnap.exists) throw Exception('המשימה לא נמצאה');
        final tData = taskSnap.data()!;
        if (tData['status'] != 'open') {
          throw Exception('המשימה כבר שויכה לנותן שירות אחר');
        }

        final balance = ((clientSnap.data() ?? {})['balance'] as num? ?? 0)
            .toDouble();
        if (balance < agreedPriceNis) {
          throw Exception(
              'אין מספיק יתרה בארנק. נדרשת יתרה של ₪$agreedPriceNis');
        }

        final feePct = ((adminSnap.data() ?? {})['feePercentage'] as num? ??
                0.1)
            .toDouble();
        final commission = (agreedPriceNis * feePct).round();
        final netToProvider = agreedPriceNis - commission;

        // ── 1. Update task doc ──────────────────────────────────────
        tx.update(taskRef, {
          'selectedProviderId': providerId,
          'selectedProviderName': providerName,
          'agreedPriceNis': agreedPriceNis,
          'platformFeeNis': commission,
          'providerPayoutNis': netToProvider,
          'status': 'in_progress',
          'acceptedAt': FieldValue.serverTimestamp(),
        });

        // ── 2. Mark chosen response ─────────────────────────────────
        if (responseSnap.exists) {
          tx.update(responseRef, {'status': 'chosen'});
        }

        // ── 3. Debit client ─────────────────────────────────────────
        tx.update(_db.collection('users').doc(clientId), {
          'balance': FieldValue.increment(-agreedPriceNis),
        });

        // ── 4. Credit provider pending ──────────────────────────────
        tx.update(_db.collection('users').doc(providerId), {
          'pendingBalance': FieldValue.increment(netToProvider),
        });

        // ── 5. Platform earnings record (pending) ───────────────────
        tx.set(_db.collection('platform_earnings').doc(), {
          'taskId': taskId,
          'amount': commission,
          'sourceExpertId': providerId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending_escrow',
          'source': 'any_tasks',
        });

        // ── 6. Transaction log ──────────────────────────────────────
        tx.set(_db.collection('transactions').doc(), {
          'senderId': clientId,
          'senderName': clientName,
          'receiverId': providerId,
          'receiverName': providerName,
          'amount': agreedPriceNis,
          'type': 'any_task_escrow',
          'taskId': taskId,
          'taskTitle': taskTitle,
          'payoutStatus': 'pending',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // ── 7. Platform totals ──────────────────────────────────────
        tx.set(
          adminSettingsRef,
          {'totalPlatformBalance': FieldValue.increment(commission)},
          SetOptions(merge: true),
        );
      });

      return null;
    } on FirebaseException catch (e) {
      debugPrint('TaskEscrowService.chooseProvider FirebaseException: $e');
      return e.message ?? 'שגיאת מסד נתונים.';
    } catch (e) {
      debugPrint('TaskEscrowService.chooseProvider error: $e');
      return e.toString().replaceAll('Exception: ', '');
    }
  }
}
