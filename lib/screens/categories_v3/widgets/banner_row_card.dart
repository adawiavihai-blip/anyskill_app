import 'package:flutter/material.dart';

import '../models/promoted_banner.dart';

/// Promoted banner row — read-only mirror of AnyTasks + נתינה מהלב per Q5-A.
///
/// Phase B renders the cached `promoted_banners` doc (if present) OR a
/// hardcoded mock that mirrors the live home_tab values. Either way, edits
/// here do NOT yet affect the customer screen — that migration ships in a
/// later phase.
class BannerRowCard extends StatelessWidget {
  const BannerRowCard({super.key, required this.banner, this.onTap});

  final PromotedBanner banner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final start = _hex(banner.gradientStart, const Color(0xFF6366F1));
    final end = _hex(banner.gradientEnd, const Color(0xFF8B5CF6));

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [start, end],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: start.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon (emoji or 1st char)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    banner.icon.isNotEmpty
                        ? banner.icon.characters.first
                        : '★',
                    style: const TextStyle(
                      fontSize: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            banner.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const _MirrorChip(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        banner.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                if (banner.ctaLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      banner.ctaLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _hex(String hex, Color fallback) {
    final clean = hex.replaceFirst('#', '');
    final parsed = int.tryParse(clean, radix: 16);
    if (parsed == null) return fallback;
    if (clean.length == 6) return Color(0xFF000000 | parsed);
    if (clean.length == 8) return Color(parsed);
    return fallback;
  }
}

/// Tiny "Mirror" badge clarifying that editing here doesn't yet flow to the
/// home screen (Q5-A — Phase A-B is a read-only mirror).
class _MirrorChip extends StatelessWidget {
  const _MirrorChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 9, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'תצוגה',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
