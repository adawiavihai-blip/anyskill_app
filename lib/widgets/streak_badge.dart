/// AnySkill — Streak Badge Widget
///
/// Displays a fire icon with the current streak count.
/// Pulses orange when streak is at risk of breaking.
library;

import 'package:flutter/material.dart';
import '../services/engagement_service.dart';

class StreakBadge extends StatelessWidget {
  final int streak;
  final bool atRisk;

  const StreakBadge({
    super.key,
    required this.streak,
    this.atRisk = false,
  });

  /// Factory that reads streak data from a user data map.
  factory StreakBadge.fromUserData(Map<String, dynamic> data) {
    return StreakBadge(
      streak: (data['streak'] as num? ?? 0).toInt(),
      atRisk: EngagementService.isStreakAtRisk(data),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (streak <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: atRisk
              ? [const Color(0xFFF97316), const Color(0xFFEF4444)]
              : [const Color(0xFFF97316), const Color(0xFFF59E0B)],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withValues(alpha: atRisk ? 0.4 : 0.2),
            blurRadius: atRisk ? 10 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$streak',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 3),
          const Text('🔥', style: TextStyle(fontSize: 14)),
          if (atRisk) ...[
            const SizedBox(width: 4),
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 14),
          ],
        ],
      ),
    );
  }
}
