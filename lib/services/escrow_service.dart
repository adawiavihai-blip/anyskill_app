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

    // ── Pet Stay Tracker gate (v13.0.0) ───────────────────────────────
    // Quote payment from chat bypasses the expert-profile dog picker, so
    // we must block pet-service quotes here and route the user through
    // the proper flow. Cheap: single read of the provider's user doc +
    // optional category schema read.
    try {
      final providerSnap = await _db.collection('users').doc(providerId).get();
      final category =
          (providerSnap.data() ?? {})['serviceType']?.toString() ?? '';
      if (category.isNotEmpty) {
        final catSnap = await _db
            .collection('categories')
            .where('name', isEqualTo: category)
            .limit(1)
            .get();
        if (catSnap.docs.isNotEmpty) {
          final schemaRaw =
              catSnap.docs.first.data()['serviceSchema'] as Map?;
          final walkTracking = schemaRaw?['walkTracking'] == true;
          final dailyProof = schemaRaw?['dailyProof'] == true;
          if (walkTracking || dailyProof) {
            return 'זהו שירות פנסיון/דוגווקר — יש להזמין מפרופיל הספק כדי לצרף פרופיל כלב';
          }
        }
      }
    } catch (e) {
      // Fail open — if the pre-check errors we don't block real payments.
      debugPrint('[Escrow] pet-gate pre-check failed: $e');
    }

    try {
      final adminSettingsRef = _db
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings');

      String? createdJobId;

      await _db.runTransaction((tx) async {
        // ── Read required docs (v15.x: layered commission) ─────────────────
        // ORDER MATTERS: every tx.get MUST happen before any tx.set/update.
        final clientDoc   = await tx.get(_db.collection('users').doc(clientId));
        final adminDoc    = await tx.get(adminSettingsRef);
        final quoteDoc    = await tx.get(_db.collection('quotes').doc(quoteId));
        final providerDoc = await tx.get(_db.collection('users').doc(providerId));

        // Provider's serviceType drives the category-level commission lookup.
        final providerData = providerDoc.data() ?? {};
        final providerCategory = (providerData['serviceType'] ?? '').toString();

        // Conditionally read category override. Using category NAME as the
        // doc ID (consistent with provider.serviceType storing the name).
        DocumentSnapshot<Map<String, dynamic>>? categoryCommissionDoc;
        if (providerCategory.isNotEmpty) {
          categoryCommissionDoc = await tx.get(
            _db.collection('category_commissions').doc(providerCategory),
          );
        }

        // Guard: already paid (idempotency)
        final currentStatus = (quoteDoc.data() ?? {})['status']?.toString() ?? '';
        if (currentStatus == 'paid') return;

        final clientBalance =
            ((clientDoc.data() ?? {})['balance'] as num? ?? 0).toDouble();
        if (clientBalance < amount) {
          throw Exception('אין מספיק יתרה בארנק. נדרשת יתרה של ₪${amount.toStringAsFixed(0)}.');
        }

        // ── Resolve effective commission (custom > category > global) ──────
        // All percentages below are fractions (0.10 = 10%) to match the
        // existing feePercentage convention.
        double feePct = ((adminDoc.data() ?? {})['feePercentage'] as num? ?? 0.1)
            .toDouble();
        String feeSource = 'global';

        // Layer 2: category override
        if (categoryCommissionDoc != null && categoryCommissionDoc.exists) {
          final catPct = (categoryCommissionDoc.data()?['percentage'] as num?)
              ?.toDouble();
          if (catPct != null) {
            feePct = catPct / 100;
            feeSource = 'category';
          }
        }

        // Layer 3: per-provider custom override (highest priority)
        final customActive = providerData['customCommissionActive'] == true;
        final custom = providerData['customCommission'];
        if (customActive && custom is Map) {
          final pct = (custom['percentage'] as num?)?.toDouble();
          final expiresAt = custom['expiresAt'];
          DateTime? expiresDt;
          if (expiresAt is Timestamp) expiresDt = expiresAt.toDate();
          final live = expiresDt == null || expiresDt.isAfter(DateTime.now());
          if (pct != null && live) {
            feePct = pct / 100;
            feeSource = 'custom';
          }
        }

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
          'commissionFeePct':   feePct * 100, // 0-100 scale for readability
          'commissionSource':   feeSource,
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
