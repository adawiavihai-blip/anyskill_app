import 'package:flutter/material.dart';

import '../services/category_analytics_service.dart';

/// 5-card KPI strip at the top of the v3 tab (spec §7.1 row 2).
///
/// Cards:
///   1. Total root categories
///   2. Total sub-categories
///   3. Categories missing image (warning tone)
///   4. Categories with no providers (danger tone)
///   5. Categories wired to a CSM (info tone)
///
/// Responsive: 5-across on desktop (≥1024), 3+2 on tablet (≥720), 2+2+1 on phone.
class KpiMetricsRow extends StatelessWidget {
  const KpiMetricsRow({super.key, required this.kpis});

  final CategoriesKpis kpis;

  @override
  Widget build(BuildContext context) {
    final cards = <_KpiCardData>[
      _KpiCardData(
        label: 'קטגוריות',
        value: '${kpis.totalCategories}',
        icon: Icons.category_rounded,
        accent: const Color(0xFF6366F1),
      ),
      _KpiCardData(
        label: 'תתי-קטגוריות',
        value: '${kpis.totalSubcategories}',
        icon: Icons.account_tree_rounded,
        accent: const Color(0xFF8B5CF6),
      ),
      _KpiCardData(
        label: 'חסרות תמונה',
        value: '${kpis.missingImageCount}',
        icon: Icons.image_not_supported_rounded,
        accent: const Color(0xFFF59E0B),
        emphasized: kpis.missingImageCount > 0,
      ),
      _KpiCardData(
        label: 'בלי ספקים',
        value: '${kpis.noProvidersCount}',
        icon: Icons.person_off_rounded,
        accent: const Color(0xFFEF4444),
        emphasized: kpis.noProvidersCount > 0,
      ),
      _KpiCardData(
        label: 'בתוך CSM',
        value: '${kpis.inCsmCount}',
        icon: Icons.extension_rounded,
        accent: const Color(0xFF10B981),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 1024 ? 5 : (w >= 720 ? 3 : 2);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cols == 5 ? 2.4 : (cols == 3 ? 2.2 : 2.0),
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => _KpiCard(data: cards[i]),
        );
      },
    );
  }
}

class _KpiCardData {
  const _KpiCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool emphasized;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    final tint = data.accent.withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: data.emphasized
              ? data.accent.withValues(alpha: 0.4)
              : Colors.black.withValues(alpha: 0.06),
          width: data.emphasized ? 1.5 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(data.icon, size: 18, color: data.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B7280),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
