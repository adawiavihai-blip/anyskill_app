import 'package:flutter/material.dart';

/// Reusable empty / error state used across the v3 tab. Matches the chip /
/// card aesthetic of the rest of the screen — soft grey card, centered
/// icon, primary line + secondary line, optional CTA.
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.tone = EmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final EmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final accent = switch (tone) {
      EmptyTone.neutral => const Color(0xFF6B7280),
      EmptyTone.warning => const Color(0xFFF59E0B),
      EmptyTone.danger => const Color(0xFFEF4444),
      EmptyTone.success => const Color(0xFF10B981),
    };
    final bg = accent.withValues(alpha: 0.08);

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onCta,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(ctaLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: accent,
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum EmptyTone { neutral, warning, danger, success }
