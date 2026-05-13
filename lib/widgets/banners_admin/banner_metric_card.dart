import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// A single KPI card in the 4-metric strip at the top of the banners tab.
///
/// Layout (per the mockup's "KPIs" section):
/// ```
/// ┌─────────────────────────────┐
/// │ label (11px, ink3)          │
/// │                             │
/// │ 48,219          ▂▃▇▅▇▃      │  ← big metric + optional trailing
/// │ (22px, ink,       (sparkline
/// │  letter -0.02em)   or other Widget)
/// │                             │
/// │ ↑ 12.4%  vs 7d             │  ← trend (11px, colored)
/// └─────────────────────────────┘
/// ```
///
/// [trendPercent] is shown as a `+`/`-` prefix pill:
///  - positive → [BannersTokens.success] with ↑
///  - negative → [BannersTokens.danger] with ↓
///  - zero/null → [BannersTokens.ink3] with →
///
/// Trailing widget is typically a [BannerSparkline] but can be anything
/// (progress ring, mini-chart, etc.).
class BannerMetricCard extends StatelessWidget {
  const BannerMetricCard({
    super.key,
    required this.label,
    required this.valueText,
    this.trendPercent,
    this.trendSuffix = 'לעומת 7 ימים',
    this.trailing,
    this.accent = false,
  });

  final String label;
  final String valueText;
  final double? trendPercent;
  final String trendSuffix;
  final Widget? trailing;

  /// When true, the valueText renders in accent color — used for the
  /// "attributed revenue" card per the mockup.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final trendColor = _trendColor(trendPercent);
    final trendIcon = _trendIcon(trendPercent);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BannersTokens.spaceLg,
        vertical: BannersTokens.spaceMd + 2,
      ),
      color: BannersTokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Label ──────────────────────────────────────────────────
          Text(label, style: BannersTokens.captionSm),
          const SizedBox(height: 6),

          // ── Metric + trailing ─────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  valueText,
                  style: BannersTokens.metric.copyWith(
                    color: accent ? BannersTokens.accent : BannersTokens.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: BannersTokens.spaceSm),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 6),

          // ── Trend ──────────────────────────────────────────────────
          if (trendPercent != null)
            Row(
              children: [
                Icon(trendIcon, size: 11, color: trendColor),
                const SizedBox(width: 2),
                Text(
                  '${trendPercent!.abs().toStringAsFixed(1)}%',
                  style: BannersTokens.captionSm.copyWith(color: trendColor),
                ),
                const SizedBox(width: 6),
                Text(trendSuffix, style: BannersTokens.captionSm),
              ],
            )
          else
            const SizedBox(height: 11),
        ],
      ),
    );
  }

  static Color _trendColor(double? pct) {
    if (pct == null || pct == 0) return BannersTokens.ink3;
    return pct > 0 ? BannersTokens.success : BannersTokens.danger;
  }

  static IconData _trendIcon(double? pct) {
    if (pct == null || pct == 0) return Icons.east_rounded;
    return pct > 0 ? Icons.north_east_rounded : Icons.south_east_rounded;
  }
}

/// Groups 4 [BannerMetricCard]s in a single flush strip with 1px
/// dividers between them — per the spec's "grouped with a single
/// outer border, 1px dividers inside".
class BannerMetricStrip extends StatelessWidget {
  const BannerMetricStrip({super.key, required this.cards})
      : assert(cards.length >= 1 && cards.length <= 6);

  final List<BannerMetricCard> cards;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      children.add(Expanded(child: cards[i]));
      if (i < cards.length - 1) {
        children.add(Container(width: 1, color: BannersTokens.line));
      }
    }
    return Container(
      decoration: BannersTokens.cardDecoration(radius: BannersTokens.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
