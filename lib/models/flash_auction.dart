// Flash Auction model — emergency motorcycle towing auction.
//
// Lives at `flash_auctions/{auctionId}` with offers in
// `flash_auctions/{auctionId}/offers/{offerId}` (subcollection).
//
// Lifecycle (per spec §motorcycle / Motorcycle 2):
//   1. Customer creates auction → status='searching'
//   2. Provider sends offer → first offer flips status→'has_offers'
//   3. Customer picks an offer → status='matched' + selectedOfferId
//   4. Pay & Secure runs → matchedJobId is populated → motorcycle_tows
//      starts via the existing CSM #8 tracking flow
//
// CF (`dispatchFlashAuction`) writes notifiedProviderIds + currentRadiusKm
// + expiresAt. Client never writes those fields directly (rules block it).
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_map.dart';

/// Root auction doc.
class FlashAuction {
  /// Firestore doc id (= `auctionId`). Empty string when not yet persisted.
  final String id;
  final String customerId;
  final String customerName;
  final DateTime createdAt;
  final DateTime expiresAt;
  /// One of [FlashAuctionStatus] strings.
  final String status;
  /// One of [FlashAuctionIssueType] strings.
  final String issueType;
  /// Free-text provided by the customer in the issue step (optional).
  final String issueDetails;
  final FlashAuctionLocation pickup;
  final FlashAuctionLocation dropoff;
  /// Estimated route distance (km). Computed via Haversine on the location
  /// screen using the two pin coords; the provider's price calc reads this.
  final double distanceKm;
  /// Storage URLs the customer attached at booking time. Optional —
  /// cleared if the customer skipped photos.
  final List<String> photoUrls;

  /// Current dispatch radius. Bumped 5 → 10 → 15 by the CF over time.
  final double currentRadiusKm;
  /// Provider uids that have been notified by the dispatch CF. The CF
  /// appends to this array as each tier fires.
  final List<String> notifiedProviderIds;
  /// Number of offers received. Denormalized from the offers subcollection
  /// so the searching/offers screens render the count without an extra
  /// query.
  final int offerCount;

  /// Populated when the customer picks an offer.
  final String? selectedOfferId;
  final String? selectedProviderId;
  /// Populated once Pay & Secure has run and a real `jobs/{id}` doc exists.
  /// `MotorcycleTowTrackingScreen` keys off this.
  final String? matchedJobId;

  /// Cancellation reason — only present when `status == 'cancelled'`.
  final String? cancellationReason;

  /// Server-set reason for `status == 'expired'`. CF writes either a known
  /// code (`'missing_pickup_coords'` / `'no_providers_found'`) or omits it
  /// for the 120s timeout case. Read-only on the client.
  final String? expiredReason;

  /// Hebrew-localized expiry reason written by the CF — drives the
  /// "נסה שנית" screen subtitle. Read-only on the client.
  final String? expiredReasonHebrew;

