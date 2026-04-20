import 'package:flutter/material.dart';

/// Tiny pill showing coverage breadth: 🌍 X ערים. Color tints by spread:
///   - 0 ערים    → red
///   - 1-3       → amber
///   - 4-9       → blue
///   - 10+       → green
class CoverageChip extends StatelessWidget {
  const CoverageChip({super.key, required this.cities});

  final int cities;

  @override
  Widget build(BuildContext context) {
    final color = cities >= 10
        ? const Color(0xFF10B981)
        : cities >= 4
            ? const Color(0xFF3B82F6)
            : cities >= 1
                ? const Color(0xFFF59E0B)
                : const Color(0xFFEF4444);

    final label = cities == 0
        ? 'אין כיסוי'
        : cities == 1
            ? 'עיר אחת'
            : '$cities ערים';

    return Tooltip(
      message: 'מספר ערים שונות שבהן יש ספק פעיל',
      child: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
