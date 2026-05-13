// Handyman booking service — price calculation + Express Reorder lookup.
// Sync rules (per spec 01_MAIN_PROMPT_HANDYMAN.md §4):
//  - Express Reorder reads from the existing `jobs` + `reviews` collections.
//  - NO duplicate booking history store.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/handyman_profile.dart';

class HandymanBookingService {
  static final _db = FirebaseFirestore.instance;

  /// Sum of the effective prices for each selected service (respects
  /// provider custom overrides in pricing.customPrices).
  static double servicesTotal({
    required HandymanProfile profile,
    required List<HandymanPunchListItem> punchList,
  }) {
    double sum = 0;
    for (final p in punchList) {
      sum += profile.pricing.priceFor(p.serviceId, p.price);
    }
    return double.parse(sum.toStringAsFixed(2));
  }

  /// Graduated punch-list discount as an absolute NIS amount off the
  /// services subtotal. Matches spec percentages (2→10%, 3→20%, 4+→30%).
  static double punchListDiscountAmount({
    required HandymanProfile profile,
    required List<HandymanPunchListItem> punchList,
  }) {
    final subtotal = servicesTotal(profile: profile, punchList: punchList);
    final pct = profile.punchListDiscount.percentFor(punchList.length);
    final disc = subtotal * (pct / 100.0);
    return double.parse(disc.toStringAsFixed(2));
  }

  /// Final total = services − discount + materials + emergency surcharge.
  static double calculateTotal({
    required HandymanProfile profile,
    required List<HandymanPunchListItem> punchList,
    required String materialsOption,
    required double materialsEstimate,
    required String urgency,
  }) {
    final services = servicesTotal(profile: profile, punchList: punchList);
    final discount = punchListDiscountAmount(profile: profile, punchList: punchList);
    final materials =
        materialsOption == 'client_brings' ? 0.0 : materialsEstimate;
    final emergencySurcharge = urgency == 'emergency'
        ? profile.pricing.emergencySurcharge
        : 0.0;
    final total = services - discount + materials + emergencySurcharge;
    return double.parse(total.toStringAsFixed(2));
  }

  /// Breakdown for the sticky summary UI.
  static Map<String, double> buildPriceBreakdown({
    required HandymanProfile profile,
    required List<HandymanPunchListItem> punchList,
    required String materialsOption,
    required double materialsEstimate,
    required String urgency,
  }) {
    final services = servicesTotal(profile: profile, punchList: punchList);
    final discount = punchListDiscountAmount(profile: profile, punchList: punchList);
    final materials =
        materialsOption == 'client_brings' ? 0.0 : materialsEstimate;
    final emergencySurcharge = urgency == 'emergency'
        ? profile.pricing.emergencySurcharge
        : 0.0;
    final total = services - discount + materials + emergencySurcharge;
    return {
      'servicesTotal': double.parse(services.toStringAsFixed(2)),
      'materialsEstimate': double.parse(materials.toStringAsFixed(2)),
      'punchListDiscount':
          double.parse((-discount).toStringAsFixed(2)),
      'emergencySurcharge':
          double.parse(emergencySurcharge.toStringAsFixed(2)),
      'total': double.parse(total.toStringAsFixed(2)),
    };
  }

  /// Estimated total duration (minutes) across the punch list, plus the
  /// provider's service-area buffer (travel + setup).
  static int estimatedDurationMinutes({
    required HandymanProfile profile,
    required List<HandymanPunchListItem> punchList,
  }) {
    int sum = 0;
    for (final p in punchList) {
      sum += p.estimatedMinutes;
    }
    sum += profile.serviceArea.bufferMinutes;
    return sum;
  }

  /// Express Reorder — pulls the most-recent completed handyman job
  /// between (customer, provider) from the existing `jobs` collection.
  /// Returns the raw doc data (with optional `reviewRating` + `reviewText`
  /// merged in) or null if none.
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

      final docs = query.docs.where((d) {
        final data = d.data();
        if (data['handymanPreferences'] is Map) return true;
        final st = (data['serviceType']?.toString() ?? '').toLowerCase();
        return st.contains('הנדי') || st.contains('handyman');
      }).toList();
      if (docs.isEmpty) return null;

      docs.sort((a, b) {
        final ta = a.data()['completedAt'];
        final tb = b.data()['completedAt'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      });

      final top = docs.first;
      final data = Map<String, dynamic>.from(top.data());

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
}
