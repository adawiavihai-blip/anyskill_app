import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class PaymentModule {
  // ── Cancel booking: refund full amount to customer ───────────────────────
  static Future<bool> cancelEscrow({
    required String jobId,
    required String customerId,
    required double totalAmount,
    String chatRoomId = '',
    FirebaseFirestore? db,
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;
    try {
      await firestore.runTransaction((tx) async {
        // Read job first to validate status and amount — prevents double-refund
        // and guards against arbitrary amount injection if the caller is tampered.
        final jobSnap = await tx.get(firestore.collection('jobs').doc(jobId));
        if (!jobSnap.exists) throw Exception('Job $jobId not found');
        final jobData = jobSnap.data() as Map<String, dynamic>;
        final currentStatus = jobData['status'] as String? ?? '';
        // Idempotency: already cancelled means the refund was already issued.
        if (currentStatus == 'cancelled') return;
        if (currentStatus != 'paid_escrow') {
          throw Exception('Cannot cancel job in status "$currentStatus"');
        }
        // Use the authoritative amount from Firestore, not the caller-supplied value.
        final authorisedAmount =
            (jobData['totalAmount'] as num? ?? totalAmount).toDouble();

        tx.update(firestore.collection('jobs').doc(jobId), {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
        tx.update(firestore.collection('users').doc(customerId), {
          'balance': FieldValue.increment(authorisedAmount),
        });
        tx.set(firestore.collection('transactions').doc(), {
          'userId': customerId,
          'amount': authorisedAmount,
          'title': 'ביטול הזמנה — החזר כספי',
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'refund',
          'jobId': jobId,
        });
      });

      if (chatRoomId.isNotEmpty) {
        await firestore
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': 'system',
          'message': '❌ ההזמנה בוטלה. הסכום הוחזר לארנק הלקוח.',
          'type': 'text',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      return true;
    } catch (e) {
      debugPrint("cancelEscrow error: $e");
      return false;
    }
  }

  // ── Refund after dispute: admin resolves in customer's favour ────────────
  static Future<bool> refundDisputedJob({
    required String jobId,
    required String customerId,
    required double totalAmount,
    FirebaseFirestore? db,
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;
    try {
      await firestore.runTransaction((tx) async {
        // Read job first — idempotency guard and amount validation.
        final jobSnap = await tx.get(firestore.collection('jobs').doc(jobId));
        if (!jobSnap.exists) throw Exception('Job $jobId not found');
        final jobData = jobSnap.data() as Map<String, dynamic>;
        final currentStatus = jobData['status'] as String? ?? '';
        // Already resolved — don't issue a second refund.
        if (currentStatus == 'refunded') return;
        final authorisedAmount =
            (jobData['totalAmount'] as num? ?? totalAmount).toDouble();

        tx.update(firestore.collection('jobs').doc(jobId), {
          'status': 'refunded',
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': 'admin',
          'resolution': 'refund',
        });
        tx.update(firestore.collection('users').doc(customerId), {
          'balance': FieldValue.increment(authorisedAmount),
        });
        tx.set(firestore.collection('transactions').doc(), {
          'userId': customerId,
          'amount': authorisedAmount,
          'title': 'החזר כספי — מחלוקת נפתרה לטובתך',
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'refund',
          'jobId': jobId,
        });
      });
      return true;
    } catch (e) {
      debugPrint("refundDisputedJob error: $e");
      return false;
    }
  }

  // Returns null on success, or an error string to show the user.
  static Future<String?> releaseEscrowFundsWithError({
    required String jobId,
    required String expertId,
    required String expertName,
    required String customerName,
    required double totalAmount,
  }) async {
    try {
      debugPrint("[PPR-CLIENT] calling processPaymentRelease: jobId=$jobId expertId=$expertId total=$totalAmount");
      final result = await FirebaseFunctions.instance
          .httpsCallable('processPaymentRelease')
          .call({
        'jobId': jobId,
        'expertId': expertId,
        'expertName': expertName,
        'customerName': customerName,
        'totalAmount': totalAmount,
      });
      debugPrint("[PPR-CLIENT] success: ${result.data}");
      return null; // no error
    } on FirebaseFunctionsException catch (e) {
      final msg = "[${e.code}] ${e.message}${e.details != null ? ' | details: ${e.details}' : ''}";
      debugPrint("[PPR-CLIENT] FirebaseFunctionsException: $msg");
      return msg;
    } catch (e) {
      debugPrint("[PPR-CLIENT] unexpected error: $e");
      return e.toString();
    }
  }

  static Future<bool> releaseEscrowFunds({
    required String jobId,
    required String expertId,
    required String expertName,
    required String customerName,
    required double totalAmount,
    FirebaseFirestore? db, // kept for API compatibility; ignored (Cloud Function handles DB)
  }) async {
    final error = await releaseEscrowFundsWithError(
      jobId: jobId,
      expertId: expertId,
      expertName: expertName,
      customerName: customerName,
      totalAmount: totalAmount,
    );
    return error == null;
  }

  // ── Policy-aware cancellation — calls processCancellation Cloud Function ───
  // cancelledBy: 'customer' | 'provider'
  // Returns a map with: success, newStatus, isPenalty, customerCredit, expertCredit.
  // Throws a user-readable String on error.
  static Future<Map<String, dynamic>> cancelWithPolicy({
    required String jobId,
    required String cancelledBy,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('processCancellation')
          .call({'jobId': jobId, 'cancelledBy': cancelledBy});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw (e.message ?? e.code);
    } catch (e) {
      throw e.toString();
    }
  }
}