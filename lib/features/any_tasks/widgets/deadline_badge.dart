/// AnyTasks — Deadline countdown badge.
///
/// Single source of truth for "time remaining" display in both the
/// customer's MyTasksScreen card and the provider's ProviderFeedScreen
/// card. Polls `DateTime.now()` once at build — parent should rebuild
/// periodically (e.g. `StreamBuilder.periodic(Duration(minutes: 1))`)
/// if a live countdown is desired. For normal Firestore-streamed cards
/// the snapshot updates are frequent enough.
library;

import 'package:flutter/material.dart';

import '../theme/any_tasks_palette.dart';

/// Renders a compact pill showing time-until-deadline.
/// Shows nothing (zero-height SizedBox) if `deadline` is null.
class DeadlineBadge extends StatelessWidget {
  final DateTime? deadline;

  /// Compact = icon + short label only. False = icon + long label.
  final bool compact;

  const DeadlineBadge({super.key, required this.deadline, this.compact = true});

  @override
  Widget build(BuildContext context) {
    if (deadline == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final diff = deadline!.difference(now);

    final _DeadlineVisual v = _resolveVisual(diff);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: v.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: v.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.icon, size: 11, color: v.fg),
          const SizedBox(width: 4),
          Text(
            compact ? v.shortLabel : v.longLabel,
            style: TextStyle(
              color: v.fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadlineVisual {
  final Color bg;
  final Color fg;
  final Color border;
  final IconData icon;
  final String shortLabel;
  final String longLabel;

  const _DeadlineVisual({
    required this.bg,
    required this.fg,
    required this.border,
    required this.icon,
    required this.shortLabel,
    required this.longLabel,
  });
}

_DeadlineVisual _resolveVisual(Duration diff) {
  // Past — task missed its deadline. Grey.
  if (diff.isNegative) {
    return _DeadlineVisual(
      bg: Colors.grey.shade100,
      fg: Colors.grey.shade700,
      border: Colors.grey.shade300,
      icon: Icons.event_busy_rounded,
      shortLabel: 'פג תוקף',
      longLabel: 'פג תוקף',
    );
  }

  // Under 2 hours — red, urgent.
  if (diff.inMinutes < 120) {
    final mins = diff.inMinutes;
    final label =
        mins < 1 ? 'פחות מדקה' : mins == 1 ? 'דקה' : 'נותרו $mins דק׳';
    return _DeadlineVisual(
      bg: const Color(0xFFFEE2E2),
      fg: const Color(0xFFB91C1C),
      border: const Color(0xFFFCA5A5),
      icon: Icons.whatshot_rounded,
      shortLabel: label,
      longLabel: label,
    );
  }

  // Under 24 hours — amber, warning.
  if (diff.inHours < 24) {
    final hours = diff.inHours;
    final label = hours == 1 ? 'נותרה שעה' : 'נותרו $hours שעות';
    return _DeadlineVisual(
      bg: const Color(0xFFFEF3C7),
      fg: const Color(0xFF92400E),
      border: const Color(0xFFFCD34D),
      icon: Icons.timer_rounded,
      shortLabel: label,
      longLabel: label,
    );
  }

  // Under 3 days — green, but emphasised.
  final days = diff.inDays;
  if (days <= 3) {
    final label = days == 1 ? 'נותר יום' : 'נותרו $days ימים';
    return _DeadlineVisual(
      bg: const Color(0xFFD1FAE5),
      fg: const Color(0xFF047857),
      border: const Color(0xFF6EE7B7),
      icon: Icons.event_rounded,
      shortLabel: label,
      longLabel: label,
    );
  }

  // 4+ days — neutral green.
  final label = 'נותרו $days ימים';
  return _DeadlineVisual(
    bg: TasksPalette.bgPrimary,
    fg: TasksPalette.textSecondary,
    border: TasksPalette.borderLight,
    icon: Icons.calendar_today_rounded,
    shortLabel: label,
    longLabel: label,
  );
}
