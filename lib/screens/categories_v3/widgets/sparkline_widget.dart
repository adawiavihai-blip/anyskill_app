import 'package:flutter/material.dart';

/// 60×28 mini line-chart of the last 30 daily counts (spec §7.5).
///
/// Visual:
///   - Smooth curve via Catmull-Rom interpolation between points
///   - Stroke + 8% fill — green when growth ≥ 0, red when growth < 0
///   - Flat baseline shown when data is all-zeros (defensive default)
///
/// Performance: `shouldRepaint` returns false unless the data identity
/// changes. CategoryRowCard wraps this in a `RepaintBoundary` so a parent
/// rebuild doesn't repaint the painter.
class SparklineWidget extends StatelessWidget {
  const SparklineWidget({
    super.key,
    required this.points,
    required this.growthPercent,
    this.width = 60,
    this.height = 28,
  });

  /// 30 daily counts (oldest → newest). Caller pads to length 30.
  final List<int> points;

  /// % change vs prior period — drives the color band.
  final double growthPercent;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Defensive: empty points → flat hairline placeholder.
    final safePoints = points.isEmpty ? const <int>[0] : points;
    final isFlat = safePoints.every((p) => p == 0);
    // growthPercent might be NaN/Infinity from a /0 upstream; treat as 0.
    final safeGrowth = growthPercent.isFinite ? growthPercent : 0.0;
    final color = isFlat
        ? const Color(0xFF9CA3AF)
        : (safeGrowth >= 0
            ? const Color(0xFF10B981)
            : const Color(0xFFEF4444));
    return RepaintBoundary(
      child: Tooltip(
        message: _tooltipText(safePoints, safeGrowth),
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _SparklinePainter(
              points: safePoints,
              color: color,
              isFlat: isFlat,
            ),
          ),
        ),
      ),
    );
  }

  String _tooltipText(List<int> pts, double g) {
    try {
      final total = pts.fold<int>(0, (s, v) => s + v);
      final sign = g >= 0 ? '+' : '';
      return '$total בשבוע (30 ימים) · $sign${g.toStringAsFixed(0)}%';
    } catch (_) {
      return 'אין נתונים';
    }
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.color,
    required this.isFlat,
  });

  final List<int> points;
  final Color color;
  final bool isFlat;

  @override
  void paint(Canvas canvas, Size size) {
    // Defense layer #1: never paint into a zero-sized canvas — the smooth
    // path math involves division by size.width which would NaN out.
    if (size.width <= 0 || size.height <= 0) return;

    // Defense layer #2: catch any unexpected math/range error from the
    // smooth-path computation. A failed paint surfaces as a paint error
    // in Flutter's renderer, which on web shows as a blank/grey frame.
    try {
      _paintInner(canvas, size);
    } catch (e) {
      // Last-resort fallback: a single grey hairline across the middle.
      final paint = Paint()
        ..color = const Color(0xFF9CA3AF).withValues(alpha: 0.4)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintInner(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    if (isFlat) {
      // Single horizontal hairline through the middle
      final paint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    // maxVal: protect against negative-only inputs (clamp to 1 minimum).
    final reducedMax = points.reduce((a, b) => a > b ? a : b).toDouble();
    final maxVal = reducedMax > 1 ? reducedMax : 1.0;

    // stepX: protect against single-point input (would be infinite).
    final divisor = points.length > 1 ? (points.length - 1) : 1;
    final stepX = size.width / divisor;

    final pts = <Offset>[
      for (var i = 0; i < points.length; i++)
        Offset(
          i * stepX,
          size.height - (points[i] / maxVal) * (size.height - 4) - 2,
        ),
    ];

    if (pts.isEmpty) return;

    // Build a smooth path via Catmull-Rom → cubic Bezier conversion
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    // Fill path (closed at the bottom)
    final fillPath = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()..color = color.withValues(alpha: 0.08),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      !identical(oldDelegate.points, points) || oldDelegate.color != color;
}
