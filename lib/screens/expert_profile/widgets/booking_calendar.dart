import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'tokens.dart';

/// 60-day TableCalendar for date selection in the booking flow.
///
/// Extracted from `expert_profile_screen.dart` in §80. The calendar
/// is stateless — all state lives in the parent (focused day, selected
/// day, unavailable dates set). The parent passes them in + receives
/// the user's selection via [onDaySelected].
///
/// Unavailable dates are rendered with a red circle "disabled" badge.
class BookingCalendar extends StatelessWidget {
  const BookingCalendar({
    super.key,
    required this.unavailableDates,
    required this.selectedDay,
    required this.focusedDay,
    required this.onDaySelected,
  });

  final Set<DateTime> unavailableDates;
  final DateTime? selectedDay;
  final DateTime focusedDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: TableCalendar(
        locale: 'he_IL',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: focusedDay,
        headerStyle: const HeaderStyle(
            formatButtonVisible: false, titleCentered: true),
        selectedDayPredicate: (day) => isSameDay(selectedDay, day),
        enabledDayPredicate: (day) {
          final n = DateTime.utc(day.year, day.month, day.day);
          return !unavailableDates.contains(n);
        },
        onDaySelected: onDaySelected,
        calendarBuilders: CalendarBuilders(
          disabledBuilder: (context, day, _) {
            final n = DateTime.utc(day.year, day.month, day.day);
            if (!unavailableDates.contains(n)) return null;
            return Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: Center(
                  child: Text('${day.day}',
                      style: TextStyle(
                          color: Colors.red.shade300,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration: BoxDecoration(
              color: ExpertProfileTokens.purple, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: Color(0xFFE0E7FF), shape: BoxShape.circle),
          todayTextStyle: TextStyle(
              color: ExpertProfileTokens.purple, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
