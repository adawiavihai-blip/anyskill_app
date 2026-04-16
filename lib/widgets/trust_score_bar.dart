import 'package:flutter/material.dart';

/// Phase 2 / Phase 5 — visual Trust Score (0-100) for a customer or
/// provider. The score itself is computed by the recalculateTrustScore
/// Cloud Function (Phase 5) and stored on `users/{uid}.trustScore`.
/// Until that CF ships, this widget gracefully handles missing scores
/// and falls back to a "no data" hint.
///
/// Color bands:
///   • 70-100 — green   (trusted)
///   • 40-69  — amber   (caution)
///   • 0-39   — red     (high risk)
class TrustScoreBar extends StatelessWidget {
  /// Raw trust score from Firestore. If null, renders a "no data" stub.
  final num? score;

  /// Compact mode renders just the pill — used in dense rows. Default
  /// renders pill + progress bar + label.
  final bool compact;

  /// Optional title shown above the bar (e.g. "אמינות לקוח").
  final String? title;

  const TrustScoreBar({
    super.key,
    required this.score,
    this.compact = false,
    this.title,
  });

  Color get _color {
    final s = score?.toDouble();
    if (s == null) return const Color(0xFF9CA3AF);
    if (s >= 70) return const Color(0xFF10B981);
    if (s >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String get _label {
    final s = score?.toDouble();
    if (s == null) return '—';
    if (s >= 70) return 'גבוה';
    if (s >= 40) return 'בינוני';
    return 'נמוך';
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    final s = score?.toDouble();
    final pct = s == null ? 0.0 : (s.clamp(0, 100) / 100.0);
    final scoreText = s == null ? '—' : s.round().toString();

    if (compact) {
      return Tooltip(
        message: 'Trust Score: $scoreText / 100 ($_label)',
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded, size: 12, color: c),
              const SizedBox(width: 4),
              Text(
                scoreText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_rounded, size: 14, color: c),
            const SizedBox(width: 6),
            Text(
              title ?? 'Trust Score',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
              ),
            ),
            const Spacer(),
            Text(
              '$scoreText / 100',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: c,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '·',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(width: 6),
            Text(
              _label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: const Color(0xFFF3F4F6),
            valueColor: AlwaysStoppedAnimation<Color>(c),
          ),
        ),
        if (s == null) ...[
          const SizedBox(height: 4),
          Text(
            'אין מספיק נתונים לחישוב',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }
}
