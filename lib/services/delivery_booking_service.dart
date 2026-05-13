import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_profile.dart';

/// Delivery CSM — price calculation + last-booking preferences helper.
class DeliveryBookingService {
  DeliveryBookingService._();

  /// Compute final NIS total for a delivery booking.
  ///
  /// - [base] is resolved via [DeliveryPricing.priceFor]
  /// - [timing] == 'immediate' adds [DeliveryImmediateOption.surcharge]
  /// - distance above 5 km adds `perKmAfter5 * (distanceKm - 5)`
  /// - [addOnsTotal] is the sum of all selected add-ons
  static double calculateTotal({
    required DeliveryProfile profile,
    required String packageType,
    required double distanceKm,
    required String timing,
    double addOnsTotal = 0,
  }) {
    final base = profile.pricing.priceFor(packageType).toDouble();
    double immediateSurcharge = 0;
    if (timing == 'immediate' && profile.availability.immediate.enabled) {
      immediateSurcharge = profile.availability.immediate.surcharge.toDouble();
    }
    double kmAfter5 = 0;
    if (distanceKm > 5) {
      kmAfter5 = (distanceKm - 5) * profile.pricing.perKmAfter5;
    }
    final total = base + immediateSurcharge + kmAfter5 + addOnsTotal;
    // Round to 2 decimals (see CLAUDE.md Section 18 Rule 7 — fee-first rounding).
    return double.parse(total.toStringAsFixed(2));
  }

  /// Breakdown view — same maths as [calculateTotal] but returns the rows.
  static Map<String, double> buildPriceBreakdown({
    required DeliveryProfile profile,
    required String packageType,
    required double distanceKm,
    required String timing,
    double addOnsTotal = 0,
  }) {
    final base = profile.pricing.priceFor(packageType).toDouble();
    double immediateSurcharge = 0;
    if (timing == 'immediate' && profile.availability.immediate.enabled) {
      immediateSurcharge = profile.availability.immediate.surcharge.toDouble();
    }
    double kmAfter5 = 0;
    if (distanceKm > 5) {
      kmAfter5 = (distanceKm - 5) * profile.pricing.perKmAfter5;
    }
    final total = base + immediateSurcharge + kmAfter5 + addOnsTotal;
    return {
      'base': base,
      'addOnsTotal': addOnsTotal,
      'immediateSurcharge': immediateSurcharge,
      'kmAfter5': double.parse(kmAfter5.toStringAsFixed(2)),
      'total': double.parse(total.toStringAsFixed(2)),
    };
  }

  /// Fetch the last booking a customer made with a specific courier — used
  /// to populate the "Express Reorder" card at the top of the booking block.
  static Future<Map<String, dynamic>?> getLastBookingWith({
    required String customerId,
    required String expertId,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: customerId)
          .where('expertId', isEqualTo: expertId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data();
    } catch (_) {
      return null;
    }
  }
}
