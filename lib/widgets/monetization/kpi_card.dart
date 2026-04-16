import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// A single KPI card used in section 3 of the Monetization tab.
/// Layout (top→bottom): label row + pill · big value · visual · footnote.
///
/// Stage 2 — structure and styling are final; real data wiring lands in
/// stage 3.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    this.pill,
    this.pillBackground,
    this.pillForeground,
    this.deltaText,
    this.deltaColor,
    this.footnote,
    this.visual,
  });

  final String label;
  final String value;
  final String? suffix;
  final String? pill;
  final Color? pillBackground;
  final Color? pillForeground;
  final String? deltaText;
  final Color? deltaColor;
  final String? footnote;
  final Widget? visual;

  @override
  Widget build(BuildContext context) {
    return MonetizationCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label + pill row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: MonetizationTokens.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pill != null && pillBackground != null && pillForeground != null)
                MonetizationPill(
                  label: pill!,
                  background: pillBackground!,
                  foreground: pillForeground!,
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Value + optional suffix / delta
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: MonetizationTokens.textPrimary,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Text(
                  suffix!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MonetizationTokens.textTertiary,
                  ),
                ),
              ],
              if (deltaText != null) ...[
                const SizedBox(width: 6),
                Text(
                  deltaText!,
                  style: TextStyle(
                    fontSize: 11,
                    color: deltaColor ?? MonetizationTokens.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          if (visual != null) ...[
            const SizedBox(height: 8),
            visual!,
          ],
          if (footnote != null) ...[
            const SizedBox(height: 2),
            Text(footnote!, style: MonetizationTokens.micro),
          ],
        ],
      ),
    );
  }
}

/// Sparkline widget used inside `KpiCard.visual`. Pure Dart — no fl_chart
/// dependency yet (keeps Stage 2 lightweight).
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = MonetizationTokens.success,
    this.fillAlpha = 0.1,
    this.height = 20,
  });

  final List<double> values;
  final Color color;
  final double fillAlpha;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparklinePainter(
          values: values,
          color: color,
          fillAlpha: fillAlpha,
        ),
      ),
    );
  }
}

/// Escrow wait-time bars. Each bar represents one in-escrow job; opacity
/// grows with wait time (longer wait = more saturated amber).
class EscrowWaitBars extends StatelessWidget {
  const EscrowWaitBars({
    super.key,
    required this.waits,
    this.height = 20,
    this.maxBars = 6,
  });

  final List<Duration> waits;
  final double height;
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    if (waits.isEmpty) {
      return SizedBox(
        height: height,
        child: Container(
          decoration: BoxDecoration(
            color: MonetizationTokens.surfaceAlt,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: const Text('—', style: MonetizationTokens.micro),
        ),
      );
    }
    // Sort newest first and trim to maxBars.
    final sorted = [...waits]..sort((a, b) => a.compareTo(b));
    final bars = sorted.take(maxBars).toList();
    final maxH = bars.last.inMinutes.toDouble().clamp(1, double.infinity);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < bars.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: MonetizationTokens.warningVivid.withValues(
                    alpha: (0.25 + (bars[i].inMinutes / maxH) * 0.75)
                        .clamp(0.25, 1.0),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal progress bar representing current pct vs target pct.
/// Target is shown as a vertical tick mark.
class FeeTargetBar extends StatelessWidget {
  const FeeTargetBar({
    super.key,
    required this.current,
    required this.target,
    this.max = 20,
    this.color = MonetizationTokens.primary,
  });

  final double current;
  final double target;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = (current / max).clamp(0.0, 1.0);
    final tickAt = (target / max).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 4,
          decoration: BoxDecoration(
            color: MonetizationTokens.surfaceAlt,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            children: [
              // Fill (RTL — from trailing edge)
              PositionedDirectional(
                top: 0,
                bottom: 0,
                start: 0,
                width: constraints.maxWidth * fill,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Target tick
              PositionedDirectional(
                start: constraints.maxWidth * tickAt - 1,
                top: -2,
                child: Container(
                  width: 2,
                  height: 8,
                  color: MonetizationTokens.primaryDarker,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mini bar chart — top-N custom-commission provider revenues.
class CustomProviderBars extends StatelessWidget {
  const CustomProviderBars({
    super.key,
    required this.values,
    this.height = 20,
  });

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Container(
          decoration: BoxDecoration(
            color: MonetizationTokens.surfaceAlt,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.center,
          child: const Text('אין נתונים',
              style: MonetizationTokens.micro),
        ),
      );
    }
    final maxV = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Container(
                height: (values[i] / maxV * height).clamp(2, height),
                decoration: BoxDecoration(
                  color: i < 3
                      ? MonetizationTokens.churn
                      : MonetizationTokens.churnSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.fillAlpha,
  });

  final List<double> values;
  final Color color;
  final double fillAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < values.length; i++) {
      final dx = size.width * (i / (values.length - 1).clamp(1, 999));
      final dy = size.height - ((values[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(dx, dy);
        fillPath.moveTo(dx, size.height);
        fillPath.lineTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
        fillPath.lineTo(dx, dy);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()..color = color.withValues(alpha: fillAlpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.fillAlpha != fillAlpha;
}
