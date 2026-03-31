/// AnySkill — Level Up Celebration Overlay
///
/// Full-screen overlay with:
///   - Scale-in animation of new level badge
///   - Confetti particle burst
///   - Sound effect hook (caller can trigger AudioService)
///   - Auto-dismiss after 3 seconds or tap
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../services/gamification_service.dart';

/// Shows a full-screen celebration overlay.
/// Call this when [EngagementService.didLevelUp] returns true.
Future<void> showLevelUpCelebration(BuildContext context, int newXp) {
  final level = GamificationService.levelFor(newXp);
  final levelName = GamificationService.levelName(level);
  final gradient = GamificationService.levelGradient(level);

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => _CelebrationOverlay(
      levelName: levelName,
      gradient: gradient,
      xp: newXp,
    ),
  );
}

class _CelebrationOverlay extends StatefulWidget {
  final String levelName;
  final List<Color> gradient;
  final int xp;

  const _CelebrationOverlay({
    required this.levelName,
    required this.gradient,
    required this.xp,
  });

  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    // Generate confetti particles
    final rng = Random();
    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(),
        speed: 0.3 + rng.nextDouble() * 0.7,
        size: 4 + rng.nextDouble() * 8,
        color: [
          const Color(0xFF6366F1),
          const Color(0xFFF59E0B),
          const Color(0xFF10B981),
          const Color(0xFFEC4899),
          const Color(0xFF8B5CF6),
        ][rng.nextInt(5)],
        angle: rng.nextDouble() * pi * 2,
      ));
    }

    _ctrl.forward();

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Stack(
          children: [
            // ── Confetti particles ────────────────────────────────────────
            for (final p in _particles)
              Positioned(
                left: MediaQuery.of(context).size.width * p.x,
                top: MediaQuery.of(context).size.height *
                    (0.3 - _ctrl.value * p.speed),
                child: Transform.rotate(
                  angle: p.angle + _ctrl.value * pi,
                  child: Opacity(
                    opacity: (1 - _ctrl.value).clamp(0.3, 1.0),
                    child: Container(
                      width: p.size,
                      height: p.size * 1.5,
                      decoration: BoxDecoration(
                        color: p.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Central badge ────────────────────────────────────────────
            Center(
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Level-up text
                      const Text(
                        '🎊 עלית רמה! 🎊',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                                blurRadius: 12,
                                color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Level badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: widget.gradient,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: widget.gradient.last
                                  .withValues(alpha: 0.5),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              widget.levelName,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${widget.xp} XP',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'הקש לסגירה',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Particle {
  final double x;
  final double speed;
  final double size;
  final Color color;
  final double angle;
  const _Particle({
    required this.x,
    required this.speed,
    required this.size,
    required this.color,
    required this.angle,
  });
}
