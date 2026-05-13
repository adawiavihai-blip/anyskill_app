// Cleaning booking service — price calculation + history reads.
// Sync rules (per spec):
//  - Express Reorder reads from the existing `jobs` collection (Section 4 escrow lifecycle)
//    + existing `reviews` collection. No duplicate data stores.
//  - Recurring-customer analytics also read from `jobs` collection.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cleaning_profile.dart';

/// Computes + persists nothing. Pure functions + Firestore reads.
class CleaningBookingService {
  static final _db = FirebaseFirestore.instance;

  /// Heuristic duration estimate in minutes (fallback when Gemini CF fails).
  static int estimateDurationMinutes({
    required String cleaningType,
    required int bedrooms,
    required int bathrooms,
    required int squareMeters,
    required bool hasPets,
    required int selectedTasksCount,
    required int addOnsCount,
  }) {
    // Base by square meters.
    double base = 60.0; // 1h min
    if (squareMeters <= 60) {
      base = 120;
    } else if (squareMeters <= 100) {
      base = 180;
    } else if (squareMeters <= 150) {
      base = 240;
    } else {
      base = 300;
    }

    // Type multipliers (matches pricing).
    const multipliers = {
      'regular_home': 1.0,
      'deep_renovation': 2.0,
      'airbnb': 0.8,
      'office': 1.5,
      'store': 1.3,
      'event': 1.6,
    };
    base *= (multipliers[cleaningType] ?? 1.0);

    // Small additions.
    base += (bedrooms * 10);
    base += (bathrooms * 15);
    base += (hasPets ? 20 : 0);
    base += (selectedTasksCount * 4);
    base += (addOnsCount * 15);

    return base.round().clamp(60, 600);
  }

  /// Final price calc matching the spec's summary math.
  static double calculateTotal({
    required CleaningProfile profile,
    required String cleaningType,
    required int squareMeters,
    required List<String> selectedAddOns,
    required bool ecoMode,
    required String schedulingType, // 'one_time' | 'recurring'
    required String recurrenceFrequency, // weekly/biweekly/monthly
  }) {
    final base = profile.pricing.basePriceFor(cleaningType, squareMeters);
    double addOnsTotal = 0;
    for (final id in selectedAddOns) {
      addOnsTotal += (profile.pricing.addOns[id] ?? 0).toDouble();
    }
    final ecoSurcharge = ecoMode && profile.ecoMode.enabled
        ? profile.ecoMode.surcharge.toDouble()
        : 0.0;
    final subtotal = base + addOnsTotal + ecoSurcharge;

    double recurringDiscount = 0;
    if (schedulingType == 'recurring') {
      final pct =
          profile.recurringDiscounts.discountFor(recurrenceFrequency).toDouble();
      recurringDiscount = subtotal * (pct / 100.0);
    }

    final total = subtotal - recurringDiscount;
    return double.parse(total.toStringAsFixed(2));
  }

  /// Breakdown map used in the sticky summary UI.
  static Map<String, double> buildPriceBreakdown({
    required CleaningProfile profile,
    required String cleaningType,
    required int squareMeters,
    required List<String> selectedAddOns,
    required bool ecoMode,
    required String schedulingType,
    required String recurrenceFrequency,
  }) {
    final base = profile.pricing.basePriceFor(cleaningType, squareMeters);
    double addOnsTotal = 0;
    for (final id in selectedAddOns) {
      addOnsTotal += (profile.pricing.addOns[id] ?? 0).toDouble();
    }
    final ecoSurcharge = ecoMode && profile.ecoMode.enabled
        ? profile.ecoMode.surcharge.toDouble()
        : 0.0;
    final subtotal = base + addOnsTotal + ecoSurcharge;
    double recurringDiscount = 0;
    if (schedulingType == 'recurring') {
      final pct = profile.recurringDiscounts
          .discountFor(recurrenceFrequency)
          .toDouble();
      recurringDiscount = subtotal * (pct / 100.0);
    }
    final total = subtotal - recurringDiscount;
    return {
      'base': double.parse(base.toStringAsFixed(2)),
      'addOnsTotal': double.parse(addOnsTotal.toStringAsFixed(2)),
      'ecoSurcharge': double.parse(ecoSurcharge.toStringAsFixed(2)),
      'subtotal': double.parse(subtotal.toStringAsFixed(2)),
      'recurringDiscount':
          double.parse((-recurringDiscount).toStringAsFixed(2)),
      'total': double.parse(total.toStringAsFixed(2)),
    };
  }

  /// Express Reorder lookup — reads the LAST completed cleaning job between
  /// this customer and this provider from the existing `jobs` collection.
  /// Also pulls the customer's review if one exists.
  static Future<Map<String, dynamic>?> getLastBookingWith({
    required String customerId,
    required String expertId,
  }) async {
    try {
      final query = await _db
          .collection('jobs')
          .where('customerId', isEqualTo: customerId)
          .where('expertId', isEqualTo: expertId)
          .where('status', isEqualTo: 'completed')
          .limit(10)
          .get();

      if (query.docs.isEmpty) return null;

      // Filter + sort on the client to avoid a composite index.
      final docs = query.docs.where((d) {
        final data = d.data();
        return (data['cleaningPreferences'] is Map) ||
            (data['serviceType']?.toString().toLowerCase().contains('נקי') ??
                false) ||
            (data['serviceType']?.toString().toLowerCase().contains('clean') ??
                false);
      }).toList();
      if (docs.isEmpty) return null;

      docs.sort((a, b) {
        final ta = a.data()['completedAt'];
        final tb = b.data()['completedAt'];
        if (ta is Timestamp && tb is Timestamp) {
          return tb.compareTo(ta);
        }
        return 0;
      });

      final top = docs.first;
      final data = Map<String, dynamic>.from(top.data());

      // Pull the matching customer review (reviewerId == customerId).
      try {
        final reviewQuery = await _db
            .collection('reviews')
            .where('jobId', isEqualTo: top.id)
            .where('reviewerId', isEqualTo: customerId)
            .limit(1)
            .get();
        if (reviewQuery.docs.isNotEmpty) {
          final r = reviewQuery.docs.first.data();
          data['reviewRating'] = r['overallRating'] ?? r['rating'];
          data['reviewText'] = r['publicComment'] ?? r['comment'] ?? '';
        }
      } catch (_) {}

      return data;
    } catch (_) {
      return null;
    }
  }

  /// Count distinct customers the provider currently has on an ACTIVE
  /// recurring schedule. Reads from the existing `jobs` collection.
  static Stream<int> streamRecurringCustomersCount(String providerId) {
    return _db
        .collection('jobs')
        .where('expertId', isEqualTo: providerId)
        .limit(500)
        .snapshots()
        .map((snap) {
      final ids = <String>{};
      for (final doc in snap.docs) {
        final prefs = doc.data()['cleaningPreferences'];
        if (prefs is! Map) continue;
        final rec = prefs['recurrence'];
        if (rec is! Map) continue;
        if (rec['enabled'] == true && rec['active'] != false) {
          final cid = doc.data()['customerId']?.toString();
          if (cid != null && cid.isNotEmpty) ids.add(cid);
        }
      }
      return ids.length;
    });
  }
}
