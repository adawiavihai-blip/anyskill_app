import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// The "Global → Category → Provider" breadcrumb at the top of the
/// Commission Control Center (section 5).
class CommissionHierarchyVisual extends StatelessWidget {
  const CommissionHierarchyVisual({
    super.key,
    required this.globalPct,
    required this.customCategoryCount,
    required this.customProviderCount,
  });

  final double globalPct;
  final int customCategoryCount;
  final int customProviderCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MonetizationTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: Row(
        children: [
          _HierarchyChip(
            label: 'שכבה 1 — גלובלי',
            value: '${globalPct.toStringAsFixed(globalPct == globalPct.toInt() ? 0 : 1)}%',
          ),
          const _HierarchyChevron(),
          _HierarchyChip(
            label: 'שכבה 2 — קטגוריה',
            value: '$customCategoryCount מותאמות',
          ),
          const _HierarchyChevron(),
          _HierarchyChip(
            label: 'שכבה 3 — ספק',
            value: '$customProviderCount פרטניות',
          ),
        ],
      ),
    );
  }
}

class _HierarchyChip extends StatelessWidget {
  const _HierarchyChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MonetizationTokens.radiusSm),
          border: Border.all(color: MonetizationTokens.borderSoft, width: 0.5),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                  fontSize: 10,
                  color: MonetizationTokens.textTertiary,
                )),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _HierarchyChevron extends StatelessWidget {
  const _HierarchyChevron();
  @override
  Widget build(BuildContext context) {
    // RTL: the arrow should point LEFT visually, so we use chevron_left.
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: Icon(Icons.chevron_left_rounded,
          size: 14, color: MonetizationTokens.textTertiary),
    );
  }
}
