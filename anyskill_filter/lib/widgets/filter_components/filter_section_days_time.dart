// lib/widgets/filter_components/filter_section_days_time.dart
//
// בלוק זמינות שבועית — 7 ימים + 4 חלקי יום.
// value: {days: Set<int>, times: Set<String>}

import 'package:flutter/material.dart';
import '../../models/filter_schema.dart';

class FilterSectionDaysTime extends StatelessWidget {
  final FilterSection section;
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const FilterSectionDaysTime({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
  });

  static const _indigo = Color(0xFF6366F1);
  static const _purple = Color(0xFF8B5CF6);
  static const _textPrimary = Color(0xFF0F172A);
  static const _borderLight = Color(0xFFF1F5F9);

  static const _dayLabels = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];
  static const _times = [
    {'value': 'morning', 'label': 'בוקר', 'range': '06-12', 'emoji': '🌅'},
    {'value': 'noon', 'label': 'צהריים', 'range': '12-16', 'emoji': '☀'},
    {'value': 'evening', 'label': 'אחה״צ', 'range': '16-20', 'emoji': '🌇'},
    {'value': 'night', 'label': 'ערב', 'range': '20-23', 'emoji': '🌙'},
  ];

  Set<int> get _activeDays {
    final raw = value?['days'];
    if (raw is Set) return raw.cast<int>();
    if (raw is List) return raw.cast<int>().toSet();
    return {};
  }

  Set<String> get _activeTimes {
    final raw = value?['times'];
    if (raw is Set) return raw.cast<String>();
    if (raw is List) return raw.cast<String>().toSet();
    return {};
  }

  void _toggleDay(int day) {
    final days = _activeDays.toSet();
    if (days.contains(day)) {
      days.remove(day);
    } else {
      days.add(day);
    }
    _emit(days: days);
  }

  void _toggleTime(String time) {
    final times = _activeTimes.toSet();
    if (times.contains(time)) {
      times.remove(time);
    } else {
      times.add(time);
    }
    _emit(times: times);
  }

  void _emit({Set<int>? days, Set<String>? times}) {
    final newDays = days ?? _activeDays;
    final newTimes = times ?? _activeTimes;
    if (newDays.isEmpty && newTimes.isEmpty) {
      onChanged(null);
    } else {
      onChanged({
        if (newDays.isNotEmpty) 'days': newDays,
        if (newTimes.isNotEmpty) 'times': newTimes,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ימים בשבוע',
          style: TextStyle(
            fontSize: 10.5,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(7, (i) {
            final active = _activeDays.contains(i);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: GestureDetector(
                  onTap: () => _toggleDay(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(colors: [_indigo, _purple])
                          : null,
                      color: active ? null : Colors.white,
                      border: Border.all(
                        color: active ? _indigo : _borderLight,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: active ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        const Text(
          'חלק יום',
          style: TextStyle(
            fontSize: 10.5,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _times.map((t) {
            final active = _activeTimes.contains(t['value']);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _buildTimeCard(t, active),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTimeCard(Map<String, String> t, bool active) {
    return GestureDetector(
      onTap: () => _toggleTime(t['value']!),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFAFBFF) : Colors.white,
          border: Border.all(
            color: active ? _indigo : _borderLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(t['emoji']!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              t['label']!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              t['range']!,
              style: const TextStyle(
                fontSize: 9.5,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
