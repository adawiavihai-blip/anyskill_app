import 'package:flutter/material.dart';

/// Design tokens for the v15.x Monetization tab.
///
/// Extracted **directly from the mockup** (`docs/ui-specs/monetization/
/// monetization_mockup.html`). Spec says: "HTML wins over text" — so every
/// value here is a hex I read from the mockup, not a guess.
///
/// Scoped to the monetization tab only — does NOT replace the global
/// `Brand.*` palette from `lib/theme/app_theme.dart` (same pattern used by
/// `MapPalette` in Section 26 of CLAUDE.md).
class MonetizationTokens {
  MonetizationTokens._();

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const scaffold    = Color(0xFFFAF9F6);
  static const surface     = Colors.white;
  static const surfaceAlt  = Color(0xFFF7F5F0);
  static const surfaceDark = Color(0xFF1D1D1B);  // simulator card bg
  static const surfaceDarker = Color(0xFF2C2C2A); // nested card inside dark

  // ── Borders ──────────────────────────────────────────────────────────────
  static const borderSoft    = Color(0x26000000); // rgba(0,0,0,0.15)
  static const borderStronger = Color(0x33000000); // rgba(0,0,0,0.20)
  static const borderDark    = Color(0xFF444441);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFF1D1D1B);
  static const textSecondary = Color(0xFF5F5E5A);
  static const textTertiary  = Color(0xFF888780);
  static const textOnDark    = Colors.white;
  static const textOnDarkDim = Color(0xFFB4B2A9);
  static const textOnDarkFaint = Color(0xFFD3D1C7);

  // ── Purple (primary / AI / commission) ───────────────────────────────────
  static const primary       = Color(0xFF7F77DD);
  static const primaryDark   = Color(0xFF3C3489);
  static const primaryDarker = Color(0xFF26215C);
  static const primaryLight  = Color(0xFFEEEDFE);
  static const primaryBorder = Color(0xFFAFA9EC);

  // ── Green (success / growth) ─────────────────────────────────────────────
  static const success        = Color(0xFF1D9E75);
  static const successText    = Color(0xFF085041);
  static const successLight   = Color(0xFFE1F5EE);
  static const successBorder  = Color(0xFF9FE1CB);
  static const successVivid   = Color(0xFF5DCAA5);

  // ── Amber (warning / escrow / VIP) ───────────────────────────────────────
  static const warning       = Color(0xFFEF9F27);
  static const warningText   = Color(0xFF854F0B);
  static const warningLight  = Color(0xFFFAEEDA);
  static const warningVivid  = Color(0xFFFAC775);
  static const warningDarker = Color(0xFF412402);

  // ── Red (danger / anomaly) ───────────────────────────────────────────────
  static const danger        = Color(0xFFE24B4A);
  static const dangerText    = Color(0xFF791F1F);
  static const dangerDeep    = Color(0xFFA32D2D);
  static const dangerLight   = Color(0xFFFCEBEB);
  static const dangerBorder  = Color(0xFFF09595);
  static const dangerDown    = Color(0xFF993C1D);

  // ── Pink (churn / women / specialty) ─────────────────────────────────────
  static const churn         = Color(0xFFD4537E);
  static const churnText     = Color(0xFF72243E);
  static const churnDeep     = Color(0xFF993556);
  static const churnLight    = Color(0xFFFBEAF0);
  static const churnBorder   = Color(0xFFF4C0D1);
  static const churnSoft     = Color(0xFFF4C0D1);

  // ── Spacing ──────────────────────────────────────────────────────────────
  static const spaceXs  = 4.0;
  static const spaceSm  = 8.0;
  static const spaceMd  = 12.0;
  static const spaceLg  = 16.0;
  static const spaceXl  = 20.0;
  static const spaceXxl = 28.0;

  // ── Radius ───────────────────────────────────────────────────────────────
  static const radiusSm = 6.0;
  static const radiusMd = 8.0;
  static const radiusLg = 12.0;
  static const radiusXl = 16.0;

  // ── Typography ───────────────────────────────────────────────────────────
  // Font is inherited from `ThemeData.textTheme` (Assistant) — no override.
  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.2,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.3,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 13,
    color: textPrimary,
    height: 1.5,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    color: textSecondary,
    height: 1.5,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: textSecondary,
  );
  static const TextStyle captionTertiary = TextStyle(
    fontSize: 11,
    color: textTertiary,
  );
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    color: textTertiary,
  );
  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );

  // ── Shared decorations ───────────────────────────────────────────────────
  static BoxDecoration cardDecoration({Color? borderColor}) => BoxDecoration(
        color: surface,
        border: Border.all(
          color: borderColor ?? borderSoft,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(radiusLg),
      );

  static BoxDecoration badgeDecoration({
    required Color background,
  }) =>
      BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      );
}

/// Reusable outer card matching the mockup's `.card` class
/// (background white, 0.5px border, radius 12, padding 20/24).
class MonetizationCard extends StatelessWidget {
  const MonetizationCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 20,
    ),
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: MonetizationTokens.cardDecoration(borderColor: borderColor),
      child: child,
    );
  }
}

/// A tiny rounded pill used throughout the tab (LIVE, delta %, etc.).
class MonetizationPill extends StatelessWidget {
  const MonetizationPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.fontSize = 10,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: MonetizationTokens.badgeDecoration(background: background),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          color: foreground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
