/// Calendar-specific display widgets for the availability manager.
///
/// Extracted from my_bookings_screen.dart (Phase 1 refactor).
/// All widgets are pure display — zero coupling to parent state.
library;

import 'package:flutter/material.dart';

// ── Striped blocked day cell (calendar) ────────────────────────────────────

class StripedBlockedDay extends StatelessWidget {
  final DateTime day;
  final bool     isSelected;

  const StripedBlockedDay({super.key, required this.day, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.7), width: 1.5),
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: const DiagonalStripesPainter(),
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: isSelected ? Colors.redAccent : Colors.red[700],
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DiagonalStripesPainter extends CustomPainter {
  const DiagonalStripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.12)
      ..strokeWidth = 3;
    const step = 6.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Block type chip (full day / time range toggle) ─────────────────────────

class BlockTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const BlockTypeChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey[700],
                )),
          ],
        ),
      ),
    );
  }
}

// ── Time dropdown (30-min intervals) ───────────────────────────────────────

class CalendarTimeDropdown extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const CalendarTimeDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  static final _times = [
    for (int h = 6; h <= 22; h++) ...[
      '${h.toString().padLeft(2, '0')}:00',
      '${h.toString().padLeft(2, '0')}:30',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _times.contains(value) ? value : _times.first,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
          items: _times.map((t) => DropdownMenuItem(
            value: t,
            child: Text(t),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ── Reason chip (personal / break / appointment) ───────────────────────────

class ReasonChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const ReasonChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF97316).withValues(alpha: 0.5)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14,
              color: isSelected ? const Color(0xFFF97316) : Colors.grey[500]),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFFF97316) : Colors.grey[600],
              )),
        ]),
      ),
    );
  }
}
