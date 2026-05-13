// Flash Auction service — Firestore CRUD + streams for the emergency
// motorcycle towing flow.
//
// Boundaries:
//   • Customer creates / watches / cancels — `createAuction`,
//     `watchAuction`, `watchOffers`, `selectOffer`, `cancelAuction`.
//   • Provider receives + responds — `watchActiveAuctionsForProvider`,
//     `submitOffer`.
//   • Cloud Functions (`dispatchFlashAuction`, `notifyOnFlashAuctionOffer`)
//     own everything that touches `notifiedProviderIds`, `currentRadiusKm`
//     and customer FCM. Client never writes those fields.
//
// Status transitions are documented in the model file. The service stays
// thin — it doesn't enforce transitions itself (Firestore rules do).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/flash_auction_constants.dart';
import '../models/flash_auction.dart';
import '../models/motorcycle_tow_profile.dart';
import 'flash_auction_pricing_service.dart';

class FlashAuctionService {
  static final _db = FirebaseFirestore.instance;
  static const _kCollection = 'flash_auctions';

  // ═══════════════════════════════════════════════════════════════════════
  // CUSTOMER SIDE
  // ═══════════════════════════════════════════════════════════════════════

  /// Creates a new auction with `status='searching'`. Returns the new
  /// `auctionId`. Throws on failure (caller wraps in try/catch and shows a
  /// snackbar via ErrorMapper §10).
  ///
  /// Server-managed fields (`notifiedProviderIds`, `currentRadiusKm`,
  /// FCM dispatch) are populated by `dispatchFlashAuction` CF on the next
  /// 30-second tick.
  static Future<String> createAuction({
    required String customerId,
    required String customerName,
    required String issueType,
    String issueDetails = '',
    required FlashAuctionLocation pickup,
    required FlashAuctionLocation dropoff,
    required double distanceKm,
    List<String> photoUrls = const [],
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(
      Duration(seconds: FlashAuctionConfig.expireAfter),
    );
    final ref = _db.collection(_kCollection).doc();
    final auction = FlashAuction(
      id: ref.id,
      customerId: customerId,
      customerName: customerName,
      createdAt: now,
      expiresAt: expiresAt,
      status: FlashAuctionStatus.searching,
      issueType: issueType,
      issueDetails: issueDetails,
      pickup: pickup,
      dropoff: dropoff,
      distanceKm: distanceKm,
      photoUrls: photoUrls,
      currentRadiusKm: FlashAuctionConfig.initialRadiusKm,
    );
    await ref.set(auction.toMap());
    debugPrint('[FlashAuction] ✅ created ${ref.id} '
        '(distance=${distanceKm.toStringAsFixed(1)} km)');
    return ref.id;
  }

  /// Stream the auction doc. Customer's screens key off this for
  /// `status` transitions + offer count. Returns null when the doc
  /// doesn't exist (deleted / wrong id).
  static Stream<FlashAuction?> watchAuction(String auctionId) {
    return _db
        .collection(_kCollection)
        .doc(auctionId)
        .snapshots()
        .map((s) => s.exists ? FlashAuction.fromDoc(s) : null);
  }

  /// Stream offers as they arrive — sorted by recommendation score so
  /// the offers screen renders the recommended one at the top by default.
  /// Capped at [FlashAuctionConfig.maxOffersToDisplay].
  static Stream<List<FlashAuctionOffer>> watchOffers(String auctionId) {
    return _db
        .collection(_kCollection)
        .doc(auctionId)
        .collection('offers')
        .orderBy('createdAt')
        .limit(FlashAuctionConfig.maxOffersToDisplay)
        .snapshots()
        .map((q) {
      final list = q.docs.map(FlashAuctionOffer.fromDoc).toList();
      // Client-side score sort — descending so the recommended is index 0.
      list.sort((a, b) => b.recommendationScore.compareTo(a.recommendationScore));
      return list;
    });
  }

  /// Customer picks an offer. Atomic transaction:
  ///   • Read the auction — must still be `searching` or `has_offers`.
  ///   • Read the offer — must still be `pending`.
  ///   • Write `auction.status='matched'` + `selectedOfferId` + `selectedProviderId`.
  ///   • Write `offer.status='selected'`.
  ///
  /// Race condition: if 2 customers somehow tap "select" on the same
  /// offer at the exact same instant (impossible per single-customer
  /// auction model, but cheap to guard), the second tx fails because the
  /// auction is already `matched`. Returns null on success, Hebrew error
  /// string on failure.
  static Future<String?> selectOffer({
    required String auctionId,
    required String offerId,
  }) async {
    try {
      final auctionRef = _db.collection(_kCollection).doc(auctionId);
      final offerRef = auctionRef.collection('offers').doc(offerId);
      await _db.runTransaction((tx) async {
        final aSnap = await tx.get(auctionRef);
        if (!aSnap.exists) throw 'הקריאה לא נמצאה';
        final aStatus = (aSnap.data() ?? {})['status'] as String? ?? '';
        if (aStatus != FlashAuctionStatus.searching &&
            aStatus != FlashAuctionStatus.hasOffers) {
          throw 'הקריאה כבר נסגרה';
        }
        final oSnap = await tx.get(offerRef);
        if (!oSnap.exists) throw 'ההצעה לא נמצאה';
        final oData = oSnap.data() ?? {};
        if (oData['status'] != FlashAuctionOfferStatus.pending) {
          throw 'ההצעה כבר אינה זמינה';
        }
        tx.update(auctionRef, {
          'status': FlashAuctionStatus.matched,
          'selectedOfferId': offerId,
          'selectedProviderId': oData['providerId'],
          'matchedAt': FieldValue.serverTimestamp(),
        });
        tx.update(offerRef, {'status': FlashAuctionOfferStatus.selected});
      });
      return null;
    } catch (e) {
      debugPrint('[FlashAuction] selectOffer error: $e');
      return e is String ? e : e.toString();
    }
  }

  /// Customer aborts before selecting. Sets `status='cancelled'` +
  /// optional reason. The dispatch CF picks this up on the next tick and
  /// stops sending notifications. (Active offers stay in the subcollection
  /// for audit but lose their relevance.)
  static Future<void> cancelAuction({
    required String auctionId,
    String reason = 'customer_cancelled',
  }) async {
    try {
      await _db.collection(_kCollection).doc(auctionId).update({
        'status': FlashAuctionStatus.cancelled,
        'cancellationReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[FlashAuction] ✅ cancelled $auctionId ($reason)');
    } catch (e) {
      debugPrint('[FlashAuction] cancelAuction error: $e');
      rethrow;
    }
  }

  /// Updates the matched job id on the auction once Pay & Secure has
  /// produced a `jobs/{id}` doc. The provider's tracking screen keys off
  /// this — when the field flips from null → non-null they navigate.
  static Future<void> markMatchedJob({
    required String auctionId,
    required String jobId,
  }) async {
    await _db.collection(_kCollection).doc(auctionId).update({
      'matchedJobId': jobId,
      'matchedJobCreatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// **Direct booking from a Flash Auction offer.** Delegates to the
  /// `bookFromFlashAuctionOffer` Cloud Function (CLAUDE.md §57) so the
  /// atomic Pay & Secure transaction runs with Admin SDK and bypasses the
  /// §50 audit rule that blocks client-side `pendingBalance` increments.
  ///
  /// Returns the new `jobId` on success, or a Hebrew error string. The
  /// caller pops back to Home and shows the result.
  ///
  /// **Idempotency (§60):** sends `clientReqId: book_${auctionId}_${offerId}`
  /// — retries within 1h return the cached result instead of double-booking.
  static Future<({String? jobId, String? error})> bookFromOffer({
    required FlashAuction auction,
    required FlashAuctionOffer offer,
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
          .httpsCallable('bookFromFlashAuctionOffer')
          .call({
        'auctionId': auction.id,
        'offerId': offer.id,
        'clientReqId': 'book_${auction.id}_${offer.id}',
      }).timeout(const Duration(seconds: 30));

      final data = result.data as Map?;
      final jobId = data?['jobId'] as String?;
      if (data?['success'] == true && jobId != null) {
        debugPrint(
          '[FlashAuction] ✅ booked $jobId from auction ${auction.id} '
          '(provider=${offer.providerId}, total=₪${offer.totalPrice.round()})',
        );
        return (jobId: jobId, error: null);
      }
      return (jobId: null, error: 'אירעה שגיאה. נסה/י שוב');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FlashAuction] bookFromOffer CF error: ${e.code} ${e.message}');
      return (jobId: null, error: e.message ?? 'שגיאת שרת. נסה/י שוב');
    } catch (e) {
      debugPrint('[FlashAuction] bookFromOffer error: $e');
      return (jobId: null, error: 'אירעה שגיאה. נסה/י שוב');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PROVIDER SIDE
  // ═══════════════════════════════════════════════════════════════════════

  /// Stream of live auctions where this provider was notified by the
  /// dispatch CF. Used by [opportunities_screen.dart] to inject Flash
  /// Auction cards alongside the regular job_requests list.
  ///
  /// Filters:
  ///   • `notifiedProviderIds` array-contains [providerId]
  ///   • `status` is searching | has_offers
  ///
  /// Note: a single-field array-contains query plus an inequality on
  /// `status` requires a composite index. We keep the query simple by
  /// only filtering on `array-contains` here and excluding closed
  /// auctions client-side. Cap at 20 to bound stream cost.
  static Stream<List<FlashAuction>> watchActiveAuctionsForProvider(
    String providerId,
  ) {
    return _db
        .collection(_kCollection)
        .where('notifiedProviderIds', arrayContains: providerId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((q) {
      final all = q.docs.map(FlashAuction.fromDoc);
      return all.where((a) => a.isLive).toList();
    });
  }

  /// Provider commits to an ETA. Pricing is computed server-truthfully
  /// from their stored profile — they don't pass it in. Snapshot fields
  /// (name, rating, jobsCount, isVerified, isVolunteer, isPro, image) are
  /// frozen onto the offer doc so the customer sees what was true at
  /// offer time.
  ///
  /// Returns the new offer id on success, null on failure.
  /// Returns 'duplicate' (special string) when the provider already has
  /// an active offer on this auction (we enforce 1 active offer per
  /// (provider, auction) pair).
  static Future<String?> submitOffer({
    required String auctionId,
    required int etaMinutes,
    required MotorcycleTowProfile providerProfile,
    DateTime? when,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // 1. Read the auction for distance + status check.
      final auctionRef = _db.collection(_kCollection).doc(auctionId);
      final aSnap = await auctionRef.get();
      if (!aSnap.exists) return null;
      final aData = aSnap.data() ?? {};
      final aStatus = aData['status'] as String? ?? '';
      if (aStatus != FlashAuctionStatus.searching &&
          aStatus != FlashAuctionStatus.hasOffers) {
        // Auction closed — silent no-op (provider's UI will hide soon).
        return null;
      }
      final distanceKm = (aData['distanceKm'] as num?)?.toDouble() ?? 0;

      // 2. Check duplicate offer (one per provider per auction).
      final existing = await auctionRef
          .collection('offers')
          .where('providerId', isEqualTo: user.uid)
          .where('status', isEqualTo: FlashAuctionOfferStatus.pending)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return 'duplicate';

      // 3. Read provider profile snapshot — name/rating/jobs/photo.
      final providerSnap =
          await _db.collection('users').doc(user.uid).get();
      final pData = providerSnap.data() ?? {};

      // 4. Compute price.
      final breakdown = FlashAuctionPricingService.priceForProvider(
        providerProfile: providerProfile,
        distanceKm: distanceKm,
        when: when,
      );

      // 5. Atomic transaction: write the offer + bump auction.offerCount
      //    (and flip status to 'has_offers' if it was still 'searching').
      final offerRef = auctionRef.collection('offers').doc();
      final offer = FlashAuctionOffer(
        id: offerRef.id,
        auctionId: auctionId,
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
        providerIsVolunteer:
            ((pData['volunteerTaskCount'] as num?)?.toInt() ?? 0) > 0,
        providerIsPro: pData['isAnySkillPro'] == true,
        etaMinutes: etaMinutes,
        totalPrice: breakdown.total,
        priceBreakdown: breakdown,
        createdAt: DateTime.now(),
      );

      await _db.runTransaction((tx) async {
        final aSnapTx = await tx.get(auctionRef);
        if (!aSnapTx.exists) throw 'auction_missing';
        final aDataTx = aSnapTx.data() ?? {};
        final aStatusTx = aDataTx['status'] as String? ?? '';
        // Re-check inside the tx — covers status flip races.
        if (aStatusTx != FlashAuctionStatus.searching &&
            aStatusTx != FlashAuctionStatus.hasOffers) {
          throw 'auction_closed';
        }
        tx.set(offerRef, offer.toMap());
        final updates = <String, Object?>{
          'offerCount': FieldValue.increment(1),
        };
        if (aStatusTx == FlashAuctionStatus.searching) {
          updates['status'] = FlashAuctionStatus.hasOffers;
        }
        tx.update(auctionRef, updates);
      });
      debugPrint(
          '[FlashAuction] ✅ offer ${offerRef.id} on $auctionId ($etaMinutes min)');
      return offerRef.id;
    } catch (e) {
      debugPrint('[FlashAuction] submitOffer error: $e');
      return null;
    }
  }

  /// Stream the provider's own offer for a given auction, if it exists.
  /// Used by the FlashAuctionProviderCard so the provider can see live
  /// status (pending/selected/rejected) of their submitted offer.
  static Stream<FlashAuctionOffer?> watchMyOffer({
    required String auctionId,
    required String providerId,
  }) {
    return _db
        .collection(_kCollection)
        .doc(auctionId)
        .collection('offers')
        .where('providerId', isEqualTo: providerId)
        .limit(1)
        .snapshots()
        .map((q) {
      if (q.docs.isEmpty) return null;
      return FlashAuctionOffer.fromDoc(q.docs.first);
    });
  }
}
