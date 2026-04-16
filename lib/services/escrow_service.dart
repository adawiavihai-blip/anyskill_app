import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Handles Escrow creation from an Official Quote approved by the client.
/// v15.x audit: the atomic transaction now runs SERVER-SIDE via the
/// `createEscrowPayment` CF, removing cross-user pendingBalance writes
/// from the client SDK.
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
    if (clientId == providerId) {
      return 'לא ניתן להזמין שירות מעצמך';
    }

    // Pet Stay Tracker gate (v13.0.0) — block pet-service quotes
    try {
      final providerSnap =
          await _db.collection('users').doc(providerId).get();
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
      debugPrint('[Escrow] pet-gate pre-check failed: $e');
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createEscrowPayment')
          .call({
        'quoteId': quoteId,
        'chatMessageId': chatMessageId,
        'chatRoomId': chatRoomId,
        'providerId': providerId,
        'providerName': providerName,
        'clientName': clientName,
        'amount': amount,
        'description': description,
      }).timeout(const Duration(seconds: 30));

      final data = result.data as Map?;
      if (data?['success'] == true) return null;
      return 'שגיאה לא צפויה';
    } on FirebaseFunctionsException catch (e) {
      debugPrint('EscrowService.payQuote CF error: ${e.code} ${e.message}');
      return e.message ?? 'שגיאת שרת.';
    } catch (e) {
      debugPrint('EscrowService.payQuote error: $e');
      return e.toString().replaceAll('Exception: ', '');
    }
  }
}
