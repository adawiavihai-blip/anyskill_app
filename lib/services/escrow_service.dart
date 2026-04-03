import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Handles Escrow creation from an Official Quote approved by the client.
class EscrowService {
  EscrowService._();

  static final _db = FirebaseFirestore.instance;

  /// Called when a client taps "Pay & Secure in Escrow" on a quote card.
  ///
  /// Returns null on success, or a Hebrew error string to show the user.
  static Future<String?> payQuote({
    required String quoteId,
    required String chatMessageId,
    required String chatRoomId,
    required String providerId,
    required String providerName,
    required String clientId,
    required String clientName,
    required double amount,
    required String description,
  }) async {
    // ── Anti-fraud: block self-booking ─────────────────────────────────
    if (clientId == providerId) {
      return 'לא ניתן להזמין שירות מעצמך';
    }

    try {
      final adminSettingsRef = _db
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings');

      String? createdJobId;

      await _db.runTransaction((tx) async {
        // ── Read required docs ──────────────────────────────────────────────
        final clientDoc   = await tx.get(_db.collection('users').doc(clientId));
        final adminDoc    = await tx.get(adminSettingsRef);
        final quoteDoc    = await tx.get(_db.collection('quotes').doc(quoteId));

        // Guard: already paid (idempotency)
        final currentStatus = (quoteDoc.data() ?? {})['status']?.toString() ?? '';
        if (currentStatus == 'paid') return;

        final clientBalance =
            ((clientDoc.data() ?? {})['balance'] as num? ?? 0).toDouble();
        if (clientBalance < amount) {
          throw Exception('אין מספיק יתרה בארנק. נדרשת יתרה של ₪${amount.toStringAsFixed(0)}.');
        }

        final feePct =
            ((adminDoc.data() ?? {})['feePercentage'] as num? ?? 0.1).toDouble();
        final commission     = double.parse((amount * feePct).toStringAsFixed(2));
        final netToProvider  = double.parse((amount - commission).toStringAsFixed(2));

        // ── Create Job (escrow) ─────────────────────────────────────────────
        final jobRef = _db.collection('jobs').doc();
        createdJobId = jobRef.id;
        tx.set(jobRef, {
          'expertId':           providerId,
          'expertName':         providerName,
          'customerId':         clientId,
          'customerName':       clientName,
          'totalAmount':        amount,
          'netAmountForExpert': netToProvider,
          'commission':         commission,
          'description':        description,
          'status':             'paid_escrow',
          'source':             'quote',
          'quoteId':            quoteId,
          'chatRoomId':         chatRoomId,
          'createdAt':          FieldValue.serverTimestamp(),
          'clientReviewDone':   false,
          'providerReviewDone': false,
        });

        // ── Deduct client balance ───────────────────────────────────────────
        tx.update(_db.collection('users').doc(clientId), {
          'balance': FieldValue.increment(-amount),
        });

        // ── Credit provider pending balance ─────────────────────────────────
        tx.update(_db.collection('users').doc(providerId), {
          'pendingBalance': FieldValue.increment(netToProvider),
        });

        // ── Platform commission record ──────────────────────────────────────
        tx.set(_db.collection('platform_earnings').doc(), {
          'jobId':          jobRef.id,
          'amount':         commission,
          'sourceExpertId': providerId,
          'timestamp':      FieldValue.serverTimestamp(),
          'status':         'pending_escrow',
        });

        // ── Transaction log ─────────────────────────────────────────────────
        tx.set(_db.collection('transactions').doc(), {
          'senderId':      clientId,
          'senderName':    clientName,
          'receiverId':    providerId,
          'receiverName':  providerName,
          'amount':        amount,
          'type':          'quote_payment',
          'jobId':         jobRef.id,
          'quoteId':       quoteId,
          'payoutStatus':  'pending',
          'timestamp':     FieldValue.serverTimestamp(),
        });

        // ── Mark quote as paid ──────────────────────────────────────────────
        tx.update(_db.collection('quotes').doc(quoteId), {
          'status': 'paid',
          'jobId':  jobRef.id,
          'paidAt': FieldValue.serverTimestamp(),
        });

        // ── Update the chat message quoteStatus ────────────────────────────
        if (chatMessageId.isNotEmpty) {
          tx.update(
            _db
                .collection('chats')
                .doc(chatRoomId)
                .collection('messages')
                .doc(chatMessageId),
            {'quoteStatus': 'paid', 'jobId': jobRef.id},
          );
        }

        // ── Admin system balance ────────────────────────────────────────────
        tx.set(
          adminSettingsRef,
          {'totalPlatformBalance': FieldValue.increment(commission)},
          SetOptions(merge: true),
        );
      });

      // ── System message in chat (non-critical, outside transaction) ─────────
      if (createdJobId != null) {
        await _db
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId':  'system',
          'message':
              '✅ ₪${amount.toStringAsFixed(0)} נעולים באסקרו. העבודה יכולה להתחיל!',
          'type':      'system_alert',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      return null; // success
    } on FirebaseException catch (e) {
      debugPrint('EscrowService.payQuote FirebaseException: $e');
      return e.message ?? 'שגיאת מסד נתונים.';
    } catch (e) {
      debugPrint('EscrowService.payQuote error: $e');
      return e.toString().replaceAll('Exception: ', '');
    }
  }
}
