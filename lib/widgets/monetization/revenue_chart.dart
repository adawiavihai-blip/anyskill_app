import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// A single series for the revenue chart.
class RevenueSeries {
  final String label;
  final List<double> points; // one value per day (0 = first day of month)
  final Color color;
  final bool dashed;
  final double fillAlpha;
  final bool isProjection;

  const RevenueSeries({
    required this.label,
    required this.points,
    required this.color,
    this.dashed = false,
    this.fillAlpha = 0.0,
    this.isProjection = false,
  });
}

/// Section 6 (left) — line chart comparing this month vs previous month vs
/// projection. Pure-Dart CustomPainter for Stage 2 — swap to fl_chart later
/// if we need interactivity (tap-to-inspect, scrubbing, etc.).
class RevenueChart extends StatelessWidget {
  const RevenueChart({
    super.key,
    required this.series,
    this.height = 180,
    this.peakLabel,
  });

  final List<RevenueSeries> series;
  final double height;
  final String? peakLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _RevenueChartPainter(series: series),
          ),
        ),
        const SizedBox(height: 10),
        // Legend
        Wrap(
          spacing: 14,
          children: series
              .map((s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 2,
                        color: s.color,
                      ),
                      const SizedBox(width: 4),
                      Text(s.label,
                          style: const TextStyle(
                              fontSize: 11,
                              color: MonetizationTokens.textSecondary)),
                    ],
                  ))
              .toList(),
        ),
        if (peakLabel != null) ...[
          const SizedBox(height: 4),
          Text(peakLabel!, style: MonetizationTokens.micro),
        ],
      ],
    );
  }
}

class _RevenueChartPainter extends CustomPainter {
  _RevenueChartPainter({required this.series});
  final List<RevenueSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    // ── Compute bounds
    double maxV = 0;
    int maxLen = 0;
    for (final s in series) {
      for (final v in s.points) {
        if (v > maxV) maxV = v;
      }
      if (s.points.length > maxLen) maxLen = s.points.length;
    }
    if (maxV == 0 || maxLen == 0) return;

    // ── Horizontal gridlines (light)
    final gridPaint = Paint()
      ..color = MonetizationTokens.borderSoft
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 3; i++) {
      final dy = size.height * i / 4;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    // ── Each series
    for (final s in series) {
      if (s.points.isEmpty) continue;
      final path = Path();
      final fillPath = Path();
      for (int i = 0; i < s.points.length; i++) {
        final dx = size.width * (i / (maxLen - 1).clamp(1, 999));
        final dy = size.height -
            (s.points[i] / maxV) * size.height * 0.95 -
            (size.height * 0.025);
        if (i == 0) {
          path.moveTo(dx, dy);
          fillPath.moveTo(dx, size.height);
          fillPath.lineTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
          fillPath.lineTo(dx, dy);
        }
      }
      fillPath.lineTo(
          size.width * (s.points.length - 1) / (maxLen - 1).clamp(1, 999),
          size.height);
      fillPath.close();

      if (s.fillAlpha > 0) {
        canvas.drawPath(
          fillPath,
          Paint()..color = s.color.withValues(alpha: s.fillAlpha),
        );
      }

      final strokePaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round;

      if (s.dashed) {
        _drawDashed(canvas, path, strokePaint);
      } else {
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, next.toDouble()),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueChartPainter oldDelegate) =>
      oldDelegate.series != series;
}
