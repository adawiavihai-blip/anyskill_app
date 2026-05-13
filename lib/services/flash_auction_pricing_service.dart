// Flash Auction pricing — pure-math wrapper around the existing CSM #8
// motorcycle towing booking math.
//
// The provider doesn't enter a price in Flash Auction (per spec §motorcycle
// "ייחודיות הפיצ'ר"). Instead, we compute it deterministically from their
// `users/{uid}.motorcycleTowProfile.pricing` config + the auction's
// distance + the call time. Emergency surcharge ALWAYS applies in Flash
// Auction (`urgencyId: 'immediate'`).
//
// Output shape matches the existing escrow flow so the price the customer
// pre-approves on the offer card is exactly what gets debited from their
// wallet via Pay & Secure.
import '../models/flash_auction.dart';
import '../models/motorcycle_tow_profile.dart';
import 'motorcycle_tow_booking_service.dart';

class FlashAuctionPricingService {
  /// Compute the breakdown the provider will see (and the customer will
  /// pre-approve) given the provider's pricing config + auction distance.
  ///
  /// [when] defaults to now — used to detect Saturday/night surcharge.
  static FlashAuctionPriceBreakdown priceForProvider({
    required MotorcycleTowProfile providerProfile,
    required double distanceKm,
    DateTime? when,
  }) {
    // Reuse the existing booking math. urgencyId='immediate' triggers the
    // 50% emergency surcharge documented in CSM #8.
    final breakdown = MotorcycleTowBookingService.calculate(
      pricing: providerProfile.pricing,
      distanceKm: distanceKm,
      urgencyId: 'immediate',
      when: when,
    );

    // The CSM model uses `extraKm` (km beyond the provider's includedKm).
    // For Flash Auction we surface this as `kmCharged` so the breakdown
    // is self-explanatory on the offer card.
    return FlashAuctionPriceBreakdown(
      basePrice: breakdown.basePrice,
      pricePerKm: providerProfile.pricing.pricePerKm,
      kmCharged: breakdown.extraKm,
      kmFee: breakdown.kmFee,
      nightSurcharge: breakdown.nightSurcharge,
      emergencySurcharge: breakdown.emergencySurcharge,
      total: breakdown.total,
    );
  }

  /// Earnings the provider takes home AFTER the platform commission.
  /// Used in the FCM body the dispatch CF generates ("₪Y הכנסה משוערת").
  /// `feePercentage` is `admin/admin/settings/settings.feePercentage`
  /// (default 0.10 = 10%, see CLAUDE.md §4.1).
  static double estimatedEarningsForProvider({
    required FlashAuctionPriceBreakdown breakdown,
    required double feePercentage,
  }) {
    final commission = breakdown.total * feePercentage;
    final net = breakdown.total - commission;
    return double.parse(net.toStringAsFixed(2));
  }
}
