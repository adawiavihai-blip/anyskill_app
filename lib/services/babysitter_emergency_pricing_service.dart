// Babysitter Emergency pricing — pure-math wrapper around the existing
// CSM #7 babysitter booking math (CLAUDE.md §53).
//
// The provider doesn't enter a price in the emergency flow. Instead, we
// compute it deterministically from their `users/{uid}.babysitterProfile
// .pricing` config + the customer's # children + start/end times. The
// last-minute surcharge ALWAYS applies — that's the whole point of the
// emergency flow (per BabysitterEmergencyConfig.emergencyAlwaysLastMinute).
//
// Output shape matches BabysitterEmergencyPriceBreakdown so the price
// the customer pre-approves on the offer card is exactly what gets
// debited from their wallet via Pay & Secure inside `bookFromOffer`.
import '../models/babysitter_emergency.dart';
import '../models/babysitter_profile.dart';
import 'babysitter_booking_service.dart';

class BabysitterEmergencyPricingService {
  /// Compute the breakdown the provider will see (and the customer will
  /// pre-approve) given the provider's pricing config + the booking
  /// window + the # of children.
  ///
  /// [bookingCreatedAt] defaults to now — used by the booking math to
  /// detect last-minute surcharge eligibility. We pass `now - 1 minute`
  /// instead of `now` to GUARANTEE the surcharge fires regardless of
  /// the provider's `lastMinuteThresholdHours` config (an emergency
  /// IS by definition last-minute).
  static BabysitterEmergencyPriceBreakdown priceForProvider({
    required BabysitterPricingConfig pricing,
    required int numChildren,
    required DateTime agreedStart,
    required DateTime agreedEnd,
    required bool isHoliday,
    DateTime? now,
  }) {
    // Force the last-minute surcharge: pass a "createdAt" timestamp
    // that's later than agreedStart minus the provider's threshold.
    // We use agreedStart itself — guarantees `hoursAhead == 0` and
    // therefore the surcharge fires whenever the provider's config has
    // `lastMinuteSurchargePercent > 0`.
    final forcedCreatedAt = now ?? agreedStart;

    final estimate = BabysitterBookingService.estimate(
      pricing: pricing,
      numChildren: numChildren,
      agreedStart: agreedStart,
      agreedEnd: agreedEnd,
      isHoliday: isHoliday,
      bookingCreatedAt: forcedCreatedAt,
    );

    return BabysitterEmergencyPriceBreakdown(
      regularHours: estimate.regularHours,
      regularAmount: estimate.regularAmount,
      nightHours: estimate.nightHours,
      nightAmount: estimate.nightAmount,
      holidaySurcharge: estimate.holidaySurcharge,
      lastMinuteSurcharge: estimate.lastMinuteSurcharge,
      total: estimate.total,
    );
  }

  /// Earnings the provider takes home AFTER the platform commission.
  /// Used in the FCM body the dispatch CF generates ("₪Y הכנסה משוערת").
  /// `feePercentage` is `admin/admin/settings/settings.feePercentage`
  /// (default 0.10 = 10%, see CLAUDE.md §4.1).
  static double estimatedEarningsForProvider({
    required BabysitterEmergencyPriceBreakdown breakdown,
    required double feePercentage,
  }) {
    final commission = breakdown.total * feePercentage;
    final net = breakdown.total - commission;
    return double.parse(net.toStringAsFixed(2));
  }
}
