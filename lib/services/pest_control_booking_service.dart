import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/pest_control_profile.dart';

class PestControlBookingService {
  static final _db = FirebaseFirestore.instance;

  static double calculateTotal({
    required PestControlProfile profile,
    required String locationKey,
    required String urgency,
    required List<Map<String, dynamic>> addOns,
  }) {
    double base = (profile.basePricing[locationKey] ?? 290).toDouble();

    double addOnsTotal = 0;
    for (final addon in addOns) {
      addOnsTotal += (addon['price'] as num? ?? 0).toDouble();
    }

    double emergencyFee = 0;
    if (urgency == 'emergency' && profile.availability.emergencyService.enabled) {
      emergencyFee = profile.availability.emergencyService.additionalFee.toDouble();
    }

    return base + addOnsTotal + emergencyFee;
  }

  static Map<String, dynamic> buildPriceBreakdown({
    required PestControlProfile profile,
    required String locationKey,
    required String urgency,
    required List<Map<String, dynamic>> addOns,
  }) {
    final base = (profile.basePricing[locationKey] ?? 290).toDouble();
    double addOnsTotal = 0;
    for (final addon in addOns) {
      addOnsTotal += (addon['price'] as num? ?? 0).toDouble();
    }
    final emergencyFee = (urgency == 'emergency' &&
            profile.availability.emergencyService.enabled)
        ? profile.availability.emergencyService.additionalFee.toDouble()
        : 0.0;

    return {
      'basePrice': base,
      'addOnsTotal': addOnsTotal,
      'emergencyFee': emergencyFee,
      'travelFee': 0.0,
      'discount': 0.0,
      'total': base + addOnsTotal + emergencyFee,
    };
  }

  static Future<Map<String, dynamic>?> getLastBookingPreferences(
      String providerId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await _db
          .collection('jobs')
          .where('customerId', isEqualTo: uid)
          .where('expertId', isEqualTo: providerId)
          .where('pestControlPreferences', isNull: false)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 4));
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data()['pestControlPreferences']
          as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
