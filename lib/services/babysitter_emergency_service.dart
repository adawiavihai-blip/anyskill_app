// Babysitter Emergency service — Firestore CRUD + streams for the
// emergency babysitter dispatch flow (CLAUDE.md §76).
//
// Sister-module to FlashAuctionService (CLAUDE.md §57). Same boundaries:
//   • Customer creates / watches / cancels — `createEmergency`,
//     `watchEmergency`, `watchOffers`, `selectOffer`, `cancelEmergency`.
//   • Provider receives + responds — `watchActiveEmergenciesForProvider`,
//     `submitOffer`.
//   • Cloud Functions (`dispatchBabysitterEmergency`,
//     `notifyOnBabysitterEmergencyOffer`) own everything that touches
//     `notifiedProviderIds`, `currentRadiusKm` and customer FCM. Client
//     never writes those fields (rules block it).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/babysitter_emergency_constants.dart';
import '../models/babysitter_emergency.dart';
import '../models/babysitter_profile.dart';
import 'babysitter_emergency_pricing_service.dart';

class BabysitterEmergencyService {
  static final _db = FirebaseFirestore.instance;
  static const _kCollection = 'babysitter_emergencies';

  // ═══════════════════════════════════════════════════════════════════════
  // CUSTOMER SIDE
  // ═══════════════════════════════════════════════════════════════════════

