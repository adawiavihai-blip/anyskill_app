import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Animated 160px circular capacity ring used in the VIP hero
/// ([banners-mockup-v3.html:462-469](docs/ui-specs/Baner/banners-mockup-v3.html)).
///
/// Shows current/max as a gold gradient stroke arc on a faint gold
/// track. Counts up smoothly from 0 → [current] on first mount.
class StudioCapacityRing extends StatefulWidget {
  const StudioCapacityRing({
    super.key,
    required this.current,
    required this.max,
    this.size = 160,
    this.strokeWidth = 10,
  });

  final int current;
  final int max;
  final double size;
  final double strokeWidth;

  @override
  State<StudioCapacityRing> createState() => _StudioCapacityRingState();
}

class _StudioCapacityRingState extends State<StudioCapacityRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _anim = Tween<double>(begin: 0, end: _fraction).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  double get _fraction {
    if (widget.max <= 0) return 0;
    return (widget.current / widget.max).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant StudioCapacityRing old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current || old.max != widget.max) {
      _anim = Tween<double>(begin: _anim.value, end: _fraction).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.max - widget.current).clamp(0, widget.max);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingPainter(
                fraction: _anim.value,
                strokeWidth: widget.strokeWidth,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.current}',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'מתוך ${widget.max}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remaining > 0 ? 'נותרו $remaining' : 'מלא',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.strokeWidth});
  final double fraction;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    if (radius <= 0) return;

    // Track
    final track = Paint()
      ..color = StudioColors.gold.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    // Fill arc — start at top, sweep clockwise.
    if (fraction <= 0) return;
    final fill = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFB89855),
          Color(0xFF8C6F36),
          Color(0xFFB89855),
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at 12 o'clock
      2 * math.pi * fraction, // sweep clockwise
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

/// Horizontal capacity bar — alternative compact view shown under the
/// VIP hero ([banners-mockup-v3.html:546-549](docs/ui-specs/Baner/banners-mockup-v3.html)).
///
/// Three coloured segments: paying (gold) / admin-comp (black) / free (grey).
class StudioCapacityBar extends StatelessWidget {
  const StudioCapacityBar({
    super.key,
    required this.paying,
    required this.adminComp,
    required this.max,
  });

  final int paying;
  final int adminComp;
  final int max;

  int get _free {
    final f = max - paying - adminComp;
    return f < 0 ? 0 : f;
  }

  @override
  Widget build(BuildContext context) {
    final total = paying + adminComp + _free;
    if (total == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: StudioColors.bgSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 18, vertical: 14),
      decoration: studioCard(radius: StudioRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _LegendChip(
                  color: StudioColors.gold, label: 'משלמים'),
              const SizedBox(width: 14),
              const _LegendChip(
                  color: StudioColors.ink, label: 'חינם · מנהל'),
              const SizedBox(width: 14),
              const _LegendChip(
                  color: StudioColors.bgTonal, label: 'פנויים'),
              const Spacer(),
              Text(
                '$paying · $adminComp · $_free',
                style: StudioText.bodyMedium(),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (paying > 0)
                    Expanded(
                      flex: paying,
                      child: const ColoredBox(color: StudioColors.gold),
                    ),
                  if (adminComp > 0)
                    Expanded(
                      flex: adminComp,
                      child: const ColoredBox(color: StudioColors.ink),
                    ),
                  if (_free > 0)
                    Expanded(
                      flex: _free,
                      child: const ColoredBox(color: StudioColors.bgTonal),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: StudioText.captionSm(),
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }
}
