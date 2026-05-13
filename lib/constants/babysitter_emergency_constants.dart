// Babysitter Emergency Dispatch — emergency babysitter request flow.
//
// Sister-module to Flash Auction (CLAUDE.md §57) — same 60-second
// multi-provider auction pattern, adapted for childcare:
//   • Single home address (no pickup/dropoff)
//   • Children count + age groups + duration drive the price math
//   • Pricing math reuses BabysitterBookingService.estimate(...)
//     (CLAUDE.md §53) with `bookingCreatedAt: now` so the last-minute
//     surcharge ALWAYS applies — that's the whole point of the flow.
//
// CRITICAL safety rule (enforced by the CF): only providers with
// `babysitterProfile.trust.backgroundChecked == true` AND
// `babysitterProfile.availability.acceptsLastMinute == true` get the FCM.
//
// Adding a new tunable: bump the value here, NOT inline in the screen
// code. The CF (functions/index.js — `dispatchBabysitterEmergency`)
// reads the matching numeric values inline (see `_BSE_TIER_*` constants
// at the top of that block — keep them aligned).
import 'package:flutter/material.dart';

/// Tunables that drive the UI countdown and the dispatch CF cadence.
class BabysitterEmergencyConfig {
  // ── Layered dispatch radii (km) ──────────────────────────────────────
  static const double initialRadiusKm = 5.0;
  static const double expandedRadiusKm = 10.0;
  static const double maximumRadiusKm = 15.0;

  // ── Timing (seconds since babysitter_emergencies/{id}.createdAt) ─────
  static const int initialDispatchDelay = 0;
  static const int expandToTier2After = 30;
  static const int expandToTier3After = 60;
  static const int expireAfter = 120;

  // ── Provider notification limits per tier ────────────────────────────
  static const int maxProvidersTier1 = 5;
  static const int maxProvidersTier2 = 10;
  static const int maxProvidersTier3 = 999; // capped only by query page

  // ── Customer-side timer on the offers screen ─────────────────────────
  static const int customerOffersDisplayTimeoutSec = 60;
  static const int maxOffersToDisplay = 10;

  // ── Pricing ──────────────────────────────────────────────────────────
  /// Babysitter emergencies ALWAYS treat the booking as last-minute
  /// (so the provider's `lastMinuteSurchargePercent` applies). This is
  /// the whole point of the flow — checked client-side AND server-side.
  static const bool emergencyAlwaysLastMinute = true;

  // ── Recommended-offer scoring (mirror of FlashAuction) ───────────────
  static const double etaWeight = 2.0;
  static const double priceWeight = 0.05;
  static const double ratingWeight = 20.0;
  static const double experienceWeight = 0.1;
  static const int maxJobsForExperienceScore = 200;

  // ── Domain constraints ───────────────────────────────────────────────
  /// Max children count visible in the picker. 5+ collapses into a
  /// "3+" hourly bucket per BabysitterPricingConfig.rateForChildren.
  static const int maxChildrenInPicker = 5;

  /// Default duration when the customer first lands on the details
  /// screen. 3h is the median family booking length.
  static const int defaultDurationHours = 3;

  /// Min/max bookable durations in hours. Min mirrors
  /// BabysitterPricingConfig.minimumBookingHours; max prevents
  /// accidental "overnight" picks via the slider.
  static const int minDurationHours = 1;
  static const int maxDurationHours = 12;
}

/// Stable string ids for the "what's the situation?" picker on the
/// details screen. Stored as `babysitter_emergencies/{id}.reason`.
///
/// 6 buckets — same shape as FlashAuctionIssueType. Each maps to a
/// Hebrew label + icon for the grid render.
class BabysitterEmergencyReason {
  static const String urgentMeeting = 'urgent_meeting';
  static const String medicalEmergency = 'medical_emergency';
  static const String regularSitterCancelled = 'regular_sitter_cancelled';
  static const String lastMinuteEvent = 'last_minute_event';
  static const String nightOut = 'night_out';
  static const String other = 'other';

  static const Map<String, String> labels = {
    urgentMeeting: 'פגישה דחופה',
    medicalEmergency: 'אירוע רפואי',
    regularSitterCancelled: 'המטפלת הקבועה ביטלה',
    lastMinuteEvent: 'אירוע מהרגע להרגע',
    nightOut: 'ערב בחוץ',
    other: 'אחר',
  };

  static const Map<String, IconData> icons = {
    urgentMeeting: Icons.business_center_rounded,
    medicalEmergency: Icons.local_hospital_rounded,
    regularSitterCancelled: Icons.event_busy_rounded,
    lastMinuteEvent: Icons.celebration_rounded,
    nightOut: Icons.nightlife_rounded,
    other: Icons.help_outline_rounded,
  };

  static const List<String> all = [
    urgentMeeting,
    medicalEmergency,
    regularSitterCancelled,
    lastMinuteEvent,
    nightOut,
    other,
  ];

  static String labelOf(String? id) => labels[id] ?? labels[other]!;
  static IconData iconOf(String? id) => icons[id] ?? icons[other]!;
}

/// Age groups for the children picker. Mirrors the babysitter CSM's
/// existing `babysitter_age_groups.dart` keys so a provider's
/// `babysitterProfile.ageGroups` filter can match against this.
class BabysitterEmergencyAgeGroup {
  static const String infant = 'infant'; // 0-1
  static const String toddler = 'toddler'; // 1-3
  static const String preschool = 'preschool'; // 3-5
  static const String schoolAge = 'school_age'; // 5-12
  static const String teen = 'teen'; // 12+

  static const Map<String, String> labels = {
    infant: 'תינוק (0-1)',
    toddler: 'פעוט (1-3)',
    preschool: 'גן (3-5)',
    schoolAge: 'בית ספר (5-12)',
    teen: 'נער/ה (12+)',
  };

  static const Map<String, String> emojis = {
    infant: '👶',
    toddler: '🧒',
    preschool: '🧑‍🎨',
    schoolAge: '🎒',
    teen: '🧑',
  };

  static const List<String> all = [
    infant,
    toddler,
    preschool,
    schoolAge,
    teen,
  ];

  static String labelOf(String? id) => labels[id] ?? '';
  static String emojiOf(String? id) => emojis[id] ?? '👤';
}

/// Parent emergency-doc status. Same lifecycle as FlashAuctionStatus.
class BabysitterEmergencyStatus {
  static const String searching = 'searching';
  static const String hasOffers = 'has_offers';
  static const String matched = 'matched';
  static const String cancelled = 'cancelled';
  static const String expired = 'expired';
}

/// Sub-doc status. Same lifecycle as FlashAuctionOfferStatus.
class BabysitterEmergencyOfferStatus {
  static const String pending = 'pending';
  static const String selected = 'selected';
  static const String rejected = 'rejected';
}

/// FCM copy. Centralized so the CF + the in-app notifications row use
/// identical strings.
class BabysitterEmergencyNotifications {
  static String providerTitle() => 'בקשת בייביסיטר דחופה';

  static String providerBody({
    required int numChildren,
    required double distanceKm,
    required double estimatedEarnings,
  }) {
    final kidsLabel = numChildren == 1 ? 'ילד אחד' : '$numChildren ילדים';
    return '$kidsLabel · ${distanceKm.toStringAsFixed(1)} ק"מ ממך · '
        '₪${estimatedEarnings.toStringAsFixed(0)} הכנסה משוערת';
  }

  static String customerOfferReceived({
    required String providerName,
    required int etaMinutes,
  }) {
    return '$providerName יכולה להגיע ב-$etaMinutes דקות';
  }
}
