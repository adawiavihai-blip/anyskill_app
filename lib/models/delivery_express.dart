// Delivery Express model — emergency courier dispatch.
//
// Lives at `delivery_express/{auctionId}` with offers in
// `delivery_express/{auctionId}/offers/{offerId}` (subcollection).
//
// Pattern mirrors Flash Auction (lib/models/flash_auction.dart, CLAUDE.md
// §57). Two locations (pickup + dropoff) like motorcycle towing — NOT the
// single-location babysitter pattern.
//
// Lifecycle (per CLAUDE.md §57 §76):
//   1. Customer creates auction → status='searching'
//   2. Provider sends offer → first offer flips status→'has_offers'
//   3. Customer picks an offer → status='matched' + selectedOfferId
//   4. Pay & Secure runs via `bookFromDeliveryExpressOffer` CF →
//      matchedJobId populated → regular job-lifecycle layer takes over
//
// CF (`dispatchDeliveryExpress`) writes notifiedProviderIds +
// currentRadiusKm + expiresAt. Client never writes those fields (rules
// block it).
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_map.dart';

/// Root auction doc.
class DeliveryExpress {
  /// Firestore doc id. Empty string when not yet persisted.
  final String id;
  final String customerId;
  final String customerName;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// One of [DeliveryExpressStatus] strings.
  final String status;

  /// One of [DeliveryExpressPackageType] strings.
  final String packageType;

  /// One of [DeliveryExpressUrgencyReason] strings.
  final String urgencyReason;

  /// Free-text description from the customer (optional). Examples:
  /// "מסמכי חוזה לחתימה", "זר ליום הולדת", etc.
  final String packageDescription;

  /// Customer's contact for the recipient (so the courier can call from
  /// the dropoff location if needed). Empty when the customer is the
  /// recipient. Hidden from offers until match.
  final String recipientName;
  final String recipientPhone;

  final DeliveryExpressLocation pickup;
  final DeliveryExpressLocation dropoff;

  /// Haversine distance pickup→dropoff (km). Used by the provider's
  /// pricing math and by the dispatch CF for radius checks (against
  /// pickup location).
  final double distanceKm;

  /// Optional Storage URLs the customer attached (e.g. photo of the
  /// package or written address). Most deliveries skip photos.
  final List<String> photoUrls;

  /// Current dispatch radius. Bumped 5 → 10 → 15 by the CF over time.
  final double currentRadiusKm;
  /// Provider uids notified by the dispatch CF. CF appends as tiers fire.
  final List<String> notifiedProviderIds;
  /// Number of offers received (denormalized from subcollection).
  final int offerCount;

  /// Populated when the customer picks an offer.
  final String? selectedOfferId;
  final String? selectedProviderId;
  /// Populated once Pay & Secure has produced a `jobs/{id}` doc.
  final String? matchedJobId;

  final String? cancellationReason;

  /// Server-set reason for `status == 'expired'` (e.g. `'no_providers_found'`,
  /// `'missing_pickup_coords'`). Read-only on the client.
  final String? expiredReason;
  /// Hebrew-localized expiry reason written by the CF — drives the
  /// "נסה שנית" screen subtitle. Read-only on the client.
  final String? expiredReasonHebrew;

  const DeliveryExpress({
    required this.id,
    required this.customerId,
    this.customerName = '',
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.packageType,
    this.urgencyReason = 'other',
    this.packageDescription = '',
    this.recipientName = '',
    this.recipientPhone = '',
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    this.photoUrls = const [],
    this.currentRadiusKm = 5.0,
    this.notifiedProviderIds = const [],
    this.offerCount = 0,
    this.selectedOfferId,
    this.selectedProviderId,
    this.matchedJobId,
    this.cancellationReason,
    this.expiredReason,
    this.expiredReasonHebrew,
  });

  /// True while the auction is still active (searching OR has_offers).
  bool get isLive => status == 'searching' || status == 'has_offers';

  /// Seconds until [expiresAt]. Negative when already expired.
  int get secondsRemaining =>
      expiresAt.difference(DateTime.now()).inSeconds;

