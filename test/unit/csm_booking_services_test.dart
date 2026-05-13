// Unit tests for the pure-math sides of all 4 CSM booking services.
// These services are 100% pure functions — they take a profile + booking
// inputs and return a price breakdown. The tests pin the contract so a
// future regression that breaks the math fails the suite immediately.
//
// Run: flutter test test/unit/csm_booking_services_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:anyskill_app/models/babysitter_profile.dart';
import 'package:anyskill_app/models/motorcycle_tow_profile.dart';
import 'package:anyskill_app/models/delivery_profile.dart';
import 'package:anyskill_app/models/handyman_profile.dart';

import 'package:anyskill_app/services/babysitter_booking_service.dart';
import 'package:anyskill_app/services/motorcycle_tow_booking_service.dart';
import 'package:anyskill_app/services/cleaning_booking_service.dart';
import 'package:anyskill_app/services/delivery_booking_service.dart';
import 'package:anyskill_app/services/handyman_booking_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // BabysitterBookingService
  // ═══════════════════════════════════════════════════════════════════════
  group('BabysitterBookingService — estimate/finalBill', () {
    final pricing = const BabysitterPricingConfig();
    // Defaults: 60/80/100 NIS per hour for 1/2/3+ children
    //           night surcharge 20%, holiday 50%
    //           night = [22, 6) hours
    //           late fee ₪40 per 15-min interval, capped at ₪500

    test('1 child, 4-hour daytime booking = 4 * 60 = 240 NIS', () {
      final start = DateTime(2026, 5, 10, 14, 0);
      final end = DateTime(2026, 5, 10, 18, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 1,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: false,
      );
      expect(breakdown.regularHours, 4.0);
      expect(breakdown.nightHours, 0.0);
      expect(breakdown.regularAmount, 240.0);
      expect(breakdown.nightAmount, 0.0);
      expect(breakdown.holidaySurcharge, 0.0);
      expect(breakdown.lastMinuteSurcharge, 0.0);
      expect(breakdown.total, 240.0);
    });

    test('2 children, 5-hour daytime = 5 * 80 = 400 NIS', () {
      final start = DateTime(2026, 5, 10, 9, 0);
      final end = DateTime(2026, 5, 10, 14, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 2,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: false,
      );
      expect(breakdown.total, 400.0);
    });

    test('3 children → ₪100/hr (rateThreePlusChildren)', () {
      final start = DateTime(2026, 5, 10, 9, 0);
      final end = DateTime(2026, 5, 10, 12, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 3,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: false,
      );
      expect(breakdown.total, 300.0);
    });

    test('night hours (23:00-01:00) → night surcharge applied', () {
      // 2 hours fully at night, 1 child @ ₪60 base * 1.20 = ₪72/hr night
      final start = DateTime(2026, 5, 10, 23, 0);
      final end = DateTime(2026, 5, 11, 1, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 1,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: false,
      );
      expect(breakdown.regularHours, 0.0);
      expect(breakdown.nightHours, 2.0);
      expect(breakdown.nightAmount, 144.0); // 2 * 60 * 1.20
      expect(breakdown.total, 144.0);
    });

    test('mixed evening (20:00-23:00) → splits regular + night', () {
      // 20:00-22:00 = 2h regular, 22:00-23:00 = 1h night
      // 1 child @ ₪60: regular 2*60=120, night 1*60*1.20=72 → total 192
      final start = DateTime(2026, 5, 10, 20, 0);
      final end = DateTime(2026, 5, 10, 23, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 1,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: false,
      );
      expect(breakdown.regularHours, 2.0);
      expect(breakdown.nightHours, 1.0);
      expect(breakdown.regularAmount, 120.0);
      expect(breakdown.nightAmount, 72.0);
      expect(breakdown.total, 192.0);
    });

    test('holiday adds 50% surcharge on top of (regular + night)', () {
      final start = DateTime(2026, 5, 10, 14, 0);
      final end = DateTime(2026, 5, 10, 18, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 1,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: true,
      );
      // 4h * 60 = 240, holiday surcharge 240 * 0.50 = 120, total 360
      expect(breakdown.regularAmount, 240.0);
      expect(breakdown.holidaySurcharge, 120.0);
      expect(breakdown.total, 360.0);
    });

    test('last-minute surcharge (booking made <1h before)', () {
      final bookingTime = DateTime(2026, 5, 10, 13, 30);
      final start = DateTime(2026, 5, 10, 14, 0); // 30 min ahead
      final end = DateTime(2026, 5, 10, 16, 0);
      final breakdown = BabysitterBookingService.estimate(
        pricing: pricing,
        numChildren: 1,
        agreedStart: start,
        agreedEnd: end,
        isHoliday: false,
        bookingCreatedAt: bookingTime,
      );
      // 2h * 60 = 120, last-minute 30% on (regular + night) = 36
      expect(breakdown.regularAmount, 120.0);
      expect(breakdown.lastMinuteSurcharge, 36.0);
      expect(breakdown.total, 156.0);
    });

    test('finalBill: 30 min late → 2 intervals * ₪40 = ₪80 late fee', () {
      final agreedStart = DateTime(2026, 5, 10, 14, 0);
      final agreedEnd = DateTime(2026, 5, 10, 18, 0);
      final actualStart = agreedStart;
      final actualEnd = DateTime(2026, 5, 10, 18, 30); // 30 min late

      final breakdown = BabysitterBookingService.finalBill(
        pricing: pricing,
        numChildren: 1,
        agreedStart: agreedStart,
        agreedEnd: agreedEnd,
        actualStart: actualStart,
        actualEnd: actualEnd,
        isHoliday: false,
      );
      // splitByTimeOfDay uses actualStart/actualEnd, so 4h:30m all daytime
      // = 4.5h * 60 = ₪270 + late fee on the 30 min past 18:00 → 2*40=₪80
      // Total = ₪350
      expect(breakdown.lateFee, 80.0);
      expect(breakdown.total, 350.0);
    });

    test('finalBill: extreme lateness → late fee capped at ₪500', () {
      final agreedEnd = DateTime(2026, 5, 10, 18, 0);
      final actualEnd = DateTime(2026, 5, 10, 23, 0); // 5h late = many intervals
      final breakdown = BabysitterBookingService.finalBill(
        pricing: pricing,
        numChildren: 1,
        agreedStart: DateTime(2026, 5, 10, 14, 0),
        agreedEnd: agreedEnd,
        actualStart: DateTime(2026, 5, 10, 14, 0),
        actualEnd: actualEnd,
        isHoliday: false,
      );
      expect(breakdown.lateFee, 500.0); // capped, not 5*4*40 = 800
    });

    test('finalBill: on-time → no late fee', () {
      final start = DateTime(2026, 5, 10, 14, 0);
      final end = DateTime(2026, 5, 10, 18, 0);
      final breakdown = BabysitterBookingService.finalBill(
        pricing: pricing,
        numChildren: 1,
        agreedStart: start,
        agreedEnd: end,
        actualStart: start,
        actualEnd: end,
        isHoliday: false,
      );
      expect(breakdown.lateFee, 0.0);
      expect(breakdown.total, 240.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MotorcycleTowBookingService
  // ═══════════════════════════════════════════════════════════════════════
  group('MotorcycleTowBookingService — calculate', () {
    final pricing = const MotorcycleTowPricing();
    // Defaults: base ₪180 (incl. 10km), ₪4.5/extra-km, +25% night, +50% emergency

    test('5km tow, daytime, regular → just base ₪180', () {
      final result = MotorcycleTowBookingService.calculate(
        pricing: pricing,
        distanceKm: 5,
        urgencyId: 'today',
        when: DateTime(2026, 5, 10, 14, 0),
      );
      expect(result.basePrice, 180.0);
      expect(result.kmFee, 0.0); // 5 < 10 included
      expect(result.extraKm, 0.0);
      expect(result.nightSurcharge, 0.0);
      expect(result.emergencySurcharge, 0.0);
      expect(result.total, 180.0);
    });

    test('15km tow → 5 extra km * ₪4.5 = ₪22.5 km fee', () {
      final result = MotorcycleTowBookingService.calculate(
        pricing: pricing,
        distanceKm: 15,
        urgencyId: 'today',
        when: DateTime(2026, 5, 10, 14, 0),
      );
      expect(result.kmFee, 22.5);
      expect(result.extraKm, 5.0);
      expect(result.total, 202.5); // 180 + 22.5
    });

    test('night tow (23:00) → 25% surcharge on subtotal', () {
      final result = MotorcycleTowBookingService.calculate(
        pricing: pricing,
        distanceKm: 5,
        urgencyId: 'today',
        when: DateTime(2026, 5, 10, 23, 0),
      );
      expect(result.nightSurcharge, 45.0); // 180 * 0.25
      expect(result.total, 225.0);
    });

    test('emergency tow (urgencyId="immediate") → +50% on (subtotal + night)', () {
      final result = MotorcycleTowBookingService.calculate(
        pricing: pricing,
        distanceKm: 5,
        urgencyId: 'immediate',
        when: DateTime(2026, 5, 10, 14, 0),
      );
      expect(result.emergencySurcharge, 90.0); // 180 * 0.50
      expect(result.total, 270.0);
    });

    test('night + emergency stack → 25% then 50% on (subtotal+night)', () {
      final result = MotorcycleTowBookingService.calculate(
        pricing: pricing,
        distanceKm: 5,
        urgencyId: 'immediate',
        when: DateTime(2026, 5, 10, 23, 0),
      );
      // base 180, night 45 (25%), subtotal+night = 225
      // emergency 50% of 225 = 112.5
      // total = 180 + 45 + 112.5 = 337.5
      expect(result.nightSurcharge, 45.0);
      expect(result.emergencySurcharge, 112.5);
      expect(result.total, 337.5);
    });

    test('Saturday is treated as night (isNightOrSaturday)', () {
      // 2026-05-09 is a Saturday
      final result = MotorcycleTowBookingService.calculate(
        pricing: pricing,
        distanceKm: 5,
        urgencyId: 'today',
        when: DateTime(2026, 5, 9, 14, 0),
      );
      expect(result.nightSurcharge, 45.0); // Saturday surcharge applies
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CleaningBookingService — pure heuristics
  // ═══════════════════════════════════════════════════════════════════════
  group('CleaningBookingService — estimateDurationMinutes', () {
    test('regular 2BR/1BA, 80m², no pets → ~180 min base + extras', () {
      // base 180 (≤100m²), bedrooms 2*10=20, bath 1*15=15, tasks 6*4=24
      final dur = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'regular_home',
        bedrooms: 2,
        bathrooms: 1,
        squareMeters: 80,
        hasPets: false,
        selectedTasksCount: 6,
        addOnsCount: 0,
      );
      expect(dur, 180 + 20 + 15 + 24);
    });

    test('deep_renovation × 2.0 multiplier', () {
      final dur = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'deep_renovation',
        bedrooms: 2,
        bathrooms: 1,
        squareMeters: 80,
        hasPets: false,
        selectedTasksCount: 6,
        addOnsCount: 0,
      );
      expect(dur, (180 * 2.0).round() + 20 + 15 + 24);
    });

    test('airbnb × 0.8 multiplier', () {
      final dur = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'airbnb',
        bedrooms: 2,
        bathrooms: 1,
        squareMeters: 80,
        hasPets: false,
        selectedTasksCount: 6,
        addOnsCount: 0,
      );
      expect(dur, (180 * 0.8).round() + 20 + 15 + 24);
    });

    test('hasPets adds 20 min', () {
      final without = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'regular_home',
        bedrooms: 2,
        bathrooms: 1,
        squareMeters: 80,
        hasPets: false,
        selectedTasksCount: 6,
        addOnsCount: 0,
      );
      final withPets = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'regular_home',
        bedrooms: 2,
        bathrooms: 1,
        squareMeters: 80,
        hasPets: true,
        selectedTasksCount: 6,
        addOnsCount: 0,
      );
      expect(withPets - without, 20);
    });

    test('clamped to [60, 600]', () {
      // Tiny config → clamped to 60
      final small = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'airbnb',
        bedrooms: 0,
        bathrooms: 0,
        squareMeters: 30,
        hasPets: false,
        selectedTasksCount: 0,
        addOnsCount: 0,
      );
      expect(small, greaterThanOrEqualTo(60));

      // Huge config → clamped to 600
      final huge = CleaningBookingService.estimateDurationMinutes(
        cleaningType: 'deep_renovation',
        bedrooms: 10,
        bathrooms: 10,
        squareMeters: 500,
        hasPets: true,
        selectedTasksCount: 30,
        addOnsCount: 30,
      );
      expect(huge, lessThanOrEqualTo(600));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // DeliveryBookingService
  // ═══════════════════════════════════════════════════════════════════════
  group('DeliveryBookingService — calculateTotal', () {
    test('5km delivery, scheduled → just base price', () {
      final profile = const DeliveryProfile(
        pricing: DeliveryPricing(
          smallPackage: 50,
          perKmAfter5: 3,
        ),
      );
      final total = DeliveryBookingService.calculateTotal(
        profile: profile,
        packageType: 'small_package',
        distanceKm: 5,
        timing: 'scheduled',
      );
      expect(total, 50.0); // no km surcharge below 5km
    });

    test('10km delivery → ₪50 base + 5km * ₪3 = ₪65', () {
      final profile = const DeliveryProfile(
        pricing: DeliveryPricing(
          smallPackage: 50,
          perKmAfter5: 3,
        ),
      );
      final total = DeliveryBookingService.calculateTotal(
        profile: profile,
        packageType: 'small_package',
        distanceKm: 10,
        timing: 'scheduled',
      );
      expect(total, 65.0);
    });

    test('immediate timing → adds surcharge if enabled', () {
      final profile = const DeliveryProfile(
        pricing: DeliveryPricing(
          smallPackage: 50,
          perKmAfter5: 3,
        ),
        availability: DeliveryAvailability(
          immediate: DeliveryImmediateOption(
            enabled: true,
            surcharge: 25,
          ),
        ),
      );
      final total = DeliveryBookingService.calculateTotal(
        profile: profile,
        packageType: 'small_package',
        distanceKm: 5,
        timing: 'immediate',
      );
      expect(total, 75.0); // 50 + 25
    });

    test('immediate but provider has it disabled → no surcharge', () {
      final profile = const DeliveryProfile(
        pricing: DeliveryPricing(
          smallPackage: 50,
          perKmAfter5: 3,
        ),
        availability: DeliveryAvailability(
          immediate: DeliveryImmediateOption(enabled: false, surcharge: 25),
        ),
      );
      final total = DeliveryBookingService.calculateTotal(
        profile: profile,
        packageType: 'small_package',
        distanceKm: 5,
        timing: 'immediate',
      );
      expect(total, 50.0);
    });

    test('add-ons total adds to final', () {
      final profile = const DeliveryProfile(
        pricing: DeliveryPricing(
          smallPackage: 50,
          perKmAfter5: 3,
        ),
      );
      final total = DeliveryBookingService.calculateTotal(
        profile: profile,
        packageType: 'small_package',
        distanceKm: 5,
        timing: 'scheduled',
        addOnsTotal: 20,
      );
      expect(total, 70.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // HandymanBookingService
  // ═══════════════════════════════════════════════════════════════════════
  group('HandymanBookingService — pricing math', () {
    final profile = HandymanProfile(
      pricing: const HandymanPricing(
        customPrices: {'leak': 200, 'paint': 300},
        emergencySurcharge: 100,
      ),
      punchListDiscount: const HandymanPunchListDiscount(),
    );

    test('servicesTotal: single item uses provided price', () {
      final items = [
        const HandymanPunchListItem(
          serviceId: 'leak',
          nameHe: 'דליפה',
          icon: '💧',
          estimatedMinutes: 60,
          price: 250,
          priority: 1,
        ),
      ];
      // priceFor returns the override (200) regardless of item.price
      final total = HandymanBookingService.servicesTotal(
        profile: profile,
        punchList: items,
      );
      expect(total, 200.0);
    });

    test('servicesTotal: multiple items sum correctly', () {
      final items = [
        const HandymanPunchListItem(
          serviceId: 'leak',
          nameHe: 'דליפה',
          icon: '💧',
          estimatedMinutes: 60,
          price: 200,
          priority: 1,
        ),
        const HandymanPunchListItem(
          serviceId: 'paint',
          nameHe: 'צבע',
          icon: '🎨',
          estimatedMinutes: 90,
          price: 300,
          priority: 2,
        ),
      ];
      final total = HandymanBookingService.servicesTotal(
        profile: profile,
        punchList: items,
      );
      expect(total, 500.0);
    });

    test('punch-list discount: 1 item → 0% (no discount)', () {
      final items = [
        const HandymanPunchListItem(
          serviceId: 'leak',
          nameHe: 'דליפה',
          icon: '💧',
          estimatedMinutes: 60,
          price: 200,
          priority: 1,
        ),
      ];
      final discount = HandymanBookingService.punchListDiscountAmount(
        profile: profile,
        punchList: items,
      );
      expect(discount, 0.0);
    });

    test('punch-list discount: 2 items → 10% off subtotal', () {
      final items = [
        const HandymanPunchListItem(
          serviceId: 'leak',
          nameHe: 'דליפה',
          icon: '💧',
          estimatedMinutes: 60,
          price: 200,
          priority: 1,
        ),
        const HandymanPunchListItem(
          serviceId: 'paint',
          nameHe: 'צבע',
          icon: '🎨',
          estimatedMinutes: 90,
          price: 300,
          priority: 2,
        ),
      ];
      final discount = HandymanBookingService.punchListDiscountAmount(
        profile: profile,
        punchList: items,
      );
      // 500 * 10% = 50
      expect(discount, 50.0);
    });

    test('calculateTotal: 2 items + materials + emergency', () {
      final items = [
        const HandymanPunchListItem(
          serviceId: 'leak',
          nameHe: 'דליפה',
          icon: '💧',
          estimatedMinutes: 60,
          price: 200,
          priority: 1,
        ),
        const HandymanPunchListItem(
          serviceId: 'paint',
          nameHe: 'צבע',
          icon: '🎨',
          estimatedMinutes: 90,
          price: 300,
          priority: 2,
        ),
      ];
      final total = HandymanBookingService.calculateTotal(
        profile: profile,
        punchList: items,
        materialsOption: 'provider_supplies',
        materialsEstimate: 80,
        urgency: 'emergency',
      );
      // services 500 - discount 50 + materials 80 + emergency 100 = 630
      expect(total, 630.0);
    });

    test('client_brings → materials cost = 0', () {
      final items = [
        const HandymanPunchListItem(
          serviceId: 'leak',
          nameHe: 'דליפה',
          icon: '💧',
          estimatedMinutes: 60,
          price: 200,
          priority: 1,
        ),
      ];
      final total = HandymanBookingService.calculateTotal(
        profile: profile,
        punchList: items,
        materialsOption: 'client_brings',
        materialsEstimate: 80,
        urgency: 'standard',
      );
      // services 200 - discount 0 + materials 0 = 200
      expect(total, 200.0);
    });
  });
}
