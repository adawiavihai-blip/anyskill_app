// flashAuctionConfig.dart
// קבועים ותצורה לפיצ'ר Flash Auction

class FlashAuctionConfig {
  // Layered dispatch radii (in km)
  static const double initialRadiusKm = 5.0;
  static const double expandedRadiusKm = 10.0;
  static const double maximumRadiusKm = 15.0;

  // Timing (in seconds)
  static const int initialDispatchDelay = 0;
  static const int expandToTier2After = 30;
  static const int expandToTier3After = 60;
  static const int expireAfter = 120;

  // Provider notification limits
  static const int maxProvidersTier1 = 5;
  static const int maxProvidersTier2 = 10;
  static const int maxProvidersTier3 = 999; // unlimited within radius

  // Customer view
  static const int customerOffersDisplayTimeoutSec = 60;
  static const int maxOffersToDisplay = 10;

  // Emergency surcharge always applied in flash auction
  static const bool flashAuctionAlwaysEmergency = true;

  // Recommended offer scoring weights
  static const double etaWeight = 2.0;
  static const double priceWeight = 0.05;
  static const double ratingWeight = 20.0;
  static const double experienceWeight = 0.1;
  static const int maxJobsForExperienceScore = 200;
}

class IssueType {
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

  static const List<String> all = [
    engineFault, accident, flatTire,
    deadBattery, wheelsLocked, other,
  ];
}

class AuctionStatus {
  static const String searching = 'searching';
  static const String hasOffers = 'has_offers';
  static const String matched = 'matched';
  static const String cancelled = 'cancelled';
  static const String expired = 'expired';
}

class OfferStatus {
  static const String pending = 'pending';
  static const String selected = 'selected';
  static const String rejected = 'rejected';
}

// FCM Notification templates
class FlashAuctionNotifications {
  static String providerTitle() => 'קריאת גרר חדשה';

  static String providerBody({
    required double distanceKm,
    required double estimatedEarnings,
  }) {
    return '${distanceKm.toStringAsFixed(1)} ק"מ ממך · ₪${estimatedEarnings.toStringAsFixed(0)} הכנסה משוערת';
  }

  static String customerOfferReceived({
    required String providerName,
    required int etaMinutes,
  }) {
    return '$providerName יכול להגיע ב-$etaMinutes דקות';
  }
}
