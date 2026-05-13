import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Miniature line chart for KPIs + table rows.
///
/// Handles all three degenerate inputs safely:
///  - 0 values   → renders an empty [SizedBox] at the requested size
///  - 1 value    → renders a single dot at the center-right
///  - 2+ values  → renders a smoothed polyline left-to-right
///
/// The stroke width grows from 1.2px → 2px when [isHovered] is true
/// per the spec's "sparkline thickens on row hover" micro-interaction.
///
/// Scoped to the admin banners tab — prefixed `Banner*` to avoid
/// collision with the existing [Sparkline] in
/// [lib/widgets/monetization/kpi_card.dart] (§31 of CLAUDE.md).
class BannerSparkline extends StatelessWidget {
  const BannerSparkline({
    super.key,
    required this.values,
    this.color = BannersTokens.ink3,
    this.width = 72,
    this.height = 22,
    this.isHovered = false,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: BannersTokens.hoverDuration,
      width: width,
      height: height,
      child: CustomPaint(
        painter: _BannerSparklinePainter(
          values: values,
          color: color,
          strokeWidth: isHovered ? 2.0 : 1.2,
        ),
        size: Size(width, height),
      ),
    );
  }
}

class _BannerSparklinePainter extends CustomPainter {
  _BannerSparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    if (values.length == 1) {
      // Single dot at center.
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width - 2, size.height / 2),
        strokeWidth * 1.4,
        paint,
      );
      return;
    }

    // 2+ points → polyline.
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);
    final stepX = size.width / (values.length - 1);

    // Inset a bit so the stroke doesn't clip on top/bottom edges.
    final padY = strokeWidth / 2 + 1;
    final innerH = size.height - padY * 2;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normY = 1 - ((values[i] - minV) / range); // flip: high = top
      final y = padY + normY * innerH;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BannerSparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
