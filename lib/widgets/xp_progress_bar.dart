import 'package:flutter/material.dart';

/// Reusable animated gradient XP progress bar.
///
/// Shows the user's current level badge, raw XP, "XP to next level" label,
/// and a gradient bar that animates from 0 → current fill on first paint.
///
/// Formula:  level = (xp ~/ 500) + 1
///           progress = (xp % 500) / 500.0
class XpProgressBar extends StatelessWidget {
  final int  xp;
  final bool darkMode;    // true = white text (Academy dark BG), false = dark text (Profile white BG)

  const XpProgressBar({
    super.key,
    required this.xp,
    this.darkMode = false,
  });

  // ── Public helpers (reusable by other widgets) ─────────────────────────────

  static int    levelFromXp(int xp)    => (xp ~/ 500) + 1;
  static double progressFromXp(int xp) => (xp % 500) / 500.0;
  static int    xpToNextLevel(int xp)  => 500 - (xp % 500);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final level   = levelFromXp(xp);
    final toNext  = xpToNextLevel(xp);
    final progress = progressFromXp(xp);

    final labelColor = darkMode
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.grey[500]!;
    final xpColor = darkMode ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Top row: level badge + XP + "to next level" ─────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'רמה $level',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$xp XP',
                  style: TextStyle(
                    color: xpColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Text(
              'עוד $toNext XP לרמה ${level + 1}',
              style: TextStyle(color: labelColor, fontSize: 11),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── Animated gradient bar ────────────────────────────────────────────
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: progress),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  // Track
                  Container(
                    height: 10,
                    width: double.infinity,
                    color: darkMode
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.grey.shade200,
                  ),
                  // Fill
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF6366F1),
                            Color(0xFFA855F7),
                            Color(0xFFEC4899),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
