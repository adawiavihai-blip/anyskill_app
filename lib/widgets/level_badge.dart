import 'package:flutter/material.dart';
import '../services/gamification_service.dart';

/// Compact Bronze / Silver / Gold gradient badge.
/// Pass [xp] and optionally [size] (default 22 logical pixels tall).
class LevelBadge extends StatelessWidget {
  final int xp;
  final double size;

  const LevelBadge({super.key, required this.xp, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final level  = GamificationService.levelFor(xp);
    final colors = GamificationService.levelGradient(level);

    final emoji = switch (level) {
      ProviderLevel.gold   => '🥇',
      ProviderLevel.silver => '🥈',
      ProviderLevel.bronze => '🥉',
    };
    final name = GamificationService.levelName(level);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.32, vertical: size * 0.14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: size * 0.52)),
          SizedBox(width: size * 0.15),
          Text(
            name,
            style: TextStyle(
              fontSize: size * 0.48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
