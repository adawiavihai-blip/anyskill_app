// Round-trip serialization tests for CSM profile models. Pins the
// fromMap/toMap contract so a Firestore schema regression fails the suite.
//
// Pattern: build a profile → toMap → fromMap → expect deep equality on
// the key fields. Defensive against a future field rename or default
// drift.

import 'package:flutter_test/flutter_test.dart';

import 'package:anyskill_app/models/babysitter_profile.dart';
import 'package:anyskill_app/models/motorcycle_tow_profile.dart';
import 'package:anyskill_app/models/cleaning_profile.dart';
import 'package:anyskill_app/models/delivery_profile.dart';
import 'package:anyskill_app/models/handyman_profile.dart';
import 'package:anyskill_app/models/pest_control_profile.dart';

void main() {
  group('Model serialization — round-trip', () {
    test('BabysitterProfile defaults serialize cleanly', () {
      final original = const BabysitterProfile();
      final map = original.toMap();
      final restored = BabysitterProfile.fromMap(map);

      // Pricing config is the most critical — it drives every booking total.
      expect(restored.pricing.rateOneChild, original.pricing.rateOneChild);
      expect(restored.pricing.rateTwoChildren, original.pricing.rateTwoChildren);
      expect(restored.pricing.rateThreePlusChildren,
          original.pricing.rateThreePlusChildren);
      expect(restored.pricing.nightSurchargePercent,
          original.pricing.nightSurchargePercent);
      expect(restored.pricing.holidaySurchargePercent,
          original.pricing.holidaySurchargePercent);
      expect(restored.pricing.lateFeeMaxAmount,
          original.pricing.lateFeeMaxAmount);
    });

    test('BabysitterProfile custom values round-trip', () {
      final original = const BabysitterProfile(
        pricing: BabysitterPricingConfig(
          rateOneChild: 75,
          rateTwoChildren: 100,
          nightSurchargePercent: 30,
          holidaySurchargePercent: 75,
        ),
        introNote: 'משמרת אכפתית עם 5 שנות ניסיון',
      );
      final restored = BabysitterProfile.fromMap(original.toMap());

      expect(restored.pricing.rateOneChild, 75);
      expect(restored.pricing.rateTwoChildren, 100);
      expect(restored.pricing.nightSurchargePercent, 30);
      expect(restored.pricing.holidaySurchargePercent, 75);
      expect(restored.introNote, 'משמרת אכפתית עם 5 שנות ניסיון');
    });

    test('MotorcycleTowProfile defaults serialize cleanly', () {
      final original = const MotorcycleTowProfile();
      final map = original.toMap();
      final restored = MotorcycleTowProfile.fromMap(map);

      expect(restored.pricing.basePrice, original.pricing.basePrice);
      expect(restored.pricing.pricePerKm, original.pricing.pricePerKm);
      expect(restored.pricing.includedKm, original.pricing.includedKm);
      expect(restored.pricing.nightSurchargePercent,
          original.pricing.nightSurchargePercent);
      expect(restored.pricing.emergencySurchargePercent,
          original.pricing.emergencySurchargePercent);
    });

    test('MotorcycleTowProfile custom pricing round-trip', () {
      final original = const MotorcycleTowProfile(
        pricing: MotorcycleTowPricing(
          basePrice: 250,
          pricePerKm: 6.5,
          includedKm: 15,
          nightSurchargePercent: 35,
          emergencySurchargePercent: 75,
        ),
      );
      final restored =
          MotorcycleTowProfile.fromMap(original.toMap());

      expect(restored.pricing.basePrice, 250);
      expect(restored.pricing.pricePerKm, 6.5);
      expect(restored.pricing.includedKm, 15);
      expect(restored.pricing.nightSurchargePercent, 35);
      expect(restored.pricing.emergencySurchargePercent, 75);
    });

    test('DeliveryProfile defaults serialize cleanly', () {
      final original = const DeliveryProfile();
      final map = original.toMap();
      final restored = DeliveryProfile.fromMap(map);

      expect(restored.pricing.documents, original.pricing.documents);
      expect(restored.pricing.smallPackage, original.pricing.smallPackage);
      expect(restored.pricing.mediumPackage, original.pricing.mediumPackage);
      expect(restored.pricing.largePackage, original.pricing.largePackage);
      expect(restored.pricing.flowers, original.pricing.flowers);
      expect(restored.pricing.cakes, original.pricing.cakes);
      expect(restored.pricing.perKmAfter5, original.pricing.perKmAfter5);
    });

    test('DeliveryProfile priceFor returns the right value per packageType', () {
      const profile = DeliveryProfile(
        pricing: DeliveryPricing(
          documents: 30,
          smallPackage: 50,
          mediumPackage: 70,
          largePackage: 100,
          flowers: 60,
          cakes: 80,
        ),
      );
      expect(profile.pricing.priceFor('documents'), 30);
      expect(profile.pricing.priceFor('small_package'), 50);
      expect(profile.pricing.priceFor('medium_package'), 70);
      expect(profile.pricing.priceFor('large_package'), 100);
      expect(profile.pricing.priceFor('flowers'), 60);
      expect(profile.pricing.priceFor('cakes'), 80);
      // Unknown type — should return a sensible default (not crash)
      expect(profile.pricing.priceFor('unknown_type'), isA<int>());
    });

    test('HandymanProfile defaults serialize cleanly', () {
      final original = HandymanProfile();
      final map = original.toMap();
      final restored = HandymanProfile.fromMap(map);

      expect(restored.pricing.emergencySurcharge,
          original.pricing.emergencySurcharge);
      expect(restored.punchListDiscount.twoJobs,
          original.punchListDiscount.twoJobs);
      // 2-jobs default = 10%
      expect(original.punchListDiscount.percentFor(2), 10);
      expect(original.punchListDiscount.percentFor(3), 20);
      expect(original.punchListDiscount.percentFor(4), 30);
      expect(original.punchListDiscount.percentFor(1), 0);
    });

    test('HandymanProfile custom price overrides round-trip', () {
      final original = HandymanProfile(
        pricing: const HandymanPricing(
          customPrices: {'leak_fix': 250, 'paint_room': 400},
          emergencySurcharge: 150,
        ),
        punchListDiscount: const HandymanPunchListDiscount(
          twoJobs: 15,
          threeJobs: 25,
          fourPlusJobs: 35,
        ),
      );
      final restored = HandymanProfile.fromMap(original.toMap());

      expect(restored.pricing.priceFor('leak_fix', 0), 250);
      expect(restored.pricing.priceFor('paint_room', 0), 400);
      expect(restored.pricing.emergencySurcharge, 150);
      expect(restored.punchListDiscount.twoJobs, 15);
      expect(restored.punchListDiscount.threeJobs, 25);
      expect(restored.punchListDiscount.fourPlusJobs, 35);
    });

    test('CleaningProfile defaults serialize cleanly', () {
      final original = const CleaningProfile();
      final map = original.toMap();
      final restored = CleaningProfile.fromMap(map);

      expect(restored.pricing.basePriceFor('regular_home', 80),
          original.pricing.basePriceFor('regular_home', 80));
    });

    test('PestControlProfile defaults serialize cleanly', () {
      final original = const PestControlProfile();
      final map = original.toMap();
      final restored = PestControlProfile.fromMap(map);

      // Sanity check — round-trip doesn't crash
      expect(restored.toMap(), isA<Map<String, dynamic>>());
    });

    test('isXCategory helpers — Hebrew + English aliases', () {
      // Babysitter
      expect(isBabysitterCategory('בייביסיטר'), true);
      expect(isBabysitterCategory('שמרטף'), true);
      expect(isBabysitterCategory('babysitter'), true);
      expect(isBabysitterCategory('nanny'), true);
      expect(isBabysitterCategory('הדברה'), false);
      expect(isBabysitterCategory(null), false);
      expect(isBabysitterCategory(''), false);

      // Motorcycle towing
      expect(isMotorcycleTowingCategory('גרר אופנועים'), true);
      expect(isMotorcycleTowingCategory('motorcycle towing'), true);
      expect(isMotorcycleTowingCategory('ניקיון'), false);

      // Pest control
      expect(isPestControlCategory('הדברה'), true);
      expect(isPestControlCategory('pest_control'), true);
      expect(isPestControlCategory('מדביר'), true);
      expect(isPestControlCategory('שיפוצים'), false);

      // Delivery
      expect(isDeliveryCategory('משלוחים'), true);
      expect(isDeliveryCategory('שליחים'), true);
      expect(isDeliveryCategory('delivery'), true);
      expect(isDeliveryCategory('courier'), true);
      expect(isDeliveryCategory('בייביסיטר'), false);

      // Cleaning
      expect(isCleaningCategory('נקיון'), true);
      expect(isCleaningCategory('ניקיון'), true);
      expect(isCleaningCategory('cleaning'), true);
      expect(isCleaningCategory('cleaner'), true);
      expect(isCleaningCategory('הנדימן'), false);

      // Handyman
      expect(isHandymanCategory('הנדימן'), true);
      expect(isHandymanCategory('handyman'), true);
      expect(isHandymanCategory('handy man'), true);
      expect(isHandymanCategory('בייביסיטר'), false);
    });
  });
}
