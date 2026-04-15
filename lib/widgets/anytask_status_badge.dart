/// AnyTasks 3.0 — Status Badge Widget
///
/// Small colored badge that displays the current task status in Hebrew.
/// Follows the existing badge pattern from community_hub_screen.dart.
library;

import 'package:flutter/material.dart';
import '../models/anytask.dart';

class AnytaskStatusBadge extends StatelessWidget {
  final String status;
  final double fontSize;

  const AnytaskStatusBadge({
    super.key,
    required this.status,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final config = _configFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: config.color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: fontSize + 2, color: config.color),
          const SizedBox(width: 4),
          Text(
            config.label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: config.color,
            ),
          ),
        ],
      ),
    );
  }

  static _BadgeConfig _configFor(String status) {
    switch (status) {
      case AnyTaskStatus.open:
        return _BadgeConfig('פתוחה', const Color(0xFF6366F1), Icons.visibility_rounded);
      case AnyTaskStatus.claimed:
        return _BadgeConfig('נתפסה', const Color(0xFFF59E0B), Icons.person_rounded);
      case AnyTaskStatus.inProgress:
        return _BadgeConfig('בביצוע', const Color(0xFF3B82F6), Icons.engineering_rounded);
      case AnyTaskStatus.proofSubmitted:
        return _BadgeConfig('ממתין לאישור', const Color(0xFF8B5CF6), Icons.hourglass_top_rounded);
      case AnyTaskStatus.completed:
        return _BadgeConfig('הושלמה', const Color(0xFF10B981), Icons.check_circle_rounded);
      case AnyTaskStatus.cancelled:
        return _BadgeConfig('בוטלה', const Color(0xFF6B7280), Icons.cancel_rounded);
      case AnyTaskStatus.disputed:
        return _BadgeConfig('במחלוקת', const Color(0xFFEF4444), Icons.gavel_rounded);
      case AnyTaskStatus.resolved:
        return _BadgeConfig('נפתרה', const Color(0xFF10B981), Icons.handshake_rounded);
      case AnyTaskStatus.expired:
        return _BadgeConfig('פגה', const Color(0xFF6B7280), Icons.timer_off_rounded);
      default:
        return _BadgeConfig(status, const Color(0xFF6B7280), Icons.help_outline_rounded);
    }
  }
}

class _BadgeConfig {
  final String label;
  final Color color;
  final IconData icon;
  const _BadgeConfig(this.label, this.color, this.icon);
}
