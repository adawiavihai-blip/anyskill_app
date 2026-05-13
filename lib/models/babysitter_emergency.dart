// Babysitter Emergency model — emergency babysitter dispatch auction.
//
// Lives at `babysitter_emergencies/{emergencyId}` with offers in
// `babysitter_emergencies/{emergencyId}/offers/{offerId}` (subcollection).
//
// Sister-module to FlashAuction (CLAUDE.md §57). Same lifecycle:
//   1. Customer creates → status='searching'
//   2. Provider sends offer → first offer flips status→'has_offers'
//   3. Customer picks an offer → status='matched' + selectedOfferId
//   4. Pay & Secure runs → matchedJobId is populated → babysitter
//      booking starts via the existing job-lifecycle flow (CLAUDE.md §53).
//
// CF (`dispatchBabysitterEmergency`) writes notifiedProviderIds +
// currentRadiusKm + expiresAt. Client never writes those fields.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_map.dart';

/// Root emergency doc.
class BabysitterEmergency {
  /// Firestore doc id (= `emergencyId`). Empty string when not yet persisted.
  final String id;
  final String customerId;
  final String customerName;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// One of [BabysitterEmergencyStatus] strings.
  final String status;

  /// One of [BabysitterEmergencyReason] strings.
  final String reason;

  /// Free-text the customer added in the details step (optional).
  final String reasonDetails;

  // ── Children ─────────────────────────────────────────────────────────
  /// 1..maxChildrenInPicker. Drives the hourly rate via
  /// BabysitterPricingConfig.rateForChildren(...).
  final int numChildren;

  /// Age-group keys from [BabysitterEmergencyAgeGroup.all]. Optional —
  /// some parents don't bother to specify; provider sees an empty chip
  /// row in that case.
  final List<String> childrenAgeGroups;

  // ── Time ─────────────────────────────────────────────────────────────
  /// When the babysitter should arrive. Always within the next few hours
  /// (the customer screen prevents picking >12h ahead — that's a regular
  /// booking, not an emergency).
  final DateTime agreedStartTime;

  /// When the babysitter is expected to leave. Together with
  /// agreedStartTime drives the price math.
  final DateTime agreedEndTime;

  // ── Location (single — the home) ─────────────────────────────────────
  final BabysitterEmergencyLocation location;

  // ── Optional notes (allergies, medical, special needs) ───────────────
  final String specialNotes;

  /// True when the customer marked this booking as falling on an Israeli
  /// holiday — drives the holiday surcharge.
  final bool isHoliday;

  // ── Server-managed (CF only) ─────────────────────────────────────────
  final double currentRadiusKm;
  final List<String> notifiedProviderIds;
  final int offerCount;

  // ── Match flow ───────────────────────────────────────────────────────
  final String? selectedOfferId;
  final String? selectedProviderId;
  final String? matchedJobId;

  // ── Terminal state info ──────────────────────────────────────────────
  final String? cancellationReason;
  final String? expiredReason;
  final String? expiredReasonHebrew;

  const BabysitterEmergency({
    required this.id,
    required this.customerId,
    this.customerName = '',
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.reason,
    this.reasonDetails = '',
    required this.numChildren,
    this.childrenAgeGroups = const [],
    required this.agreedStartTime,
    required this.agreedEndTime,
    required this.location,
    this.specialNotes = '',
    this.isHoliday = false,
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

  bool get isLive =>
      status == 'searching' || status == 'has_offers';

  int get secondsRemaining =>
      expiresAt.difference(DateTime.now()).inSeconds;

  /// Estimated duration in hours (decimals truncated; a 2.75h shift
  /// returns 2.75 — used for the provider card "X שעות" pill).
  double get durationHours =>
      agreedEndTime.difference(agreedStartTime).inMinutes / 60.0;

  Map<String, dynamic> toMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': status,
        'reason': reason,
        'reasonDetails': reasonDetails,
        'numChildren': numChildren,
        'childrenAgeGroups': childrenAgeGroups,
        'agreedStartTime': Timestamp.fromDate(agreedStartTime),
        'agreedEndTime': Timestamp.fromDate(agreedEndTime),
        'location': location.toMap(),
        'specialNotes': specialNotes,
        'isHoliday': isHoliday,
        'currentRadiusKm': currentRadiusKm,
        'notifiedProviderIds': notifiedProviderIds,
        'offerCount': offerCount,
        if (selectedOfferId != null) 'selectedOfferId': selectedOfferId,
        if (selectedProviderId != null) 'selectedProviderId': selectedProviderId,
        if (matchedJobId != null) 'matchedJobId': matchedJobId,
        if (cancellationReason != null) 'cancellationReason': cancellationReason,
      };

  factory BabysitterEmergency.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return BabysitterEmergency.fromMap(raw, id: doc.id);
  }

