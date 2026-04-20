import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';

/// Compact status chip strip rendered inside [CategoryRowCard]. Each chip is
/// a 22px-tall pill with an icon + tiny Hebrew label. Covers the v3 spec §7.3
/// "row 1" chips: status / popularity / CSM / warning.
class CategoryStatusChips extends StatelessWidget {
  const CategoryStatusChips({super.key, required this.category});

  final CategoryV3Model category;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    // Hidden vs Active
    if (category.isHidden) {
      chips.add(const _StatusChip(
        label: 'מוסתרת',
        icon: Icons.visibility_off_rounded,
        color: Color(0xFF6B7280),
      ));
    } else {
      chips.add(const _StatusChip(
        label: 'פעילה',
        icon: Icons.check_circle_outline_rounded,
        color: Color(0xFF10B981),
      ));
    }

    // Pinned (promoted)
    if (category.isPinned) {
      chips.add(const _StatusChip(
        label: 'מקודמת',
        icon: Icons.push_pin_rounded,
        color: Color(0xFF6366F1),
      ));
    }

    // CSM badge
    if (category.isCsm) {
      chips.add(_StatusChip(
        label: 'CSM · ${category.csmModule}',
        icon: Icons.extension_rounded,
        color: const Color(0xFF8B5CF6),
      ));
    }

    // Warning: zero providers
    final activeProviders = category.analytics?.activeProviders ?? 0;
    if (activeProviders == 0 && !category.isHidden) {
      chips.add(const _StatusChip(
        label: 'אין ספקים',
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFF59E0B),
      ));
    }

    // Custom tags (manual override)
    for (final t in category.customTags) {
      chips.add(_StatusChip(
        label: t,
        icon: Icons.label_outline_rounded,
        color: const Color(0xFFEC4899),
      ));
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
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
    );
  }
}
