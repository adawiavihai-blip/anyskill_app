import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';

/// Single-line inline conversion funnel rendered under the category name
/// (spec §7.3 row 2): "12.4K צפיות → 3.2K קליקים → 284 הזמנות".
///
/// Per Q4-B+C decision, `views_30d` and `clicks_30d` are NULL until tracking
/// infra ships. We render "—" placeholders for those steps and keep the
/// orders count real.
class ConversionFunnelInline extends StatelessWidget {
  const ConversionFunnelInline({super.key, required this.analytics});

  final CategoryAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final views = analytics?.views30d;
    final clicks = analytics?.clicks30d;
    final orders = analytics?.orders30d ?? 0;
    final revenue = analytics?.revenue30d ?? 0;
    final providers = analytics?.activeProviders ?? 0;
    final growth = analytics?.growth30d ?? 0;

    final parts = <_FunnelPart>[
      _FunnelPart(
        label: views == null ? '—' : _fmtCompact(views),
        suffix: 'צפיות',
        color: const Color(0xFF9CA3AF),
      ),
      _FunnelPart(
        label: clicks == null ? '—' : _fmtCompact(clicks),
        suffix: 'קליקים',
        color: const Color(0xFF9CA3AF),
      ),
      _FunnelPart(
        label: '$orders',
        suffix: 'הזמנות',
        color: const Color(0xFF1A1A2E),
      ),
    ];

    return DefaultTextStyle(
      style: const TextStyle(
        fontSize: 11.5,
        color: Color(0xFF6B7280),
        height: 1.3,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            _FunnelStep(part: parts[i]),
            if (i < parts.length - 1) const _FunnelArrow(),
          ],
          const _Bullet(),
          if (providers > 0)
            Text('$providers ספקים', style: const TextStyle(color: Color(0xFF6B7280))),
          if (revenue > 0) ...[
            const _Bullet(),
            Text('₪${_fmtCompact(revenue.round())}',
                style: const TextStyle(
                    color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600)),
          ],
          if (growth != 0) ...[
            const _Bullet(),
            _GrowthIndicator(percent: growth),
          ],
        ],
      ),
    );
  }

  static String _fmtCompact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}

class _FunnelPart {
  const _FunnelPart({required this.label, required this.suffix, required this.color});
  final String label;
  final String suffix;
  final Color color;
}

class _FunnelStep extends StatelessWidget {
  const _FunnelStep({required this.part});
  final _FunnelPart part;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          part.label,
          style: TextStyle(fontWeight: FontWeight.w600, color: part.color),
        ),
        const SizedBox(width: 3),
        Text(part.suffix, style: const TextStyle(color: Color(0xFF6B7280))),
      ],
    );
  }
}

class _FunnelArrow extends StatelessWidget {
  const _FunnelArrow();
  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.east_rounded, size: 11, color: Color(0xFFC0C7D2));
}

class _Bullet extends StatelessWidget {
  const _Bullet();
  @override
  Widget build(BuildContext context) =>
      const Text('·', style: TextStyle(color: Color(0xFFC0C7D2)));
}

class _GrowthIndicator extends StatelessWidget {
  const _GrowthIndicator({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) {
    final positive = percent >= 0;
    final color = positive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = positive ? '▲' : '▼';
    return Text(
      '$sign ${percent.abs().toStringAsFixed(0)}%',
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
