import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// One of the 4 cards in the KPI strip at the top of Screen A.
///
/// Mockup spec ([banners-mockup-v3.html:137-148, 853-893](docs/ui-specs/Baner/banners-mockup-v3.html)):
/// - 14px radius, 20px padding, white surface, 1px line border
/// - radial-gradient halo top-right (achieved here with `_HaloPainter`)
/// - on hover: -2px translate + sh3 shadow (web only — no-op on mobile)
/// - 4 stacked rows: small uppercase label, big metric (Assistant 32 w600
///   tabular), foot row with delta pill + sparkline
///
/// **"Don't fake metrics" rule (CLAUDE.md §49 + Plan agent):** if the
/// underlying value is unknown (no aggregation infra yet), the screen
/// passes `valueText: '—'` and the card renders the dash honestly. The
/// card never invents data.
class StudioKpiCard extends StatefulWidget {
  const StudioKpiCard({
    super.key,
    required this.label,
    required this.valueText,
    this.deltaPercent,
    this.sparkline = const [],
    this.accent = false,
  });

  /// Small uppercase label — e.g. "חשיפות (7 ימים)".
  final String label;

  /// Large rendered value — e.g. "284,591" or "₪22,770" or "—".
  final String valueText;

  /// Positive = up (green), negative = down (red), null = no delta pill.
  /// Phase 1 always passes null (no daily aggregation yet).
  final double? deltaPercent;

  /// Optional 0..n points for the trailing sparkline. Empty = no sparkline.
  /// Phase 1 always passes empty (no historical data yet).
  final List<double> sparkline;

  /// Renders the value in gold — used for the "VIP revenue" KPI.
  final bool accent;

  @override
  State<StudioKpiCard> createState() => _StudioKpiCardState();
}

class _StudioKpiCardState extends State<StudioKpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hasDelta = widget.deltaPercent != null;
    final isUp = (widget.deltaPercent ?? 0) >= 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: _hover
            ? Matrix4.translationValues(0, -2, 0)
            : Matrix4.identity(),
        decoration: studioCard(
          radius: StudioRadius.md,
          shadow: _hover ? StudioShadows.sh3 : StudioShadows.sh1,
        ),
        padding: const EdgeInsets.all(StudioSpacing.s5),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Soft halo top-end corner (matches mockup .kpi::before).
            const Positioned.fill(child: _HaloPaint()),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label.toUpperCase(),
                  style: StudioText.overline(),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: StudioSpacing.s3),
                Text(
                  widget.valueText,
                  style: StudioText.metricLarge(
                    color: widget.accent ? StudioColors.gold : StudioColors.ink,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: StudioSpacing.s3),
                Row(
                  children: [
                    if (hasDelta) ...[
                      _DeltaPill(percent: widget.deltaPercent!, isUp: isUp),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    if (widget.sparkline.isNotEmpty)
                      SizedBox(
                        height: 22,
                        width: 80,
                        child: CustomPaint(
                          painter: _SparkPainter(
                            values: widget.sparkline,
                            color: widget.accent
                                ? StudioColors.gold
                                : (isUp
                                    ? StudioColors.success
                                    : StudioColors.danger),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.percent, required this.isUp});
  final double percent;
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: StudioSpacing.s2, vertical: 2),
      decoration: BoxDecoration(
        color: isUp ? StudioColors.successBg : StudioColors.dangerBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${isUp ? '↑' : '↓'} ${percent.abs().toStringAsFixed(1)}%',
        style: StudioText.chip(
          color: isUp ? StudioColors.success : StudioColors.danger,
        ),
      ),
    );
  }
}

class _HaloPaint extends StatelessWidget {
  const _HaloPaint();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HaloPainter(),
      size: Size.infinite,
    );
  }
}

class _HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Guard: degenerate sizes during initial layout. Without it, Skia
    // can throw on web (manifests as "Cannot read properties of null").
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width, 0);
    final paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x0F1A1A1A), Color(0x001A1A1A)],
      ).createShader(Rect.fromCircle(center: center, radius: 80));
    canvas.drawCircle(center, 80, paint);
  }

  @override
  bool shouldRepaint(covariant _HaloPainter oldDelegate) => false;
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : maxV - minV;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final yNorm = (values[i] - minV) / range;
      final y = size.height - (yNorm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