  Map<String, dynamic> toMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': status,
        'packageType': packageType,
        'urgencyReason': urgencyReason,
        'packageDescription': packageDescription,
        if (recipientName.isNotEmpty) 'recipientName': recipientName,
        if (recipientPhone.isNotEmpty) 'recipientPhone': recipientPhone,
        'pickupLocation': pickup.toMap(),
        'dropoffLocation': dropoff.toMap(),
        'distanceKm': distanceKm,
        'photos': photoUrls,
        'currentRadiusKm': currentRadiusKm,
        'notifiedProviderIds': notifiedProviderIds,
        'offerCount': offerCount,
        if (selectedOfferId != null) 'selectedOfferId': selectedOfferId,
        if (selectedProviderId != null) 'selectedProviderId': selectedProviderId,
        if (matchedJobId != null) 'matchedJobId': matchedJobId,
        if (cancellationReason != null) 'cancellationReason': cancellationReason,
      };

  factory DeliveryExpress.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return DeliveryExpress.fromMap(raw, id: doc.id);
  }

  factory DeliveryExpress.fromMap(
    Map<String, dynamic> raw, {
    String id = '',
  }) {
    return DeliveryExpress(
      id: id,
      customerId: raw['customerId'] as String? ?? '',
      customerName: raw['customerName'] as String? ?? '',
      createdAt: _ts(raw['createdAt']) ?? DateTime.now(),
      expiresAt: _ts(raw['expiresAt']) ??
          DateTime.now().add(const Duration(minutes: 2)),
      status: raw['status'] as String? ?? 'searching',
      packageType: raw['packageType'] as String? ?? 'small_package',
      urgencyReason: raw['urgencyReason'] as String? ?? 'other',
      packageDescription: raw['packageDescription'] as String? ?? '',
      recipientName: raw['recipientName'] as String? ?? '',
      recipientPhone: raw['recipientPhone'] as String? ?? '',
      pickup: DeliveryExpressLocation.fromMap(safeMap(raw['pickupLocation'])),
      dropoff:
          DeliveryExpressLocation.fromMap(safeMap(raw['dropoffLocation'])),
      distanceKm: (raw['distanceKm'] as num?)?.toDouble() ?? 0,
      photoUrls:
          (raw['photos'] as List?)?.whereType<String>().toList() ?? const [],
      currentRadiusKm:
          (raw['currentRadiusKm'] as num?)?.toDouble() ?? 5.0,
      notifiedProviderIds:
          (raw['notifiedProviderIds'] as List?)?.whereType<String>().toList() ??
              const [],
      offerCount: (raw['offerCount'] as num?)?.toInt() ?? 0,
      selectedOfferId: raw['selectedOfferId'] as String?,
      selectedProviderId: raw['selectedProviderId'] as String?,
      matchedJobId: raw['matchedJobId'] as String?,
      cancellationReason: raw['cancellationReason'] as String?,
      expiredReason: raw['expiredReason'] as String?,
      expiredReasonHebrew: raw['expiredReasonHebrew'] as String?,
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

class DeliveryExpressLocation {
  final String address;
  /// Optional finer detail — apartment number, gate code, floor, etc.
  /// Hidden from the offer screen; only the matched courier sees it.
  final String details;
  final double? lat;
  final double? lng;

  const DeliveryExpressLocation({
    this.address = '',
    this.details = '',
    this.lat,
    this.lng,
  });

  bool get hasCoords => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
        'address': address,
        if (details.isNotEmpty) 'details': details,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  factory DeliveryExpressLocation.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const DeliveryExpressLocation();
    return DeliveryExpressLocation(
      address: raw['address'] as String? ?? '',
      details: raw['details'] as String? ?? '',
      lat: (raw['lat'] as num?)?.toDouble(),
      lng: (raw['lng'] as num?)?.toDouble(),
    );
  }

  DeliveryExpressLocation copyWith({
    String? address,
    String? details,
    double? lat,
    double? lng,
  }) =>
      DeliveryExpressLocation(
        address: address ?? this.address,
        details: details ?? this.details,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );
}

// ═════════════════════════════════════════════════════════════════════════
// OFFER — sub-doc at delivery_express/{id}/offers/{offerId}
// ═════════════════════════════════════════════════════════════════════════

/// Courier offer on a Delivery Express call. Provider snapshots are
/// frozen at offer-create time so the customer sees what was true when
/// the offer was sent.
class DeliveryExpressOffer {
  final String id;
  final String auctionId;
  final String providerId;
  final String providerName;
  final String providerImageUrl;
  final double providerRating;
  final int providerReviewsCount;
  final int providerJobsCount;
  final bool providerIsVerified;
  final bool providerIsVolunteer;
  final bool providerIsPro;

  /// Which of the courier's vehicles will be used. 'scooter' | 'car'.
  /// Used by the customer to gauge weather/safety + by the CF FCM body.
  final String vehicleType;

  /// Courier commits to picking up the package in this many minutes.
  /// This is the ONLY field the courier enters in their offer form.
  final int etaMinutes;

  /// Computed total — server-side authoritative; client display only.
  final double totalPrice;
  /// Detailed breakdown so the customer (and the eventual job doc) sees
  /// where each shekel came from.
  final DeliveryExpressPriceBreakdown priceBreakdown;

  final DateTime createdAt;
  final String status;

  const DeliveryExpressOffer({
    required this.id,
    required this.auctionId,
    required this.providerId,
    required this.providerName,
    this.providerImageUrl = '',
    this.providerRating = 0,
    this.providerReviewsCount = 0,
    this.providerJobsCount = 0,
    this.providerIsVerified = false,
    this.providerIsVolunteer = false,
    this.providerIsPro = false,
    this.vehicleType = 'scooter',
    required this.etaMinutes,
    required this.totalPrice,
    required this.priceBreakdown,
    required this.createdAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() => {
        'auctionId': auctionId,
        'providerId': providerId,
        'providerName': providerName,
        'providerImageUrl': providerImageUrl,
        'providerRating': providerRating,
        'providerReviewsCount': providerReviewsCount,
        'providerJobsCount': providerJobsCount,
        'providerIsVerified': providerIsVerified,
        'providerIsVolunteer': providerIsVolunteer,
        'providerIsPro': providerIsPro,
        'vehicleType': vehicleType,
        'etaMinutes': etaMinutes,
        'totalPrice': totalPrice,
        'priceBreakdown': priceBreakdown.toMap(),
        'createdAt': Timestamp.fromDate(createdAt),
        'status': status,
      };

  factory DeliveryExpressOffer.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return DeliveryExpressOffer.fromMap(raw, id: doc.id);
  }

  factory DeliveryExpressOffer.fromMap(
    Map<String, dynamic> raw, {
    required String id,
  }) {
    return DeliveryExpressOffer(
      id: id,
      auctionId: raw['auctionId'] as String? ?? '',
      providerId: raw['providerId'] as String? ?? '',
      providerName: raw['providerName'] as String? ?? '',
      providerImageUrl: raw['providerImageUrl'] as String? ?? '',
      providerRating: (raw['providerRating'] as num?)?.toDouble() ?? 0,
      providerReviewsCount:
          (raw['providerReviewsCount'] as num?)?.toInt() ?? 0,
      providerJobsCount: (raw['providerJobsCount'] as num?)?.toInt() ?? 0,
      providerIsVerified: raw['providerIsVerified'] == true,
      providerIsVolunteer: raw['providerIsVolunteer'] == true,
      providerIsPro: raw['providerIsPro'] == true,
      vehicleType: raw['vehicleType'] as String? ?? 'scooter',
      etaMinutes: (raw['etaMinutes'] as num?)?.toInt() ?? 0,
      totalPrice: (raw['totalPrice'] as num?)?.toDouble() ?? 0,
      priceBreakdown: DeliveryExpressPriceBreakdown.fromMap(
        safeMap(raw['priceBreakdown']),
      ),
      createdAt: (raw['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: raw['status'] as String? ?? 'pending',
    );
  }

  /// Recommended-offer score — same weights as Flash Auction.
  /// Higher = better. Customer-side offers screen ranks by this and
  /// tags index 0 as "המומלץ ביותר".
  double get recommendationScore {
    final etaScore = (60 - etaMinutes).clamp(-60, 60) * 2.0;
    final priceScore = (1000 - totalPrice).clamp(-1000, 1000) * 0.05;
    final ratingScore = providerRating * 20.0;
    final expScore = (providerJobsCount.clamp(0, 200)) * 0.1;
    return etaScore + priceScore + ratingScore + expScore;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// PRICE BREAKDOWN — frozen on each offer + the matched job's preferences
// ═════════════════════════════════════════════════════════════════════════
//
// Direct booking: after the customer picks an offer,
// `DeliveryExpressService.bookFromOffer` runs a single atomic tx (via the
// `bookFromDeliveryExpressOffer` Cloud Function) that creates the
// `jobs/{id}` doc + flips auction → matched + offer → selected. The
// price breakdown below travels onto `jobs/{id}.deliveryPreferences
// .priceBreakdown` so the courier's order screen and audit log see
// exactly what the customer was charged.

class DeliveryExpressPriceBreakdown {
  /// Base price for the chosen package type (e.g. ₪35 documents).
  final double base;
  /// Sum of any chosen add-ons (Delivery Express has no add-ons by
  /// default, but the field stays for parity with the CSM breakdown).
  final double addOnsTotal;
  /// Always-on immediate surcharge — Delivery Express ALWAYS uses
  /// `timing: 'immediate'`, so this row is non-zero whenever the
  /// courier's `availability.immediate.enabled == true`.
  final double immediateSurcharge;
  /// Per-km charge for distance above 5 km (`perKmAfter5 × (km - 5)`).
  final double kmAfter5;
  /// Sum of all components above.
  final double total;

  const DeliveryExpressPriceBreakdown({
    this.base = 0,
    this.addOnsTotal = 0,
    this.immediateSurcharge = 0,
    this.kmAfter5 = 0,
    this.total = 0,
  });

  Map<String, dynamic> toMap() => {
        'base': base,
        'addOnsTotal': addOnsTotal,
        'immediateSurcharge': immediateSurcharge,
        'kmAfter5': kmAfter5,
        'total': total,
      };

  factory DeliveryExpressPriceBreakdown.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const DeliveryExpressPriceBreakdown();
    double d(String k) => (raw[k] as num?)?.toDouble() ?? 0;
    return DeliveryExpressPriceBreakdown(
      base: d('base'),
      addOnsTotal: d('addOnsTotal'),
      immediateSurcharge: d('immediateSurcharge'),
      kmAfter5: d('kmAfter5'),
      total: d('total'),
    );
  }
}
