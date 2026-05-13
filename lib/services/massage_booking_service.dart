import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/massage_profile.dart';
import '../constants/massage_addons_catalog.dart';

class MassageBookingService {
  static final _db = FirebaseFirestore.instance;

  static double calculateTotal({
    required MassageProfile profile,
    required int durationMinutes,
    required String? location,
    required List<String> selectedAddOns,
  }) {
    final dur = profile.durations
        .where((d) => d.enabled && d.minutes == durationMinutes)
        .firstOrNull;
    double total = dur?.price.toDouble() ?? 0;

    for (final addonId in selectedAddOns) {
      final addon =
          profile.addOns.where((a) => a.id == addonId).firstOrNull;
      if (addon != null) {
        total += addon.customPrice;
      } else {
        final def = findAddon(addonId);
        if (def != null) total += def.recommendedPrice;
      }
    }

    if (location == 'home') {
      total += profile.serviceLocations.home.travelFee;
    }

    return total;
  }

  static int calculateTotalDuration(int baseDuration, List<String> addOns) {
    int extra = 0;
    if (addOns.contains('head_massage')) extra += 10;
    if (addOns.contains('post_nap')) extra += 20;
    return baseDuration + extra;
  }

  static double calculatePackagePrice({
    required MassageProfile profile,
    required DiscountPackage package,
  }) {
    final baseDur = profile.durations.where((d) => d.enabled).firstOrNull;
    final basePrice = (baseDur?.price ?? 150).toDouble();
    final fullPrice = basePrice * package.sessionsCount;
    return fullPrice * (1 - package.discountPercent / 100);
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
          .where('massagePreferences', isNull: false)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 4));

      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      final prefs = data['massagePreferences'] as Map<String, dynamic>?;
      return prefs;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> buildPriceBreakdown({
    required MassageProfile profile,
    required int durationMinutes,
    required String? location,
    required List<String> selectedAddOns,
  }) {
    final dur = profile.durations
        .where((d) => d.enabled && d.minutes == durationMinutes)
        .firstOrNull;
    final basePrice = dur?.price.toDouble() ?? 0;

    double addOnsTotal = 0;
    for (final addonId in selectedAddOns) {
      final addon =
          profile.addOns.where((a) => a.id == addonId).firstOrNull;
      if (addon != null) {
        addOnsTotal += addon.customPrice;
      } else {
        final def = findAddon(addonId);
        if (def != null) addOnsTotal += def.recommendedPrice;
      }
    }

    final travelFee = location == 'home'
        ? profile.serviceLocations.home.travelFee.toDouble()
        : 0.0;

    return {
      'basePrice': basePrice,
      'addOnsTotal': addOnsTotal,
      'travelFee': travelFee,
      'discount': 0.0,
      'total': basePrice + addOnsTotal + travelFee,
    };
  }

  static List<String> filterIncompatibleAddOns(
      String? massageType, List<String> addOnIds) {
    if (massageType == 'pregnancy') {
      return addOnIds
          .where((id) => !['cbd_oil', 'theragun', 'cupping'].contains(id))
          .toList();
    }
    return addOnIds;
  }
}
