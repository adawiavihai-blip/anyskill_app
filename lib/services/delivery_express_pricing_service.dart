// Delivery Express pricing — pure-math wrapper around the existing
// Delivery CSM (§33) booking math.
//
// The courier doesn't enter a price in Delivery Express. Instead, we
// compute it deterministically from their `users/{uid}.deliveryProfile`
// config + the auction's distance + the chosen package type. Always uses
// `timing: 'immediate'` so the courier's immediate-surcharge fires.
//
// Output shape matches the existing escrow flow so the price the
// customer pre-approves on the offer card is exactly what gets debited
// from their wallet via Pay & Secure.
import '../models/delivery_express.dart';
import '../models/delivery_profile.dart';
import 'delivery_booking_service.dart';

class DeliveryExpressPricingService {
  /// Compute the breakdown the courier will see (and the customer will
  /// pre-approve) given the courier's profile + auction distance.
  static DeliveryExpressPriceBreakdown priceForProvider({
    required DeliveryProfile providerProfile,
    required String packageType,
    required double distanceKm,
  }) {
    final breakdown = DeliveryBookingService.buildPriceBreakdown(
      profile: providerProfile,
      packageType: packageType,
      distanceKm: distanceKm,
      timing: 'immediate',
      addOnsTotal: 0,
    );

    return DeliveryExpressPriceBreakdown(
      base: breakdown['base'] ?? 0,
      addOnsTotal: breakdown['addOnsTotal'] ?? 0,
      immediateSurcharge: breakdown['immediateSurcharge'] ?? 0,
      kmAfter5: breakdown['kmAfter5'] ?? 0,
      total: breakdown['total'] ?? 0,
    );
  }

  /// Earnings the courier takes home AFTER platform commission.
  /// Used in the FCM body the dispatch CF generates ("₪Y הכנסה משוערת").
  /// `feePercentage` is `admin/admin/settings/settings.feePercentage`
  /// (default 0.10 = 10%, see CLAUDE.md §4.1).
  static double estimatedEarningsForProvider({
    required DeliveryExpressPriceBreakdown breakdown,
    required double feePercentage,
  }) {
    final commission = breakdown.total * feePercentage;
    final net = breakdown.total - commission;
    return double.parse(net.toStringAsFixed(2));
  }
}
