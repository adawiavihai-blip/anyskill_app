// Delivery Express constants — emergency courier dispatch flow.
//
// Mirrors the Flash Auction pattern (CLAUDE.md §57) but adapted to the
// Delivery CSM (§33). 60-second multi-tier dispatch with ETA-only offers
// from couriers within an expanding 5→10→15 km radius.
//
// Adding a new tunable: bump the value here, NOT inline in the screen
// code. The CF (functions/index.js — `dispatchDeliveryExpress`) reads the
// matching numeric values inline (see `_DELIVERY_EXPRESS_TIER_*` constants
// at the top of that block — keep them aligned).
import 'package:flutter/material.dart';

/// Tunables that drive both the UI countdown and the dispatch CF cadence.
class DeliveryExpressConfig {
  // ── Layered dispatch radii (km) ──────────────────────────────────────
  static const double initialRadiusKm = 5.0;
  static const double expandedRadiusKm = 10.0;
  static const double maximumRadiusKm = 15.0;

  // ── Timing (seconds since `delivery_express/{id}.createdAt`) ─────────
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
  static const int customerOffersDisplayTimeoutSec = 60;
  static const int maxOffersToDisplay = 10;

  // ── Pricing ──────────────────────────────────────────────────────────
  /// Delivery Express ALWAYS uses `timing: 'immediate'` so the provider's
  /// immediate surcharge fires automatically. Checked client AND server.
  static const bool alwaysImmediate = true;

  // ── Recommended-offer scoring (mirrors Flash Auction weights) ────────
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

/// Stable string ids for the package-type picker on Step 1.
/// Stored as `delivery_express/{id}.packageType`. These match the ids in
/// [kDeliveryTypes] (lib/constants/delivery_types_catalog.dart) so the
/// CSM's `DeliveryPricing.priceFor(packageType)` resolves the base price.
class DeliveryExpressPackageType {
  static const String documents = 'documents';
  static const String smallPackage = 'small_package';
  static const String mediumPackage = 'medium_package';
  static const String largePackage = 'large_package';
  static const String flowers = 'flowers';
  static const String cakes = 'cakes';

  static const Map<String, String> labels = {
    documents: 'מסמכים',
    smallPackage: 'חבילה קטנה',
    mediumPackage: 'חבילה בינונית',
    largePackage: 'חבילה גדולה',
    flowers: 'פרחים',
    cakes: 'עוגות',
  };

  static const Map<String, String> weightSpecs = {
    documents: 'עד 1 ק"ג',
    smallPackage: 'עד 5 ק"ג',
    mediumPackage: '5-15 ק"ג',
    largePackage: '15-30 ק"ג',
    flowers: 'עד 3 ק"ג',
    cakes: 'עד 5 ק"ג',
  };

  static const Map<String, IconData> icons = {
    documents: Icons.description_rounded,
    smallPackage: Icons.inventory_2_outlined,
    mediumPackage: Icons.markunread_mailbox_rounded,
    largePackage: Icons.card_giftcard_rounded,
    flowers: Icons.local_florist_rounded,
    cakes: Icons.cake_rounded,
  };

  static const List<String> all = [
    documents,
    smallPackage,
    mediumPackage,
    largePackage,
    flowers,
    cakes,
  ];

  static String labelOf(String? id) => labels[id] ?? labels[smallPackage]!;

  static String weightSpecOf(String? id) =>
      weightSpecs[id] ?? weightSpecs[smallPackage]!;

  static IconData iconOf(String? id) =>
      icons[id] ?? icons[smallPackage]!;

  /// Which vehicle types can carry this package? Used by the CF when
  /// filtering eligible couriers (scooter has max ~30kg).
  /// Returns vehicle id strings matching [kDeliveryVehicles] ids.
  static List<String> eligibleVehicles(String packageType) {
    switch (packageType) {
      case documents:
      case smallPackage:
      case flowers:
      case cakes:
        return const ['scooter', 'car'];
      case mediumPackage:
      case largePackage:
        return const ['car'];
    }
    return const ['scooter', 'car'];
  }
}

/// Why is this delivery urgent? Customer picks one on Step 1 — drives the
/// UI tone + the FCM body the provider sees.
class DeliveryExpressUrgencyReason {
  static const String urgentBusiness = 'urgent_business';
  static const String timeSensitiveDoc = 'time_sensitive_doc';
  static const String freshFood = 'fresh_food';
  static const String giftDelivery = 'gift_delivery';
  static const String replacementItem = 'replacement_item';
  static const String other = 'other';

  static const Map<String, String> labels = {
    urgentBusiness: 'משלוח עסקי דחוף',
    timeSensitiveDoc: 'מסמך רגיש לזמן',
    freshFood: 'אוכל / פרחים טריים',
    giftDelivery: 'מתנה / הפתעה',
    replacementItem: 'חלף לפריט שהלך לאיבוד',
    other: 'אחר',
  };

  static const Map<String, IconData> icons = {
    urgentBusiness: Icons.business_center_rounded,
    timeSensitiveDoc: Icons.assignment_rounded,
    freshFood: Icons.local_florist_rounded,
    giftDelivery: Icons.redeem_rounded,
    replacementItem: Icons.swap_horiz_rounded,
    other: Icons.help_outline_rounded,
  };

  static const List<String> all = [
    urgentBusiness,
    timeSensitiveDoc,
    freshFood,
    giftDelivery,
    replacementItem,
    other,
  ];

  static String labelOf(String? id) => labels[id] ?? labels[other]!;

  static IconData iconOf(String? id) => icons[id] ?? icons[other]!;
}

/// Parent doc status (`delivery_express/{id}.status`).
class DeliveryExpressStatus {
  /// Created, FCM dispatch in progress.
  static const String searching = 'searching';

  /// At least one offer has arrived.
  static const String hasOffers = 'has_offers';

  /// Customer picked an offer. The job is being created via Pay & Secure.
  static const String matched = 'matched';

  /// Customer cancelled before any offer was chosen.
  static const String cancelled = 'cancelled';

  /// 120 seconds elapsed without a match — the dispatch CF closes the doc.
  static const String expired = 'expired';
}

/// Sub-doc status (`delivery_express/{id}/offers/{offerId}.status`).
class DeliveryExpressOfferStatus {
  static const String pending = 'pending';
  static const String selected = 'selected';
  static const String rejected = 'rejected';
}

/// FCM notification copy. Centralized so the CF + the in-app
/// notifications row use identical strings.
class DeliveryExpressNotifications {
  static String providerTitle() => 'משלוח דחוף חדש';

  static String providerBody({
    required double distanceKm,
    required double estimatedEarnings,
    required String packageLabel,
  }) {
    return '$packageLabel · ${distanceKm.toStringAsFixed(1)} ק"מ ממך · '
        '₪${estimatedEarnings.toStringAsFixed(0)} הכנסה משוערת';
  }

  static String customerOfferReceived({
    required String providerName,
    required int etaMinutes,
  }) {
    return '$providerName יכול לאסוף בעוד $etaMinutes דקות';
  }
}