  const FlashAuction({
    required this.id,
    required this.customerId,
    this.customerName = '',
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.issueType,
    this.issueDetails = '',
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

  /// Convenience for "auction is still live" — true while searching OR
  /// has_offers. False after matched/cancelled/expired.
  bool get isLive => status == 'searching' || status == 'has_offers';

  /// Seconds remaining until [expiresAt]. Negative when already expired.
  int get secondsRemaining {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff;
  }

  Map<String, dynamic> toMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': status,
        'issueType': issueType,
        'issueDetails': issueDetails,
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

  factory FlashAuction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return FlashAuction.fromMap(raw, id: doc.id);
  }

  factory FlashAuction.fromMap(Map<String, dynamic> raw, {String id = ''}) {
    return FlashAuction(
      id: id,
      customerId: raw['customerId'] as String? ?? '',
      customerName: raw['customerName'] as String? ?? '',
      createdAt: _ts(raw['createdAt']) ?? DateTime.now(),
      expiresAt: _ts(raw['expiresAt']) ??
          DateTime.now().add(const Duration(minutes: 2)),
      status: raw['status'] as String? ?? 'searching',
      issueType: raw['issueType'] as String? ?? 'other',
      issueDetails: raw['issueDetails'] as String? ?? '',
      pickup: FlashAuctionLocation.fromMap(safeMap(raw['pickupLocation'])),
      dropoff: FlashAuctionLocation.fromMap(safeMap(raw['dropoffLocation'])),
      distanceKm: (raw['distanceKm'] as num?)?.toDouble() ?? 0,
      photoUrls:
          (raw['photos'] as List?)?.whereType<String>().toList() ?? const [],
      currentRadiusKm: (raw['currentRadiusKm'] as num?)?.toDouble() ?? 5.0,
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

class FlashAuctionLocation {
  final String address;
  final double? lat;
  final double? lng;

  const FlashAuctionLocation({
    this.address = '',
    this.lat,
    this.lng,
  });

  bool get hasCoords => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
        'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  factory FlashAuctionLocation.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const FlashAuctionLocation();
    return FlashAuctionLocation(
      address: raw['address'] as String? ?? '',
      lat: (raw['lat'] as num?)?.toDouble(),
      lng: (raw['lng'] as num?)?.toDouble(),
    );
  }

  FlashAuctionLocation copyWith({
    String? address,
    double? lat,
    double? lng,
  }) =>
      FlashAuctionLocation(
        address: address ?? this.address,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );
}

// ═════════════════════════════════════════════════════════════════════════
// OFFER — sub-doc at flash_auctions/{auctionId}/offers/{offerId}
// ═════════════════════════════════════════════════════════════════════════

/// Auction offer from a single provider. Profile fields (name, rating,
/// jobsCount) are SNAPSHOTS — frozen at offer-create time so the customer
/// sees what was true when the offer was sent.
class FlashAuctionOffer {
  final String id;
  final String auctionId;
  final String providerId;
  final String providerName;
  /// Provider profile photo URL (Storage download URL or HTTPS). May be
  /// empty when the provider has no profile image.
  final String providerImageUrl;
  final double providerRating;
  final int providerReviewsCount;
  final int providerJobsCount;
  final bool providerIsVerified;
  /// True when the provider had an active "מתנדב פעיל" badge at offer
  /// time (≤30 days since their last completed volunteer task).
  final bool providerIsVolunteer;
  /// Whether the provider holds the AnySkill Pro badge.
  final bool providerIsPro;

  /// Provider commits to arriving in this many minutes. THIS is the only
  /// field the provider directly enters in their offer-card form.
  final int etaMinutes;

  /// Computed total — server-side authoritative; client display only.
  /// Calculated by [FlashAuctionPricingService.priceForProvider] using
  /// the provider's pricing config from `users/{uid}.motorcycleTowProfile`.
  final double totalPrice;
  /// Detailed breakdown so the customer (and the eventual job doc) sees
  /// where each shekel came from.
  final FlashAuctionPriceBreakdown priceBreakdown;

  final DateTime createdAt;
  /// One of [FlashAuctionOfferStatus] strings.
  final String status;

  const FlashAuctionOffer({
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
        'etaMinutes': etaMinutes,
        'totalPrice': totalPrice,
        'priceBreakdown': priceBreakdown.toMap(),
        'createdAt': Timestamp.fromDate(createdAt),
        'status': status,
      };

  factory FlashAuctionOffer.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return FlashAuctionOffer.fromMap(raw, id: doc.id);
  }

  factory FlashAuctionOffer.fromMap(
    Map<String, dynamic> raw, {
    required String id,
  }) {
    return FlashAuctionOffer(
      id: id,
      auctionId: raw['auctionId'] as String? ?? '',
      providerId: raw['providerId'] as String? ?? '',
      providerName: raw['providerName'] as String? ?? '',
      providerImageUrl: raw['providerImageUrl'] as String? ?? '',
      providerRating: (raw['providerRating'] as num?)?.toDouble() ?? 0,
      providerReviewsCount:
          (raw['providerReviewsCount'] as num?)?.toInt() ?? 0,
      providerJobsCount:
          (raw['providerJobsCount'] as num?)?.toInt() ?? 0,
      providerIsVerified: raw['providerIsVerified'] == true,
      providerIsVolunteer: raw['providerIsVolunteer'] == true,
      providerIsPro: raw['providerIsPro'] == true,
      etaMinutes: (raw['etaMinutes'] as num?)?.toInt() ?? 0,
      totalPrice: (raw['totalPrice'] as num?)?.toDouble() ?? 0,
      priceBreakdown: FlashAuctionPriceBreakdown.fromMap(
        safeMap(raw['priceBreakdown']),
      ),
      createdAt: (raw['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: raw['status'] as String? ?? 'pending',
    );
  }

  /// Recommended-offer score per spec §motorcycle / scoring section.
  /// Higher = better. Caller (offers screen) ranks by this and tags the
  /// top result with the green "המומלץ ביותר" badge.
  double get recommendationScore {
    // Lower ETA is better → up to 60 minutes contributes positively.
    final etaScore = (60 - etaMinutes).clamp(-60, 60) * 2.0;
    // Lower price is better → tied to a 1000 NIS reference.
    final priceScore = (1000 - totalPrice).clamp(-1000, 1000) * 0.05;
    final ratingScore = providerRating * 20.0;
    final expScore =
        (providerJobsCount.clamp(0, 200)) * 0.1;
    return etaScore + priceScore + ratingScore + expScore;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// PRICE BREAKDOWN — frozen on each offer + the matched job's preferences
// ═════════════════════════════════════════════════════════════════════════
//
// Direct booking (CLAUDE.md §57): after the customer picks an offer,
// `FlashAuctionService.bookFromOffer` runs a single atomic tx that creates
// the `jobs/{id}` doc + flips auction → matched + offer → selected. The
// price breakdown below travels onto `jobs/{id}.motorcycleTowPreferences
// .priceBreakdown` so the provider's tracking screen and audit log see
// exactly what the customer was charged.

class FlashAuctionPriceBreakdown {
  /// Provider's `pricing.basePrice` (typically ₪180).
  final double basePrice;
  /// Per-km price the provider configured (₪/km).
  final double pricePerKm;
  /// km charged after subtracting the provider's `includedKm` (default 10).
  final double kmCharged;
  /// pricePerKm × kmCharged.
  final double kmFee;
  /// Night-window surcharge amount (already in NIS, NOT a percent).
  /// Zero when the call is made in daylight hours and not on Saturday.
  final double nightSurcharge;
  /// Emergency surcharge — Flash Auction ALWAYS applies this.
  final double emergencySurcharge;
  /// Sum of all components above.
  final double total;

  const FlashAuctionPriceBreakdown({
    this.basePrice = 0,
    this.pricePerKm = 0,
    this.kmCharged = 0,
    this.kmFee = 0,
    this.nightSurcharge = 0,
    this.emergencySurcharge = 0,
    this.total = 0,
  });

  Map<String, dynamic> toMap() => {
        'basePrice': basePrice,
        'pricePerKm': pricePerKm,
        'kmCharged': kmCharged,
        'kmFee': kmFee,
        'nightSurcharge': nightSurcharge,
        'emergencySurcharge': emergencySurcharge,
        'total': total,
      };

  factory FlashAuctionPriceBreakdown.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const FlashAuctionPriceBreakdown();
    double d(String k) => (raw[k] as num?)?.toDouble() ?? 0;
    return FlashAuctionPriceBreakdown(
      basePrice: d('basePrice'),
      pricePerKm: d('pricePerKm'),
      kmCharged: d('kmCharged'),
      kmFee: d('kmFee'),
      nightSurcharge: d('nightSurcharge'),
      emergencySurcharge: d('emergencySurcharge'),
      total: d('total'),
    );
  }
}
