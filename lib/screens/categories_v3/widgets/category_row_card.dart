import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';
import 'category_status_chips.dart';
import 'conversion_funnel_inline.dart';
import 'coverage_chip.dart';
import 'health_score_bar.dart';
import 'sparkline_widget.dart';

/// Single category row card — Phase C version per spec §7.3.
///
/// Anatomy (final):
///   [checkbox] [⋮⋮ drag handle] [emoji avatar 40] [content area] [sparkline 60×28]
///   [coverage chip] [health bar+score] [▼ expand]
///
/// `content area` =
///   row 1: [name] [chips: status / pinned / CSM / warning / custom_tags]
///   row 2: ConversionFunnelInline (views → clicks → orders + revenue + growth + last edited)
class CategoryRowCard extends StatelessWidget {
  const CategoryRowCard({
    super.key,
    required this.category,
    required this.expanded,
    required this.onToggleExpand,
    required this.selected,
    required this.onToggleSelect,
    required this.dragEnabled,
    this.dragHandle,
    this.onEdit,
    this.onTogglePin,
    this.onToggleHide,
    this.focused = false,
  });

  final CategoryV3Model category;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final bool selected;
  final VoidCallback onToggleSelect;
  final bool dragEnabled;
  final Widget? dragHandle;
  final VoidCallback? onEdit;
  final VoidCallback? onTogglePin;
  final VoidCallback? onToggleHide;

  /// Highlights the row when keyboard navigation has focus on it.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final analytics = category.analytics;
    final coverage = analytics?.coverageCities ?? 0;
    final sparkline = analytics?.sparkline30d ?? const <int>[];
    final growth = analytics?.growth30d ?? 0;
    final lastEdited = category.adminMeta?.lastEditedAt;

    // Mobile-responsive: hide sparkline + coverage on screens < 480px so the
    // row doesn't overflow at iPhone-min width (360px). Health bar stays —
    // it's the most actionable signal. Edit pencil also stays.
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isCompact = viewportWidth < 480;

    final borderColor = selected
        ? const Color(0xFF6366F1)
        : focused
            ? const Color(0xFF6366F1).withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.06);

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFF0F1FF)
            : (focused ? const Color(0xFFFAFBFF) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: selected || focused ? 1.5 : 0.5,
        ),
      ),
      child: InkWell(
        onTap: onToggleExpand,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Checkbox
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelect(),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

              // Drag handle (only enabled in tree view)
              if (dragEnabled && dragHandle != null) ...[
                const SizedBox(width: 4),
                dragHandle!,
              ],

              const SizedBox(width: 6),

              // Avatar
              _Avatar(category: category),
              const SizedBox(width: 10),

              // Content (name + chips + funnel + last edited)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    ConversionFunnelInline(analytics: analytics),
                    if (lastEdited != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'עודכן ${_relative(lastEdited)} ע״י ${category.adminMeta?.lastEditedBy ?? "מערכת"}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Sparkline (hidden on compact)
              if (analytics != null && !isCompact) ...[
                const SizedBox(width: 8),
                SparklineWidget(
                  points: _padTo30(sparkline),
                  growthPercent: growth,
                ),
              ],

              // Coverage chip (hidden on compact)
              if (analytics != null && !isCompact) ...[
                const SizedBox(width: 8),
                CoverageChip(cities: coverage),
              ],

              // Health bar — always shown (most actionable signal)
              if (analytics != null) ...[
                const SizedBox(width: 10),
                HealthScoreBar(
                  score: analytics.healthScore,
                  barWidth: isCompact ? 36 : 50,
                ),
              ],

              // Inline edit + actions menu
              if (onEdit != null) ...[
                const SizedBox(width: 6),
                _InlineIconBtn(
                  icon: Icons.edit_outlined,
                  tooltip: 'ערוך (E)',
                  onTap: onEdit!,
                ),
              ],

              const SizedBox(width: 2),
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

  static List<int> _padTo30(List<int> data) {
    if (data.length >= 30) return data.sublist(data.length - 30);
    return List<int>.filled(30 - data.length, 0) + data;
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    return 'לפני ${(diff.inDays / 7).floor()} שבועות';
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

class _InlineIconBtn extends StatelessWidget {
  const _InlineIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(4),
          child: Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        ),
      ),
    );
  }
}
