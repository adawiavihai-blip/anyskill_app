import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';
import 'category_status_chips.dart';

/// Single category row card — basic Phase B version per spec §7.3.
///
/// Anatomy (Phase B):
///   [emoji avatar 40] [name + chips + last-edited line] [health number] [▼ expand]
///
/// Phase C will add: ⋮⋮ drag handle, sparkline, coverage chip, health BAR
/// (not just number), conversion funnel inline, ✏ ⋯ inline actions.
class CategoryRowCard extends StatelessWidget {
  const CategoryRowCard({
    super.key,
    required this.category,
    required this.expanded,
    required this.onToggleExpand,
    this.onEdit,
    this.onTogglePin,
    this.onToggleHide,
  });

  final CategoryV3Model category;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onEdit;
  final VoidCallback? onTogglePin;
  final VoidCallback? onToggleHide;

  @override
  Widget build(BuildContext context) {
    final analytics = category.analytics;
    final orders = analytics?.orders30d ?? 0;
    final revenue = analytics?.revenue30d ?? 0;
    final activeProviders = analytics?.activeProviders ?? 0;
    final hasMeaningfulMetrics = analytics != null &&
        (orders > 0 || activeProviders > 0);

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        onTap: onToggleExpand,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Emoji / icon avatar
              _Avatar(category: category),
              const SizedBox(width: 12),

              // Content (name + chips + meta)
              Expanded(child: _ContentColumn(
                category: category,
                hasMeaningfulMetrics: hasMeaningfulMetrics,
                orders: orders,
                revenue: revenue,
                activeProviders: activeProviders,
              )),

              // Health number — Phase C will replace with health BAR
              if (analytics != null) ...[
                const SizedBox(width: 8),
                _HealthNumber(score: analytics.healthScore),
                const SizedBox(width: 4),
              ],

              // Expand chevron
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.category});
  final CategoryV3Model category;

  @override
  Widget build(BuildContext context) {
    final color = _hexOr(category.color, const Color(0xFF6366F1));
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: _avatarChild(context, color),
    );
  }

  Widget _avatarChild(BuildContext context, Color color) {
    final iconUrl = category.iconUrl;
    final imageUrl = category.imageUrl;
    if (iconUrl.isNotEmpty || (imageUrl?.isNotEmpty ?? false)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          iconUrl.isNotEmpty ? iconUrl : imageUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initial(color),
        ),
      );
    }
    return _initial(color);
  }

  Widget _initial(Color color) {
    final initial =
        category.name.isNotEmpty ? category.name.characters.first : '?';
    return Text(
      initial,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }

  Color _hexOr(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final clean = hex.replaceFirst('#', '');
    final parsed = int.tryParse(clean, radix: 16);
    if (parsed == null) return fallback;
    if (clean.length == 6) return Color(0xFF000000 | parsed);
    if (clean.length == 8) return Color(parsed);
    return fallback;
  }
}

class _ContentColumn extends StatelessWidget {
  const _ContentColumn({
    required this.category,
    required this.hasMeaningfulMetrics,
    required this.orders,
    required this.revenue,
    required this.activeProviders,
  });

  final CategoryV3Model category;
  final bool hasMeaningfulMetrics;
  final int orders;
  final double revenue;
  final int activeProviders;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name + chips row
        Row(
          children: [
            Flexible(
              child: Text(
                category.name,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 3,
              child: CategoryStatusChips(category: category),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Meta line — orders, revenue, providers, last edited
        Text(
          _metaLine(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  String _metaLine() {
    final parts = <String>[];
    if (hasMeaningfulMetrics) {
      if (orders > 0) parts.add('$orders הזמנות (30 ימים)');
      if (revenue > 0) parts.add('₪${revenue.toStringAsFixed(0)}');
      if (activeProviders > 0) parts.add('$activeProviders ספקים');
    } else {
      // Q4-B+C: real impressions/clicks not tracked yet → show "—"
      parts.add('— הזמנות');
    }
    final lastEdited = category.adminMeta?.lastEditedAt;
    if (lastEdited != null) {
      parts.add('עודכן ${_relative(lastEdited)}');
    }
    return parts.join(' · ');
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    return 'לפני ${(diff.inDays / 7).floor()} שבועות';
  }
}

class _HealthNumber extends StatelessWidget {
  const _HealthNumber({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75
        ? const Color(0xFF10B981)
        : score >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
