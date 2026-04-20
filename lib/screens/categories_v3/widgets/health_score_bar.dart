import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';

/// Progress-bar style health score per spec §7.6.
///
/// Layout: 50px wide track + 2-digit numeric label to the start side.
/// Color: red < 50, amber 50-74, green ≥ 75 (matches HealthBand thresholds).
class HealthScoreBar extends StatelessWidget {
  const HealthScoreBar({
    super.key,
    required this.score,
    this.barWidth = 50,
  });

  final int score;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final band = score >= 75
        ? HealthBand.good
        : score >= 50
            ? HealthBand.ok
            : HealthBand.bad;
    final color = band.color;
    final fillPct = (score.clamp(0, 100)) / 100.0;

    return Tooltip(
      message: 'ציון בריאות: $score / 100',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: barWidth,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: barWidth * fillPct,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