  factory BabysitterEmergency.fromMap(
    Map<String, dynamic> raw, {
    String id = '',
  }) {
    return BabysitterEmergency(
      id: id,
      customerId: raw['customerId'] as String? ?? '',
      customerName: raw['customerName'] as String? ?? '',
      createdAt: _ts(raw['createdAt']) ?? DateTime.now(),
      expiresAt: _ts(raw['expiresAt']) ??
          DateTime.now().add(const Duration(minutes: 2)),
      status: raw['status'] as String? ?? 'searching',
      reason: raw['reason'] as String? ?? 'other',
      reasonDetails: raw['reasonDetails'] as String? ?? '',
      numChildren: (raw['numChildren'] as num?)?.toInt() ?? 1,
      childrenAgeGroups: (raw['childrenAgeGroups'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      agreedStartTime: _ts(raw['agreedStartTime']) ?? DateTime.now(),
      agreedEndTime: _ts(raw['agreedEndTime']) ??
          DateTime.now().add(const Duration(hours: 3)),
      location: BabysitterEmergencyLocation.fromMap(safeMap(raw['location'])),
      specialNotes: raw['specialNotes'] as String? ?? '',
      isHoliday: raw['isHoliday'] == true,
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

/// Single home address — apartment + access notes are CRITICAL for
/// childcare emergencies (parking, gate codes, which floor).
class BabysitterEmergencyLocation {
  final String formattedAddress;
  final String apartmentNumber;
  final String accessNotes;
  final double? lat;
  final double? lng;

  /// True when the customer dragged the pin to refine the geocoded
  /// address — used by the offers screen to label "מיקום מדויק".
  final bool pinAdjusted;

  const BabysitterEmergencyLocation({
    this.formattedAddress = '',
    this.apartmentNumber = '',
    this.accessNotes = '',
    this.lat,
    this.lng,
    this.pinAdjusted = false,
  });

  bool get hasCoords => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
        'formattedAddress': formattedAddress,
        'apartmentNumber': apartmentNumber,
        'accessNotes': accessNotes,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'pinAdjusted': pinAdjusted,
      };

  factory BabysitterEmergencyLocation.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const BabysitterEmergencyLocation();
    return BabysitterEmergencyLocation(
      formattedAddress: raw['formattedAddress'] as String? ?? '',
      apartmentNumber: raw['apartmentNumber'] as String? ?? '',
      accessNotes: raw['accessNotes'] as String? ?? '',
      lat: (raw['lat'] as num?)?.toDouble(),
      lng: (raw['lng'] as num?)?.toDouble(),
      pinAdjusted: raw['pinAdjusted'] == true,
    );
  }

  BabysitterEmergencyLocation copyWith({
    String? formattedAddress,
    String? apartmentNumber,
    String? accessNotes,
    double? lat,
    double? lng,
    bool? pinAdjusted,
  }) =>
      BabysitterEmergencyLocation(
        formattedAddress: formattedAddress ?? this.formattedAddress,
        apartmentNumber: apartmentNumber ?? this.apartmentNumber,
        accessNotes: accessNotes ?? this.accessNotes,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        pinAdjusted: pinAdjusted ?? this.pinAdjusted,
      );
}

// ═════════════════════════════════════════════════════════════════════════
// OFFER — sub-doc at babysitter_emergencies/{emergencyId}/offers/{offerId}
// ═════════════════════════════════════════════════════════════════════════

/// Offer from a single provider. Profile fields are SNAPSHOTS frozen at
/// offer-create time so the customer sees what was true when the offer
/// was sent.
class BabysitterEmergencyOffer {
  final String id;
  final String emergencyId;
  final String providerId;
  final String providerName;
  final String providerImageUrl;
  final double providerRating;
  final int providerReviewsCount;
  final int providerJobsCount;
  final bool providerIsVerified;

  /// CRITICAL TRUST SIGNAL — surfaced prominently on the offer card.
  /// Server enforces that only background-checked providers get the
  /// FCM in the first place, but we still snapshot the value here so
  /// the customer sees a green "✅ עברה ביקורת רקע" badge.
  final bool providerIsBackgroundChecked;

  /// True when the provider has at least one cert with
  /// `type == 'first_aid'` AND `verified == true` on the offer doc.
  final bool providerHasFirstAid;

  final bool providerIsVolunteer;
  final bool providerIsPro;

  /// Years of experience, snapshotted from
  /// `babysitterProfile.experience.yearsExperience`. Surfaces as a
  /// "X שנות נסיון" pill on the offer card.
  final int providerYearsExperience;

  /// THIS is the only field the provider directly enters in their
  /// offer-card form.
  final int etaMinutes;

  /// Computed total — server-side authoritative; client display only.
  final double totalPrice;

  /// Detailed breakdown so the customer (and the eventual job doc) sees
  /// where each shekel came from.
  final BabysitterEmergencyPriceBreakdown priceBreakdown;

  final DateTime createdAt;
  final String status;

  const BabysitterEmergencyOffer({
    required this.id,
    required this.emergencyId,
    required this.providerId,
    required this.providerName,
    this.providerImageUrl = '',
    this.providerRating = 0,
    this.providerReviewsCount = 0,
    this.providerJobsCount = 0,
    this.providerIsVerified = false,
    this.providerIsBackgroundChecked = false,
    this.providerHasFirstAid = false,
    this.providerIsVolunteer = false,
    this.providerIsPro = false,
    this.providerYearsExperience = 0,
    required this.etaMinutes,
    required this.totalPrice,
    required this.priceBreakdown,
    required this.createdAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() => {
        'emergencyId': emergencyId,
        'providerId': providerId,
        'providerName': providerName,
        'providerImageUrl': providerImageUrl,
        'providerRating': providerRating,
        'providerReviewsCount': providerReviewsCount,
        'providerJobsCount': providerJobsCount,
        'providerIsVerified': providerIsVerified,
        'providerIsBackgroundChecked': providerIsBackgroundChecked,
        'providerHasFirstAid': providerHasFirstAid,
        'providerIsVolunteer': providerIsVolunteer,
        'providerIsPro': providerIsPro,
        'providerYearsExperience': providerYearsExperience,
        'etaMinutes': etaMinutes,
        'totalPrice': totalPrice,
        'priceBreakdown': priceBreakdown.toMap(),
        'createdAt': Timestamp.fromDate(createdAt),
        'status': status,
      };

  factory BabysitterEmergencyOffer.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return BabysitterEmergencyOffer.fromMap(raw, id: doc.id);
  }

  factory BabysitterEmergencyOffer.fromMap(
    Map<String, dynamic> raw, {
    required String id,
  }) {
    return BabysitterEmergencyOffer(
      id: id,
      emergencyId: raw['emergencyId'] as String? ?? '',
      providerId: raw['providerId'] as String? ?? '',
      providerName: raw['providerName'] as String? ?? '',
      providerImageUrl: raw['providerImageUrl'] as String? ?? '',
      providerRating: (raw['providerRating'] as num?)?.toDouble() ?? 0,
      providerReviewsCount:
          (raw['providerReviewsCount'] as num?)?.toInt() ?? 0,
      providerJobsCount: (raw['providerJobsCount'] as num?)?.toInt() ?? 0,
      providerIsVerified: raw['providerIsVerified'] == true,
      providerIsBackgroundChecked:
          raw['providerIsBackgroundChecked'] == true,
      providerHasFirstAid: raw['providerHasFirstAid'] == true,
      providerIsVolunteer: raw['providerIsVolunteer'] == true,
      providerIsPro: raw['providerIsPro'] == true,
      providerYearsExperience:
          (raw['providerYearsExperience'] as num?)?.toInt() ?? 0,
      etaMinutes: (raw['etaMinutes'] as num?)?.toInt() ?? 0,
      totalPrice: (raw['totalPrice'] as num?)?.toDouble() ?? 0,
      priceBreakdown: BabysitterEmergencyPriceBreakdown.fromMap(
        safeMap(raw['priceBreakdown']),
      ),
      createdAt: (raw['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: raw['status'] as String? ?? 'pending',
    );
  }

  /// Recommended-offer score. Same shape as
  /// FlashAuctionOffer.recommendationScore so admins can tune the
  /// weights via [BabysitterEmergencyConfig] and both flows respond.
  double get recommendationScore {
    final etaScore = (60 - etaMinutes).clamp(-60, 60) * 2.0;
    final priceScore = (1000 - totalPrice).clamp(-1000, 1000) * 0.05;
    final ratingScore = providerRating * 20.0;
    final expScore = providerJobsCount.clamp(0, 200) * 0.1;

    // Two extra trust signals for childcare context — they nudge the
    // recommended badge toward background-checked + first-aid sitters
    // even when raw stats are similar.
    final trustBonus =
        (providerIsBackgroundChecked ? 25.0 : 0) +
            (providerHasFirstAid ? 15.0 : 0);

    return etaScore + priceScore + ratingScore + expScore + trustBonus;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// PRICE BREAKDOWN — frozen on each offer + the matched job's preferences
// ═════════════════════════════════════════════════════════════════════════
//
// Mirrors BabysitterBookingPriceBreakdown shape so the eventual job doc
// can carry both this estimate AND a final-bill version after the shift.

class BabysitterEmergencyPriceBreakdown {
  final double regularHours;
  final double regularAmount;
  final double nightHours;
  final double nightAmount;
  final double holidaySurcharge;
  final double lastMinuteSurcharge;
  final double total;

  const BabysitterEmergencyPriceBreakdown({
    this.regularHours = 0,
    this.regularAmount = 0,
    this.nightHours = 0,
    this.nightAmount = 0,
    this.holidaySurcharge = 0,
    this.lastMinuteSurcharge = 0,
    this.total = 0,
  });

  Map<String, dynamic> toMap() => {
        'regularHours': regularHours,
        'regularAmount': regularAmount,
        'nightHours': nightHours,
        'nightAmount': nightAmount,
        'holidaySurcharge': holidaySurcharge,
        'lastMinuteSurcharge': lastMinuteSurcharge,
        'total': total,
      };

  factory BabysitterEmergencyPriceBreakdown.fromMap(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return const BabysitterEmergencyPriceBreakdown();
    double d(String k) => (raw[k] as num?)?.toDouble() ?? 0;
    return BabysitterEmergencyPriceBreakdown(
      regularHours: d('regularHours'),
      regularAmount: d('regularAmount'),
      nightHours: d('nightHours'),
      nightAmount: d('nightAmount'),
      holidaySurcharge: d('holidaySurcharge'),
      lastMinuteSurcharge: d('lastMinuteSurcharge'),
      total: d('total'),
    );
  }
}
