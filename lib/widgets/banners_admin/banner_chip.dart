import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Variants of the admin-banner chip used on every banner row.
///
/// Maps 1-to-1 to [BannerStatus] + a generic `neutral` for category/
/// placement labels + `accent` for AI / provider_carousel highlights.
enum BannerChipVariant {
  success,  // active banners
  warn,     // scheduled banners
  neutral,  // placement labels, counts
  accent,   // AI insight / provider_carousel
  danger,   // expired / failed
  draft,    // draft state — muted, diagonal-stripe background elsewhere
}

/// A rounded pill / chip — ≤20px tall to match the spec's density.
///
/// Optional [hasDot] renders a small colored circle on the leading edge
/// (automatic RTL flip via [PositionedDirectional] + [Row]).
///
/// Use [BannerChipVariant.success] with `hasDot: true` for the pulsing
/// "● פעיל עכשיו" label — the pulse is the caller's responsibility
/// (wrap in a [AnimatedOpacity]).
class BannerChip extends StatelessWidget {
  const BannerChip({
    super.key,
    required this.label,
    this.variant = BannerChipVariant.neutral,
    this.hasDot = false,
    this.icon,
    this.dense = false,
  });

  final String label;
  final BannerChipVariant variant;
  final bool hasDot;
  final IconData? icon;

  /// When true: 16px tall instead of 20px — used in table rows for
  /// secondary metadata chips.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = _palette(variant);
    final h = dense ? 16.0 : 20.0;

    return Container(
      height: h,
      padding: EdgeInsetsDirectional.fromSTEB(
        hasDot ? 6 : 8,
        0,
        8,
        0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(BannersTokens.radiusPill),
        border: c.border == null ? null : Border.all(color: c.border!, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: c.fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 11, color: c.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              color: c.fg,
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  static _ChipPalette _palette(BannerChipVariant v) {
    switch (v) {
      case BannerChipVariant.success:
        return _ChipPalette(
          bg: BannersTokens.successWash,
          fg: BannersTokens.success,
        );
      case BannerChipVariant.warn:
        return _ChipPalette(
          bg: BannersTokens.warnWash,
          fg: BannersTokens.warn,
        );
      case BannerChipVariant.accent:
        return _ChipPalette(
          bg: BannersTokens.accentWash,
          fg: BannersTokens.accentInk,
        );
      case BannerChipVariant.danger:
        return _ChipPalette(
          bg: const Color(0xFFFBEAEA),
          fg: BannersTokens.danger,
        );
      case BannerChipVariant.draft:
        return _ChipPalette(
          bg: const Color(0xFFF4F4F5),
          fg: BannersTokens.ink3,
          border: BannersTokens.line2,
        );
      case BannerChipVariant.neutral:
        return _ChipPalette(
          bg: const Color(0xFFF4F4F5),
          fg: BannersTokens.ink2,
        );
    }
  }
}

class _ChipPalette {
  const _ChipPalette({required this.bg, required this.fg, this.border});
  final Color bg;
  final Color fg;
  final Color? border;
}
