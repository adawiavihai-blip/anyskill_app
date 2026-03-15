import 'dart:math';
import 'package:flutter/material.dart';

/// Displays a full-screen confetti burst as an Overlay entry.
/// Automatically removes itself after the animation finishes.
///
/// Usage:
///   VipConfetti.show(context);
class VipConfetti {
  static void show(BuildContext context) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _VipConfettiWidget(onDone: () {
        if (entry.mounted) entry.remove();
      }),
    );
    Overlay.of(context).insert(entry);
  }
}

// ── Internal animated widget ────────────────────────────────────────────────

class _VipConfettiWidget extends StatefulWidget {
  final VoidCallback onDone;
  const _VipConfettiWidget({required this.onDone});

  @override
  State<_VipConfettiWidget> createState() => _VipConfettiWidgetState();
}

class _VipConfettiWidgetState extends State<_VipConfettiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  static const _kDuration = Duration(milliseconds: 3200);

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _particles = List.generate(90, (_) => _Particle(rng));
    _ctrl = AnimationController(vsync: this, duration: _kDuration)
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _ConfettiPainter(_particles, _ctrl.value),
        ),
      ),
    );
  }
}

// ── Particle model ──────────────────────────────────────────────────────────

class _Particle {
  final double startX;   // 0..1 fraction of screen width
  final double startY;   // starts slightly above the screen
  final double vx;       // horizontal drift (fraction/s)
  final double vy;       // downward velocity (fraction/s)
  final double rotation; // initial rotation radians
  final double spin;     // radians to rotate per t unit
  final Color color;
  final double w;        // width px
  final double h;        // height px
  final bool isCircle;

  static const _kColors = [
    Color(0xFFFFC300), // gold
    Color(0xFFFF6B6B), // coral
    Color(0xFF4ECDC4), // teal
    Color(0xFF45B7D1), // sky
    Color(0xFFFF9FF3), // pink
    Color(0xFFFFEAA7), // light yellow
    Color(0xFFDDA0DD), // plum
    Color(0xFF6EE7B7), // mint
    Color(0xFFFB923C), // orange
    Color(0xFFA78BFA), // violet
  ];

  _Particle(Random rng)
      : startX = rng.nextDouble(),
        startY = -(rng.nextDouble() * 0.25) - 0.05,
        vx = (rng.nextDouble() - 0.5) * 0.35,
        vy = rng.nextDouble() * 0.7 + 0.35,
        rotation = rng.nextDouble() * 2 * pi,
        spin = (rng.nextDouble() - 0.5) * 12,
        w = rng.nextDouble() * 9 + 5,
        h = rng.nextDouble() * 5 + 3,
        isCircle = rng.nextBool() && rng.nextBool(),
        color = _kColors[rng.nextInt(_kColors.length)];
}

// ── CustomPainter ───────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t; // 0..1

  const _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      // Fade out in the last 30% of the animation
      final opacity = t < 0.7 ? 1.0 : ((1.0 - t) / 0.3).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      paint.color = p.color.withValues(alpha: opacity);

      final x = (p.startX + p.vx * t) * size.width;
      // slight gravity acceleration: y = vy*t + 0.3*t^2
      final y = (p.startY + p.vy * t + 0.3 * t * t) * size.height;

      if (y > size.height + 20) continue; // already off-screen

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + p.spin * t);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.w * 0.5, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: p.w, height: p.h),
          paint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