  /// Creates a new emergency with `status='searching'`. Returns the new
  /// `emergencyId`. Throws on failure (caller wraps in try/catch and
  /// shows a snackbar via ErrorMapper §10).
  ///
  /// Server-managed fields (`notifiedProviderIds`, `currentRadiusKm`,
  /// FCM dispatch) are populated by `dispatchBabysitterEmergency` CF on
  /// the next 30-second tick AND immediately by `onBabysitterEmergencyCreate`.
  static Future<String> createEmergency({
    required String customerId,
    required String customerName,
    required String reason,
    String reasonDetails = '',
    required int numChildren,
    List<String> childrenAgeGroups = const [],
    required DateTime agreedStartTime,
    required DateTime agreedEndTime,
    required BabysitterEmergencyLocation location,
    String specialNotes = '',
    bool isHoliday = false,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(
      Duration(seconds: BabysitterEmergencyConfig.expireAfter),
    );
    final ref = _db.collection(_kCollection).doc();
    final emergency = BabysitterEmergency(
      id: ref.id,
      customerId: customerId,
      customerName: customerName,
      createdAt: now,
      expiresAt: expiresAt,
      status: BabysitterEmergencyStatus.searching,
      reason: reason,
      reasonDetails: reasonDetails,
      numChildren: numChildren,
      childrenAgeGroups: childrenAgeGroups,
      agreedStartTime: agreedStartTime,
      agreedEndTime: agreedEndTime,
      location: location,
      specialNotes: specialNotes,
      isHoliday: isHoliday,
      currentRadiusKm: BabysitterEmergencyConfig.initialRadiusKm,
    );
    await ref.set(emergency.toMap());
    debugPrint('[BabysitterEmergency] ✅ created ${ref.id} '
        '(numChildren=$numChildren, duration=${emergency.durationHours.toStringAsFixed(1)}h)');
    return ref.id;
  }

  /// Stream the emergency doc. Customer's screens key off this for
  /// status transitions + offer count.
  static Stream<BabysitterEmergency?> watchEmergency(String emergencyId) {
    return _db
        .collection(_kCollection)
        .doc(emergencyId)
        .snapshots()
        .map((s) => s.exists ? BabysitterEmergency.fromDoc(s) : null);
  }

  /// Stream offers as they arrive — sorted by recommendation score.
  static Stream<List<BabysitterEmergencyOffer>> watchOffers(
    String emergencyId,
  ) {
    return _db
        .collection(_kCollection)
        .doc(emergencyId)
        .collection('offers')
        .orderBy('createdAt')
        .limit(BabysitterEmergencyConfig.maxOffersToDisplay)
        .snapshots()
        .map((q) {
      final list = q.docs.map(BabysitterEmergencyOffer.fromDoc).toList();
      list.sort(
        (a, b) => b.recommendationScore.compareTo(a.recommendationScore),
      );
      return list;
    });
  }

  /// Customer aborts before selecting. Sets `status='cancelled'` +
  /// optional reason. The dispatch CF picks this up and stops sending
  /// notifications.
  static Future<void> cancelEmergency({
    required String emergencyId,
    String reason = 'customer_cancelled',
  }) async {
    try {
      await _db.collection(_kCollection).doc(emergencyId).update({
        'status': BabysitterEmergencyStatus.cancelled,
        'cancellationReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[BabysitterEmergency] ✅ cancelled $emergencyId ($reason)');
    } catch (e) {
      debugPrint('[BabysitterEmergency] cancelEmergency error: $e');
      rethrow;
    }
  }

  /// **Direct booking from a babysitter emergency offer.** Delegates to the
  /// `bookFromBabysitterEmergencyOffer` Cloud Function (CLAUDE.md §76).
  /// Server-side atomic transaction runs with Admin SDK so it bypasses the
  /// §50 audit rule that blocks client-side `pendingBalance` increments.
  ///
  /// Returns the new `jobId` on success or a Hebrew error string. The
  /// caller pops back to Home and shows the result.
  ///
  /// **Idempotency (§60):** sends `clientReqId: book_${emergencyId}_${offerId}`
  /// — retries within 1h return the cached result instead of double-booking.
  static Future<({String? jobId, String? error})> bookFromOffer({
    required BabysitterEmergency emergency,
    required BabysitterEmergencyOffer offer,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return (jobId: null, error: 'יש להתחבר לפני ביצוע הזמנה');
    }
    if (user.uid == offer.providerId) {
      return (jobId: null, error: 'לא ניתן להזמין שירות מעצמך');
    }
    if (offer.totalPrice <= 0) {
      return (jobId: null, error: 'מחיר לא חוקי בהצעה');
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('bookFromBabysitterEmergencyOffer')
          .call({
        'emergencyId': emergency.id,
        'offerId': offer.id,
        'clientReqId': 'book_${emergency.id}_${offer.id}',
      }).timeout(const Duration(seconds: 30));

      final data = result.data as Map?;
      final jobId = data?['jobId'] as String?;
      if (data?['success'] == true && jobId != null) {
        debugPrint(
          '[BabysitterEmergency] ✅ booked $jobId from emergency '
          '${emergency.id} (provider=${offer.providerId}, '
          'total=₪${offer.totalPrice.round()})',
        );
        return (jobId: jobId, error: null);
      }
      return (jobId: null, error: 'אירעה שגיאה. נסה/י שוב');
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[BabysitterEmergency] bookFromOffer CF error: ${e.code} ${e.message}',
      );
      return (jobId: null, error: e.message ?? 'שגיאת שרת. נסה/י שוב');
    } catch (e) {
      debugPrint('[BabysitterEmergency] bookFromOffer error: $e');
      return (jobId: null, error: 'אירעה שגיאה. נסה/י שוב');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PROVIDER SIDE
  // ═══════════════════════════════════════════════════════════════════════

  /// Stream of live emergencies where this provider was notified by the
  /// dispatch CF. Used by `opportunities_screen.dart` to inject emergency
  /// cards alongside the regular job_requests + flash auction strips.
  ///
  /// Filters (mirrors FlashAuctionService.watchActiveAuctionsForProvider):
  ///   • `notifiedProviderIds` array-contains [providerId]
  ///   • `status` is searching | has_offers (filtered client-side)
  static Stream<List<BabysitterEmergency>>
      watchActiveEmergenciesForProvider(
    String providerId,
  ) {
    return _db
        .collection(_kCollection)
        .where('notifiedProviderIds', arrayContains: providerId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((q) {
      final all = q.docs.map(BabysitterEmergency.fromDoc);
      return all.where((a) => a.isLive).toList();
    });
  }

  /// Provider commits to an ETA. Pricing is computed server-truthfully
  /// from their stored profile — they don't pass it in. Snapshot fields
  /// (name, rating, jobsCount, isVerified, isBackgroundChecked,
  /// hasFirstAid, image) are frozen onto the offer doc.
  ///
  /// Returns the new offer id on success, null on failure.
  /// Returns 'duplicate' when the provider already has an active offer
  /// on this emergency (1 active offer per (provider, emergency) pair).
  static Future<String?> submitOffer({
    required String emergencyId,
    required int etaMinutes,
    required BabysitterProfile providerProfile,
    DateTime? when,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // 1. Read the emergency for booking window + status check.
      final emergencyRef = _db.collection(_kCollection).doc(emergencyId);
      final eSnap = await emergencyRef.get();
      if (!eSnap.exists) return null;
      final eData = eSnap.data() ?? {};
      final eStatus = eData['status'] as String? ?? '';
      if (eStatus != BabysitterEmergencyStatus.searching &&
          eStatus != BabysitterEmergencyStatus.hasOffers) {
        return null;
      }
      final emergency = BabysitterEmergency.fromMap(eData, id: emergencyId);

      // 2. Check duplicate offer.
      final existing = await emergencyRef
          .collection('offers')
          .where('providerId', isEqualTo: user.uid)
          .where('status',
              isEqualTo: BabysitterEmergencyOfferStatus.pending)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return 'duplicate';

      // 3. Read provider profile snapshot.
      final providerSnap =
          await _db.collection('users').doc(user.uid).get();
      final pData = providerSnap.data() ?? {};

      // 4. Compute price.
      final breakdown = BabysitterEmergencyPricingService.priceForProvider(
        pricing: providerProfile.pricing,
        numChildren: emergency.numChildren,
        agreedStart: emergency.agreedStartTime,
        agreedEnd: emergency.agreedEndTime,
        isHoliday: emergency.isHoliday,
        now: when,
      );

      // 5. Detect first-aid certification — at least one verified cert
      //    of type 'first_aid' or 'bls' counts.
      final hasFirstAid = providerProfile.certifications.any((c) =>
          c.verified && (c.type == 'first_aid' || c.type == 'bls'));

      // 6. Atomic transaction: write the offer + bump offerCount.
      final offerRef = emergencyRef.collection('offers').doc();
      final offer = BabysitterEmergencyOffer(
        id: offerRef.id,
        emergencyId: emergencyId,
        providerId: user.uid,
        providerName: (pData['name'] as String?) ?? '',
        providerImageUrl: (pData['profileImage'] as String?) ?? '',
        providerRating: (pData['rating'] as num?)?.toDouble() ?? 0,
        providerReviewsCount:
            (pData['reviewsCount'] as num?)?.toInt() ?? 0,
        providerJobsCount: (pData['orderCount'] as num? ??
                pData['completedJobsCount'] as num? ??
                0)
            .toInt(),
        providerIsVerified: pData['isVerified'] == true,
        providerIsBackgroundChecked:
            providerProfile.trust.backgroundChecked,
        providerHasFirstAid: hasFirstAid,
        providerIsVolunteer:
            ((pData['volunteerTaskCount'] as num?)?.toInt() ?? 0) > 0,
        providerIsPro: pData['isAnySkillPro'] == true,
        providerYearsExperience: providerProfile.experience.yearsExperience,
        etaMinutes: etaMinutes,
        totalPrice: breakdown.total,
        priceBreakdown: breakdown,
        createdAt: DateTime.now(),
      );

      await _db.runTransaction((tx) async {
        final eSnapTx = await tx.get(emergencyRef);
        if (!eSnapTx.exists) throw 'emergency_missing';
        final eDataTx = eSnapTx.data() ?? {};
        final eStatusTx = eDataTx['status'] as String? ?? '';
        if (eStatusTx != BabysitterEmergencyStatus.searching &&
            eStatusTx != BabysitterEmergencyStatus.hasOffers) {
          throw 'emergency_closed';
        }
        tx.set(offerRef, offer.toMap());
        final updates = <String, Object?>{
          'offerCount': FieldValue.increment(1),
        };
        if (eStatusTx == BabysitterEmergencyStatus.searching) {
          updates['status'] = BabysitterEmergencyStatus.hasOffers;
        }
        tx.update(emergencyRef, updates);
      });
      debugPrint(
          '[BabysitterEmergency] ✅ offer ${offerRef.id} on $emergencyId '
          '($etaMinutes min, ₪${offer.totalPrice.round()})');
      return offerRef.id;
    } catch (e) {
      debugPrint('[BabysitterEmergency] submitOffer error: $e');
      return null;
    }
  }

  /// Stream the provider's own offer for a given emergency, if it exists.
  static Stream<BabysitterEmergencyOffer?> watchMyOffer({
    required String emergencyId,
    required String providerId,
  }) {
    return _db
        .collection(_kCollection)
        .doc(emergencyId)
        .collection('offers')
        .where('providerId', isEqualTo: providerId)
        .limit(1)
        .snapshots()
        .map((q) {
      if (q.docs.isEmpty) return null;
      return BabysitterEmergencyOffer.fromDoc(q.docs.first);
    });
  }
}
