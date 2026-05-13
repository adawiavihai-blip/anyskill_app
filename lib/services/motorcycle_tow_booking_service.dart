// Motorcycle towing — booking math + Express Reorder lookup.
//
// Per the spec: pure mathematical pricing — NO AI. Future enhancements
// (photo damage detection, smart ETA) will plug into other services.
//
// Pricing formula (matches spec §functional + mockup price card):
//   extraKm        = max(0, distanceKm - includedKm)
//   kmFee          = extraKm × pricePerKm
//   subtotal       = basePrice + kmFee
//   nightSurcharge = (atNight) ? subtotal × nightSurchargePercent / 100 : 0
//   emergSurcharge = (immediate) ? (subtotal+nightSurcharge) × emergencyPct/100 : 0
//   total          = subtotal + nightSurcharge + emergSurcharge
//
// Saturday rule: when [scheduledAt] (or now) is a Saturday in IST, the
// night-surcharge is applied for the entire 24h — matches the provider hint
// "תופעל אוטומטית בשעות שתגדיר ובשבתות".
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/motorcycle_tow_profile.dart';

class MotorcycleTowBookingService {
  static final _db = FirebaseFirestore.instance;

  /// Returns true when [when] falls inside the provider's night window OR is
  /// a Saturday (Israeli weekend day). When [when] is null we use `now()`.
  static bool isNightOrSaturday({
    required MotorcycleTowPricing pricing,
    DateTime? when,
  }) {
    final t = when ?? DateTime.now();
    // weekday: 1=Mon..7=Sun. Saturday == 6.
    if (t.weekday == DateTime.saturday) return true;
    return pricing.isNightHour(t.hour);
  }

  /// Computes the full breakdown. Pure function — safe to call on every UI
  /// rebuild. Numbers are rounded to 2 decimals so the values shown EQUAL
  /// the values written to the job doc.
  static MotorcycleTowPriceBreakdown calculate({
    required MotorcycleTowPricing pricing,
    required double distanceKm,
    required String urgencyId,
    DateTime? when,
  }) {
    final extraKm = (distanceKm - pricing.includedKm).clamp(0, double.infinity);
    final kmFee = extraKm * pricing.pricePerKm;
    final base = pricing.basePrice;
    final subtotal = base + kmFee;

    final isNight = isNightOrSaturday(pricing: pricing, when: when);
    final nightSurcharge =
        isNight ? subtotal * (pricing.nightSurchargePercent / 100) : 0.0;

    final isEmergency = urgencyId == 'immediate';
    final emergSurcharge = isEmergency
        ? (subtotal + nightSurcharge) *
            (pricing.emergencySurchargePercent / 100)
        : 0.0;

    final total = subtotal + nightSurcharge + emergSurcharge;

    return MotorcycleTowPriceBreakdown(
      basePrice: _r(base),
      kmFee: _r(kmFee),
      nightSurcharge: _r(nightSurcharge),
      emergencySurcharge: _r(emergSurcharge),
      total: _r(total),
      extraKm: _r(extraKm.toDouble()),
    );
  }

  /// Round to 2 decimals.
  static double _r(double v) =>
      double.parse(v.toStringAsFixed(2));

  /// Express Reorder — most-recent completed motorcycle-tow job between
  /// (customer, provider). Returns the raw doc (with optional review fields
  /// merged in) or null if none. Mirrors the pattern in
  /// HandymanBookingService.getLastBookingWith.
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
        if (data['motorcycleTowPreferences'] is Map) return true;
        final st = (data['serviceType']?.toString() ?? '').toLowerCase();
        return st.contains('גרר') || st.contains('motorcycle');
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

  /// Haversine distance between two lat/lng points (km).
  /// Used by the booking block to estimate route distance from the pickup +
  /// dropoff coordinates when a routing API isn't available.
  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0; // earth radius in km
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;
}
