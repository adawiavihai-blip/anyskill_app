// Smart Auto-Billing math for the babysitter CSM (CLAUDE.md §53).
//
// IMPORTANT: This service is ONLY responsible for the *estimate* shown to the
// customer at booking time, and the *final billing* once the babysitter taps
// "Sim job". Both flows produce a structured price breakdown that's saved on
// the job doc as `priceBreakdown` (existing escrow contract — same shape as
// pest/cleaning/handyman/etc).
//
// The actual GPS check on Start Job + the live-shift Timer + the Stripe
// charge live in the existing job-lifecycle layer (NOT this service).
//
// Rounding: every NIS-typed value is `(value * 100).round() / 100` per
// CLAUDE.md §18 Rule 7 (fee-first subtraction prevents ghost agorot).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/babysitter_profile.dart';
import '../utils/firestore_map.dart';

class BabysitterBookingPriceBreakdown {
  final double regularHours;
  final double regularAmount;
  final double nightHours;
  final double nightAmount;
  final double lateFee;
  final double holidaySurcharge;
  final double lastMinuteSurcharge;
  final double total;

  const BabysitterBookingPriceBreakdown({
    required this.regularHours,
    required this.regularAmount,
    required this.nightHours,
    required this.nightAmount,
    required this.lateFee,
    required this.holidaySurcharge,
    required this.lastMinuteSurcharge,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
        'regularHours': regularHours,
        'regularAmount': regularAmount,
        'nightHours': nightHours,
        'nightAmount': nightAmount,
        'lateFee': lateFee,
        'holidaySurcharge': holidaySurcharge,
        'lastMinuteSurcharge': lastMinuteSurcharge,
        'total': total,
      };
}

class BabysitterBookingService {
  static double _round2(double v) => (v * 100).round() / 100;

  /// Splits the [start, end] window into (regularHours, nightHours) where
  /// "night" is hours that fall inside [pricing.nightStartsAtHour,
  /// pricing.nightEndsAtHour] (wrapping past midnight). Walked minute-by-minute
  /// to keep the logic dead-simple and obvious — even multi-hour shifts
  /// finish in microseconds.
  static ({double regular, double night}) splitByTimeOfDay({
    required DateTime start,
    required DateTime end,
    required BabysitterPricingConfig pricing,
  }) {
    if (!end.isAfter(start)) return (regular: 0, night: 0);
    final ns = pricing.nightStartsAtHour;
    final ne = pricing.nightEndsAtHour;

    int regularMinutes = 0;
    int nightMinutes = 0;
    DateTime cursor = start;
    while (cursor.isBefore(end)) {
      final h = cursor.hour;
      final isNight = ns < ne
          ? (h >= ns && h < ne)
          : (h >= ns || h < ne); // wraps midnight, e.g. 22 → 6
      if (isNight) {
        nightMinutes++;
      } else {
        regularMinutes++;
      }
      cursor = cursor.add(const Duration(minutes: 1));
    }
    return (regular: regularMinutes / 60.0, night: nightMinutes / 60.0);
  }

  /// Estimates the price BEFORE the shift starts (used in client booking
  /// block live preview). [actualEnd] equals [agreedEnd] in the estimate.
  static BabysitterBookingPriceBreakdown estimate({
    required BabysitterPricingConfig pricing,
    required int numChildren,
    required DateTime agreedStart,
    required DateTime agreedEnd,
    required bool isHoliday,
    DateTime? bookingCreatedAt,
  }) {
    final hourlyRate = pricing.rateForChildren(numChildren);
    final split = splitByTimeOfDay(
      start: agreedStart,
      end: agreedEnd,
      pricing: pricing,
    );
    final regularAmount = split.regular * hourlyRate;
    final nightAmount =
        split.night * hourlyRate * (1 + pricing.nightSurchargePercent / 100);

    double holidaySurcharge = 0;
    if (isHoliday) {
      holidaySurcharge = (regularAmount + nightAmount) *
          pricing.holidaySurchargePercent /
          100;
    }

    double lastMinuteSurcharge = 0;
    if (bookingCreatedAt != null && pricing.lastMinuteThresholdHours > 0) {
      final hoursAhead = agreedStart.difference(bookingCreatedAt).inMinutes / 60.0;
      if (hoursAhead < pricing.lastMinuteThresholdHours) {
        lastMinuteSurcharge = (regularAmount + nightAmount) *
            pricing.lastMinuteSurchargePercent /
            100;
      }
    }

    final total =
        regularAmount + nightAmount + holidaySurcharge + lastMinuteSurcharge;

    return BabysitterBookingPriceBreakdown(
      regularHours: _round2(split.regular),
      regularAmount: _round2(regularAmount),
      nightHours: _round2(split.night),
      nightAmount: _round2(nightAmount),
      lateFee: 0,
      holidaySurcharge: _round2(holidaySurcharge),
      lastMinuteSurcharge: _round2(lastMinuteSurcharge),
      total: _round2(total),
    );
  }

