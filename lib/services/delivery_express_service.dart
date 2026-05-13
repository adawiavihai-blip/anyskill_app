// Delivery Express service — Firestore CRUD + streams for the emergency
// courier dispatch flow.
//
// Boundaries:
//   • Customer creates / watches / cancels — `createAuction`,
//     `watchAuction`, `watchOffers`, `selectOffer`, `cancelAuction`.
//   • Provider (courier) receives + responds —
//     `watchActiveAuctionsForProvider`, `submitOffer`.
//   • Cloud Functions own everything that touches `notifiedProviderIds`,
//     `currentRadiusKm` and customer FCM. Client never writes those.
//
// Status transitions are documented in the model file. The service stays
// thin — it doesn't enforce transitions itself (Firestore rules do).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/delivery_express_constants.dart';
import '../models/delivery_express.dart';
import '../models/delivery_profile.dart';
import 'delivery_express_pricing_service.dart';

class DeliveryExpressService {
  static final _db = FirebaseFirestore.instance;
  static const _kCollection = 'delivery_express';

  // ═══════════════════════════════════════════════════════════════════════
  // CUSTOMER SIDE
  // ═══════════════════════════════════════════════════════════════════════

  /// Creates a new auction with `status='searching'`. Returns the new
  /// `auctionId`. Throws on failure (caller wraps in try/catch + ErrorMapper).
  static Future<String> createAuction({
    required String customerId,
    required String customerName,
    required String packageType,
    required String urgencyReason,
    String packageDescription = '',
    String recipientName = '',
    String recipientPhone = '',
    required DeliveryExpressLocation pickup,
    required DeliveryExpressLocation dropoff,
    required double distanceKm,
    List<String> photoUrls = const [],
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(
      Duration(seconds: DeliveryExpressConfig.expireAfter),
    );
    final ref = _db.collection(_kCollection).doc();
    final auction = DeliveryExpress(
      id: ref.id,
      customerId: customerId,
      customerName: customerName,
      createdAt: now,
      expiresAt: expiresAt,
      status: DeliveryExpressStatus.searching,
      packageType: packageType,
      urgencyReason: urgencyReason,
      packageDescription: packageDescription,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      pickup: pickup,
      dropoff: dropoff,
      distanceKm: distanceKm,
      photoUrls: photoUrls,
      currentRadiusKm: DeliveryExpressConfig.initialRadiusKm,
    );
    await ref.set(auction.toMap());
    debugPrint('[DeliveryExpress] ✅ created ${ref.id} '
        '(package=$packageType, distance=${distanceKm.toStringAsFixed(1)} km)');
    return ref.id;
  }

  /// Stream the auction doc.
  static Stream<DeliveryExpress?> watchAuction(String auctionId) {
    return _db
        .collection(_kCollection)
        .doc(auctionId)
        .snapshots()
        .map((s) => s.exists ? DeliveryExpress.fromDoc(s) : null);
  }

  /// Stream offers as they arrive — sorted by recommendation score so
  /// the offers screen renders the recommended at index 0.
  static Stream<List<DeliveryExpressOffer>> watchOffers(String auctionId) {
    return _db
        .collection(_kCollection)
        .doc(auctionId)
        .collection('offers')
        .orderBy('createdAt')
        .limit(DeliveryExpressConfig.maxOffersToDisplay)
        .snapshots()
        .map((q) {
      final list = q.docs.map(DeliveryExpressOffer.fromDoc).toList();
      list.sort(
          (a, b) => b.recommendationScore.compareTo(a.recommendationScore));
      return list;
    });
  }

  /// Customer picks an offer. Atomic transaction with status-flip check.
  /// Returns null on success, Hebrew error string on failure.
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
        if (aStatus != DeliveryExpressStatus.searching &&
            aStatus != DeliveryExpressStatus.hasOffers) {
          throw 'הקריאה כבר נסגרה';
        }
        final oSnap = await tx.get(offerRef);
        if (!oSnap.exists) throw 'ההצעה לא נמצאה';
        final oData = oSnap.data() ?? {};
        if (oData['status'] != DeliveryExpressOfferStatus.pending) {
          throw 'ההצעה כבר אינה זמינה';
        }
        tx.update(auctionRef, {
          'status': DeliveryExpressStatus.matched,
          'selectedOfferId': offerId,
          'selectedProviderId': oData['providerId'],
          'matchedAt': FieldValue.serverTimestamp(),
        });
        tx.update(offerRef, {
          'status': DeliveryExpressOfferStatus.selected,
        });
      });
      return null;
    } catch (e) {
      debugPrint('[DeliveryExpress] selectOffer error: $e');
      return e is String ? e : e.toString();
    }
  }

  /// Customer aborts before selecting.
  static Future<void> cancelAuction({
    required String auctionId,
    String reason = 'customer_cancelled',
  }) async {
    try {
      await _db.collection(_kCollection).doc(auctionId).update({
        'status': DeliveryExpressStatus.cancelled,
        'cancellationReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[DeliveryExpress] ✅ cancelled $auctionId ($reason)');
    } catch (e) {
      debugPrint('[DeliveryExpress] cancelAuction error: $e');
      rethrow;
    }
  }

  /// Updates the matched job id once Pay & Secure has produced a job doc.
  static Future<void> markMatchedJob({
    required String auctionId,
    required String jobId,
  }) async {
    await _db.collection(_kCollection).doc(auctionId).update({
      'matchedJobId': jobId,
      'matchedJobCreatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Direct booking from a Delivery Express offer. Delegates to the
  /// `bookFromDeliveryExpressOffer` Cloud Function so the atomic Pay &
  /// Secure transaction runs with Admin SDK.
  ///
  /// Idempotency (CLAUDE.md §60): sends
  /// `clientReqId: book_${auctionId}_${offerId}` — retries within 1h
  /// return the cached result instead of double-booking.
  static Future<({String? jobId, String? error})> bookFromOffer({
    required DeliveryExpress auction,
    required DeliveryExpressOffer offer,
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
          .httpsCallable('bookFromDeliveryExpressOffer')
          .call({
        'auctionId': auction.id,
        'offerId': offer.id,
        'clientReqId': 'book_${auction.id}_${offer.id}',
      }).timeout(const Duration(seconds: 30));

      final data = result.data as Map?;
      final jobId = data?['jobId'] as String?;
      if (data?['success'] == true && jobId != null) {
        debugPrint(
          '[DeliveryExpress] ✅ booked $jobId from auction ${auction.id} '
          '(provider=${offer.providerId}, total=₪${offer.totalPrice.round()})',
        );
        return (jobId: jobId, error: null);
      }
      return (jobId: null, error: 'אירעה שגיאה. נסה/י שוב');
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[DeliveryExpress] bookFromOffer CF error: ${e.code} ${e.message}');
      return (jobId: null, error: e.message ?? 'שגיאת שרת. נסה/י שוב');
    } catch (e) {
      debugPrint('[DeliveryExpress] bookFromOffer error: $e');
      return (jobId: null, error: 'אירעה שגיאה. נסה/י שוב');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PROVIDER SIDE
  // ═══════════════════════════════════════════════════════════════════════

  /// Stream of live auctions where this courier was notified by the
  /// dispatch CF. Used by opportunities_screen.dart to inject Delivery
  /// Express cards alongside the regular job_requests list.
  ///
  /// Same pattern as Flash Auction: client-side filter for `isLive`
  /// keeps the Firestore query single-field (no composite index needed).
  static Stream<List<DeliveryExpress>> watchActiveAuctionsForProvider(
    String providerId,
  ) {
    return _db
        .collection(_kCollection)
        .where('notifiedProviderIds', arrayContains: providerId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((q) {
      final all = q.docs.map(DeliveryExpress.fromDoc);
      return all.where((a) => a.isLive).toList();
    });
  }

  /// Courier commits to an ETA. Pricing computed server-truthfully from
  /// their stored profile — they don't pass it in.
  ///
  /// Returns the new offer id on success, null on failure.
  /// Returns 'duplicate' (special string) when the courier already has
  /// an active offer on this auction.
  static Future<String?> submitOffer({
    required String auctionId,
    required int etaMinutes,
    required String vehicleType,
    required DeliveryProfile providerProfile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // 1. Read the auction for package + distance + status check.
      final auctionRef = _db.collection(_kCollection).doc(auctionId);
      final aSnap = await auctionRef.get();
      if (!aSnap.exists) return null;
      final aData = aSnap.data() ?? {};
      final aStatus = aData['status'] as String? ?? '';
      if (aStatus != DeliveryExpressStatus.searching &&
          aStatus != DeliveryExpressStatus.hasOffers) {
        // Auction closed — silent no-op.
        return null;
      }
      final packageType =
          aData['packageType'] as String? ?? 'small_package';
      final distanceKm = (aData['distanceKm'] as num?)?.toDouble() ?? 0;

      // 2. Anti-duplicate: one active offer per (provider, auction) pair.
      final existing = await auctionRef
          .collection('offers')
          .where('providerId', isEqualTo: user.uid)
          .where('status', isEqualTo: DeliveryExpressOfferStatus.pending)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return 'duplicate';

      // 3. Read provider profile snapshot — name/rating/jobs/photo.
      final providerSnap =
          await _db.collection('users').doc(user.uid).get();
      final pData = providerSnap.data() ?? {};

      // 4. Compute price.
      final breakdown = DeliveryExpressPricingService.priceForProvider(
        providerProfile: providerProfile,
        packageType: packageType,
        distanceKm: distanceKm,
      );

      // 5. Atomic transaction: write offer + bump auction.offerCount.
      final offerRef = auctionRef.collection('offers').doc();
      final offer = DeliveryExpressOffer(
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
        vehicleType: vehicleType,
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
        if (aStatusTx != DeliveryExpressStatus.searching &&
            aStatusTx != DeliveryExpressStatus.hasOffers) {
          throw 'auction_closed';
        }
        tx.set(offerRef, offer.toMap());
        final updates = <String, Object?>{
          'offerCount': FieldValue.increment(1),
        };
        if (aStatusTx == DeliveryExpressStatus.searching) {
          updates['status'] = DeliveryExpressStatus.hasOffers;
        }
        tx.update(auctionRef, updates);
      });
      debugPrint(
          '[DeliveryExpress] ✅ offer ${offerRef.id} on $auctionId ($etaMinutes min)');
      return offerRef.id;
    } catch (e) {
      debugPrint('[DeliveryExpress] submitOffer error: $e');
      return null;
    }
  }

  /// Stream the courier's own offer for a given auction (if it exists).
  /// Used by the provider card so the courier sees live status
  /// (pending/selected/rejected) of their submitted offer.
  static Stream<DeliveryExpressOffer?> watchMyOffer({
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
      return DeliveryExpressOffer.fromDoc(q.docs.first);
    });
  }
}
