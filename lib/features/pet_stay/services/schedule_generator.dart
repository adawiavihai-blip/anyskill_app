/// AnySkill — Schedule Generator (Pet Stay Tracker v13.0.0)
///
/// Turns a dog's daily routine (meals/day, walks/day, medications, bedtime)
/// into concrete [ScheduleItem]s across each day of the stay.
///
/// Only generated for PENSION bookings. Dog-walker bookings skip the
/// schedule — the walk session itself is the activity.
library;

import '../models/dog_profile.dart';
import '../models/schedule_item.dart';

class ScheduleGenerator {
  ScheduleGenerator._();

  /// Returns an empty list for dog-walker bookings (isPension=false) or
  /// bookings with `endDate < startDate`.
  static List<ScheduleItem> generate({
    required DogProfile dog,
    required DateTime startDate,
    required DateTime endDate,
    required String customerId,
    required String expertId,
    required bool isPension,
  }) {
    if (!isPension) return const [];

    final days = _daysBetween(startDate, endDate);
    if (days.isEmpty) return const [];

    final items = <ScheduleItem>[];

    for (final day in days) {
      final dayKey = dayKeyOf(day);
      int sortCursor = 0;

      // ── Meals ────────────────────────────────────────────────────────
      for (final t in _feedTimes(dog.feedingTimesPerDay)) {
        items.add(ScheduleItem(
          dayKey: dayKey,
          time: t,
          type: 'feed',
          title: _mealLabel(t),
          description: [dog.foodBrand, dog.foodAmount]
              .where((s) => s.trim().isNotEmpty)
              .join(' · '),
          sortOrder: sortCursor++,
          customerId: customerId,
          expertId: expertId,
        ));
      }

      // ── Walks ────────────────────────────────────────────────────────
      for (final t in _walkTimes(dog.walksPerDay)) {
        items.add(ScheduleItem(
          dayKey: dayKey,
          time: t,
          type: 'walk',
          title: 'הליכון',
          description: '',
          sortOrder: sortCursor++,
          customerId: customerId,
          expertId: expertId,
        ));
      }

      // ── Medications — one item per med per day ───────────────────────
      for (final med in dog.medications) {
        if (med.name.trim().isEmpty) continue;
        items.add(ScheduleItem(
          dayKey: dayKey,
          time: '09:00',
          type: 'medication',
          title: med.name,
          description: [med.dosage, med.frequency, med.instructions]
              .where((s) => s.trim().isNotEmpty)
              .join(' · '),
          sortOrder: sortCursor++,
          customerId: customerId,
          expertId: expertId,
        ));
      }

      // ── Bedtime ──────────────────────────────────────────────────────
      if (dog.bedtime.trim().isNotEmpty) {
        items.add(ScheduleItem(
          dayKey: dayKey,
          time: dog.bedtime,
          type: 'sleep',
          title: 'שינה',
          description: dog.specialInstructions,
          sortOrder: sortCursor++,
          customerId: customerId,
          expertId: expertId,
        ));
      }
    }

    // Final sort: by dayKey, then time, then sortOrder.
    items.sort((a, b) {
      final dk = a.dayKey.compareTo(b.dayKey);
      if (dk != 0) return dk;
      final tk = a.time.compareTo(b.time);
      if (tk != 0) return tk;
      return a.sortOrder.compareTo(b.sortOrder);
    });

    return items;
  }

  /// Inclusive date range [start..end] normalized to local date-only.
  static List<DateTime> _daysBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) return const [];
    final result = <DateTime>[];
    var cur = s;
    while (!cur.isAfter(e)) {
      result.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return result;
  }

  static List<String> _feedTimes(int count) {
    switch (count) {
      case 0:
        return const [];
      case 1:
        return const ['08:00'];
      case 2:
        return const ['08:00', '18:00'];
      case 3:
        return const ['08:00', '13:00', '18:00'];
      case 4:
        return const ['07:00', '12:00', '17:00', '21:00'];
      default:
        return const ['07:00', '11:00', '14:00', '17:00', '20:00'];
    }
  }

  static List<String> _walkTimes(int count) {
    switch (count) {
      case 0:
        return const [];
      case 1:
        return const ['10:00'];
      case 2:
        return const ['09:00', '17:00'];
      case 3:
        return const ['08:00', '13:00', '19:00'];
      default:
        return const ['07:30', '11:30', '15:30', '19:30'];
    }
  }

  static String _mealLabel(String time) {
    final hour = int.tryParse(time.split(':').first) ?? 12;
    if (hour < 11) return 'ארוחת בוקר';
    if (hour < 15) return 'ארוחת צהריים';
    if (hour < 20) return 'ארוחת ערב';
    return 'ארוחה לפני שינה';
  }
}