  /// Final billing AFTER the babysitter taps "Sim job". Adds the late fee
  /// computed from the gap between [agreedEnd] and [actualEnd]. Capped at
  /// [pricing.lateFeeMaxAmount].
  static BabysitterBookingPriceBreakdown finalBill({
    required BabysitterPricingConfig pricing,
    required int numChildren,
    required DateTime agreedStart,
    required DateTime agreedEnd,
    required DateTime actualStart,
    required DateTime actualEnd,
    required bool isHoliday,
    DateTime? bookingCreatedAt,
  }) {
    final hourlyRate = pricing.rateForChildren(numChildren);
    final split = splitByTimeOfDay(
      start: actualStart,
      end: actualEnd,
      pricing: pricing,
    );
    final regularAmount = split.regular * hourlyRate;
    final nightAmount =
        split.night * hourlyRate * (1 + pricing.nightSurchargePercent / 100);

    // Late fee: only the portion of [actualEnd] past [agreedEnd] counts.
    double lateFee = 0;
    if (actualEnd.isAfter(agreedEnd)) {
      final lateMinutes = actualEnd.difference(agreedEnd).inMinutes;
      if (lateMinutes > 0 && pricing.lateFeeIntervalMinutes > 0) {
        final units = (lateMinutes / pricing.lateFeeIntervalMinutes).ceil();
        lateFee = units * pricing.lateFeePerInterval;
        if (lateFee > pricing.lateFeeMaxAmount) {
          lateFee = pricing.lateFeeMaxAmount;
        }
      }
    }

    double holidaySurcharge = 0;
    if (isHoliday) {
      holidaySurcharge = (regularAmount + nightAmount) *
          pricing.holidaySurchargePercent /
          100;
    }

    double lastMinuteSurcharge = 0;
    if (bookingCreatedAt != null && pricing.lastMinuteThresholdHours > 0) {
      final hoursAhead = agreedStart.difference(bookingCreatedAt).inMinutes / 60.0;
      if (hoursAhead < pricing.lastMinuteThresholdHours) {
        lastMinuteSurcharge = (regularAmount + nightAmount) *
            pricing.lastMinuteSurchargePercent /
            100;
      }
    }

    final total = regularAmount +
        nightAmount +
        lateFee +
        holidaySurcharge +
        lastMinuteSurcharge;

    return BabysitterBookingPriceBreakdown(
      regularHours: _round2(split.regular),
      regularAmount: _round2(regularAmount),
      nightHours: _round2(split.night),
      nightAmount: _round2(nightAmount),
      lateFee: _round2(lateFee),
      holidaySurcharge: _round2(holidaySurcharge),
      lastMinuteSurcharge: _round2(lastMinuteSurcharge),
      total: _round2(total),
    );
  }

  /// Convenience: builds a Hebrew explanation of the breakdown for the
  /// "what was I charged for?" UI.
  static String explanationFor(BabysitterBookingPriceBreakdown bd) {
    final parts = <String>[];
    if (bd.regularHours > 0) {
      parts.add('${bd.regularHours.toStringAsFixed(1)} שעות רגילות');
    }
    if (bd.nightHours > 0) {
      parts.add('${bd.nightHours.toStringAsFixed(1)} שעות לילה');
    }
    if (bd.lateFee > 0) {
      parts.add('קנס איחור: ${bd.lateFee.toStringAsFixed(0)} ₪');
    }
    if (bd.holidaySurcharge > 0) {
      parts.add('תוספת חג');
    }
    if (bd.lastMinuteSurcharge > 0) {
      parts.add('תוספת הזמנה ברגע האחרון');
    }
    return parts.join(' · ');
  }

  /// Most-recent completed babysitting booking with [providerId] — used by
  /// the client booking block to prefill (Express Reorder).
  static Future<Map<String, dynamic>?> getLastBookingPreferences(
      String providerId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: uid)
          .where('expertId', isEqualTo: providerId)
          .where('babysitterPreferences', isNull: false)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 4));
      if (snap.docs.isEmpty) return null;
      return safeMap(snap.docs.first.data()['babysitterPreferences']);
    } catch (_) {
      return null;
    }
  }
}
