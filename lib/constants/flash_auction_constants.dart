// Flash Auction constants — emergency motorcycle towing flow.
//
// Mirrors the spec's flashAuctionConfig.dart (see
// docs/ui-specs/Motorcycle/Motorcycle 2/) so UX numbers stay in sync.
// Anything customer- or provider-facing here is the source of truth for
// FCM strings, scheduling thresholds, and recommended-offer scoring.
//
// Adding a new tunable: bump the value here, NOT inline in the screen
// code. The CF (functions/index.js — `dispatchFlashAuction`) reads the
// matching numeric values inline (see `_FLASH_AUCTION_TIER_*` constants
// at the top of that block — keep them aligned).
import 'package:flutter/material.dart';

/// Tunables that drive both the UI countdown and the dispatch CF cadence.
class FlashAuctionConfig {
  // ── Layered dispatch radii (km) ──────────────────────────────────────
  static const double initialRadiusKm = 5.0;
  static const double expandedRadiusKm = 10.0;
  static const double maximumRadiusKm = 15.0;

  // ── Timing (seconds since `flash_auctions/{id}.createdAt`) ───────────
  static const int initialDispatchDelay = 0;
  static const int expandToTier2After = 30;
  static const int expandToTier3After = 60;
  static const int expireAfter = 120;

  // ── Provider notification limits per tier ────────────────────────────
  static const int maxProvidersTier1 = 5;
  static const int maxProvidersTier2 = 10;
  // Tier 3 is "everyone within radius" — capped only by Firestore-query
  // page size.
  static const int maxProvidersTier3 = 999;

  // ── Customer-side timer on the offers screen ─────────────────────────
  // After [customerOffersDisplayTimeoutSec] the on-screen countdown
  // disappears but the auction itself continues running until the
  // backend-side [expireAfter] threshold.
  static const int customerOffersDisplayTimeoutSec = 60;
  static const int maxOffersToDisplay = 10;

  // ── Pricing ──────────────────────────────────────────────────────────
  /// Flash auctions ALWAYS apply the provider's emergency surcharge.
  /// This is checked client-side AND server-side; do not toggle.
  static const bool flashAuctionAlwaysEmergency = true;

  // ── Recommended-offer scoring (per spec §scoring) ────────────────────
  /// score += (60 - eta) * etaWeight    → faster = better
  static const double etaWeight = 2.0;
  /// score += (1000 - price) * priceWeight  → cheaper = better
  static const double priceWeight = 0.05;
  /// score += rating * ratingWeight     → higher rating = better
  static const double ratingWeight = 20.0;
  /// score += min(jobs, cap) * experienceWeight → cap experience score
  static const double experienceWeight = 0.1;
  static const int maxJobsForExperienceScore = 200;
}

/// Stable string ids for the "what happened" picker on the issue screen.
/// Stored as `flash_auctions/{id}.issueType`. Different from
/// motorcycle_service_cases_catalog by design — Flash Auction has its own
/// 6 buckets; the provider's profile cases are a wider 9-item list.
class FlashAuctionIssueType {
  static const String engineFault = 'engine_fault';
  static const String accident = 'accident';
  static const String flatTire = 'flat_tire';
  static const String deadBattery = 'dead_battery';
  static const String wheelsLocked = 'wheels_locked';
  static const String other = 'other';

  static const Map<String, String> labels = {
    engineFault: 'תקלת מנוע',
    accident: 'תאונה',
    flatTire: 'פנצ\'ר',
    deadBattery: 'מצבר מת',
    wheelsLocked: 'גלגלים נעולים',
    other: 'אחר',
  };

  static const Map<String, IconData> icons = {
    engineFault: Icons.build_rounded,
    accident: Icons.error_rounded,
    flatTire: Icons.donut_large_rounded,
    deadBattery: Icons.battery_alert_rounded,
    wheelsLocked: Icons.lock_rounded,
    other: Icons.help_outline_rounded,
  };

  static const List<String> all = [
    engineFault,
    accident,
    flatTire,
    deadBattery,
    wheelsLocked,
    other,
  ];

  static String labelOf(String? id) =>
      labels[id] ?? labels[other]!;

  static IconData iconOf(String? id) =>
      icons[id] ?? icons[other]!;
}

/// Parent auction-doc status (`flash_auctions/{id}.status`).
class FlashAuctionStatus {
  /// Created, FCM dispatch in progress. Customer is on the searching screen.
  static const String searching = 'searching';

  /// At least one offer has arrived. Customer can move to the offers screen.
  /// (We keep `searching` as long as no offers; the moment the first offer
  /// lands we flip to `hasOffers`.)
  static const String hasOffers = 'has_offers';

  /// Customer picked an offer. The job is being created via Pay & Secure.
  /// `selectedOfferId` + `selectedProviderId` are populated. Once the job
  /// is created, `matchedJobId` is also populated.
  static const String matched = 'matched';

  /// Customer cancelled before any offer was chosen.
  static const String cancelled = 'cancelled';

  /// 120 seconds elapsed without a successful match — the dispatch CF
  /// closes the auction with this status. Customer may retry as a regular
  /// non-urgent broadcast.
  static const String expired = 'expired';
}

/// Sub-doc status (`flash_auctions/{id}/offers/{offerId}.status`).
class FlashAuctionOfferStatus {
  static const String pending = 'pending';
  static const String selected = 'selected';
  static const String rejected = 'rejected';
}

/// FCM notification copy. Centralized so the CF + the in-app
/// notifications row use identical strings.
class FlashAuctionNotifications {
  static String providerTitle() => 'קריאת גרר חדשה';

  static String providerBody({
    required double distanceKm,
    required double estimatedEarnings,
  }) {
    return '${distanceKm.toStringAsFixed(1)} ק"מ ממך · '
        '₪${estimatedEarnings.toStringAsFixed(0)} הכנסה משוערת';
  }

  static String customerOfferReceived({
    required String providerName,
    required int etaMinutes,
  }) {
    return '$providerName יכול להגיע ב-$etaMinutes דקות';
  }
}
