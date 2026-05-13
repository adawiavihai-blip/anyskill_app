/// Community module — scoped design system tokens.
///
/// **Scope:** these tokens are used ONLY inside `lib/screens/community/`,
/// `lib/widgets/community/`, and the Community banner inside
/// [home_tab.dart]. They do NOT replace [Brand] (`lib/theme/app_theme.dart`)
/// — same isolation pattern as Vault (CLAUDE.md §29), Monetization (§31),
/// Banners (§51), Sound Studio (§54).
///
/// **Source of truth:** `docs/ui-specs/anyskill_community/docs/DESIGN_SYSTEM.md`
/// + the 17 mockups under `docs/ui-specs/anyskill_community/mockups/`.
///
/// Reference style: Linear / Stripe / Airbnb 2026 — minimalist, monochrome
/// with a single gold accent for the volunteer heart.
library;

import 'package:flutter/material.dart';

/// Color palette — minimalist black/white with a single gold accent.
class CommunityColors {
  CommunityColors._();

  // ── Base ──────────────────────────────────────────────────────────────
  static const Color primaryBlack = Color(0xFF18181B);
  static const Color primaryWhite = Color(0xFFFFFFFF);
  static const Color background   = Color(0xFFF5F5F4);
  static const Color surface      = Color(0xFFFAFAF9);

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF18181B);
  static const Color textSecondary = Color(0xFF52525B);
  static const Color textTertiary  = Color(0xFF71717A);
  static const Color textMuted     = Color(0xFFA1A1AA);

  // ── Borders (always 0.5px in this module — never thicker) ────────────
  static const Color borderPrimary = Color(0x14000000); // rgba(0,0,0,0.08)
  static const Color borderSubtle  = Color(0x0F000000); // rgba(0,0,0,0.06)
  static const Color borderSofter  = Color(0x0A000000); // rgba(0,0,0,0.04)

  // ── Gold heart — the SINGLE accent in the entire module ──────────────
  static const Color goldHeart         = Color(0xFFA87F2A);
  static const Color goldHeartLight    = Color(0x14A87F2A); //  8% opacity
  static const Color goldHeartBorder   = Color(0x40A87F2A); // 25% opacity
  static const Color goldHeartBg       = Color(0xFFFFFBEB);
  static const Color goldHeartBgBorder = Color(0xFFFEF3C7);
  static const Color goldHeartText     = Color(0xFF92400E);

  // ── Status ────────────────────────────────────────────────────────────
  static const Color success     = Color(0xFF16A34A);
  static const Color successBg   = Color(0xFFDCFCE7);
  static const Color successText = Color(0xFF166534);

  static const Color warning     = Color(0xFFF59E0B);
  static const Color warningBg   = Color(0xFFFEF3C7);
  static const Color warningText = Color(0xFFB45309);

  static const Color danger      = Color(0xFFB91C1C);
  static const Color dangerBg    = Color(0xFFFEF2F2);

  static const Color info         = Color(0xFF0EA5E9);
  static const Color infoBg       = Color(0xFFF0F9FF);
  static const Color infoText     = Color(0xFF075985);
  static const Color infoTextDeep = Color(0xFF0C4A6E);

  // ── Star rating ───────────────────────────────────────────────────────
  static const Color starGold = Color(0xFFFBBF24);

  // ── Dark surface (celebration / yearly recap / first-heart screens) ──
  static const Color darkSurface     = Color(0xFF18181B);
  static const Color darkSurfaceTop  = Color(0xFF18181B);
  static const Color darkSurfaceBot  = Color(0xFF1F1F23);

  /// Linear gradient for dark celebration backgrounds.
  static const LinearGradient darkSurfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkSurfaceTop, darkSurfaceBot],
  );

  // ── On-dark text opacities (use as Colors.white.withValues(alpha: …)) ─
  static const Color whiteHigh  = Color(0xFFFFFFFF); // 100% — primary
  static const Color whiteAlt   = Color(0xB3FFFFFF); // 70%  — secondary
  static const Color whiteMid   = Color(0x99FFFFFF); // 60%  — body
  static const Color whiteSoft  = Color(0x80FFFFFF); // 50%  — tertiary
  static const Color whiteFaint = Color(0x66FFFFFF); // 40%  — captions
  static const Color whiteWisp  = Color(0x59FFFFFF); // 35%  — finest
}

/// Typography scale — SF Pro Display / Inter / Heebo, weights 400–600 only.
///
/// Letter-spacing rules (critical for the premium feel):
/// - Headlines (24px+): −0.4 to −0.8
/// - Mid (15–22px):     −0.2 to −0.3
/// - Body (12–14px):    −0.1
/// - Tiny uppercase:    +0.2 to +0.3
class CommunityType {
  CommunityType._();

  /// Used as `fontFamily` everywhere in the module so the platform picks
  /// SF Pro on iOS and Heebo (bundled) on Android/web.
  static const String fontFamily = 'Heebo';

  // ── Headlines ─────────────────────────────────────────────────────────
  static const TextStyle hero32 = TextStyle(
    fontSize: 32, fontWeight: FontWeight.w600,
    letterSpacing: -0.8, height: 1.1,
    color: CommunityColors.textPrimary,
  );

  static const TextStyle h24 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w600,
    letterSpacing: -0.6, height: 1.2,
    color: CommunityColors.textPrimary,
  );

  static const TextStyle h22 = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w600,
    letterSpacing: -0.5, height: 1.25,
    color: CommunityColors.textPrimary,
  );

  static const TextStyle h16 = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: CommunityColors.textPrimary,
  );

  // ── Card / list titles ────────────────────────────────────────────────
  static const TextStyle title15 = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600,
    letterSpacing: -0.2, height: 1.35,
    color: CommunityColors.textPrimary,
  );

  // ── Buttons + emphasized body ─────────────────────────────────────────
  static const TextStyle button14 = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: CommunityColors.textPrimary,
  );

  // ── Body text ─────────────────────────────────────────────────────────
  static const TextStyle body14 = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400,
    letterSpacing: -0.1, height: 1.55,
    color: CommunityColors.textSecondary,
  );

  static const TextStyle body13 = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w400,
    letterSpacing: -0.1, height: 1.5,
    color: CommunityColors.textSecondary,
  );

  static const TextStyle body13Strong = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w500,
    letterSpacing: -0.1, height: 1.5,
    color: CommunityColors.textPrimary,
  );

  // ── Meta / labels ─────────────────────────────────────────────────────
  static const TextStyle label12 = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: CommunityColors.textSecondary,
  );

  /// Tiny uppercase caption (POSITIVE letter-spacing — that's intentional).
  static const TextStyle caption11 = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: CommunityColors.textTertiary,
  );

  // ── Smallest legible text — never go below this ──────────────────────
  static const TextStyle footer10 = TextStyle(
    fontSize: 10, fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: CommunityColors.textMuted,
  );
}

/// Border-radius scale.
class CommunityRadius {
  CommunityRadius._();

  static const Radius badge   = Radius.circular(8);
  static const Radius alert   = Radius.circular(10);
  static const Radius field   = Radius.circular(12);
  static const Radius card    = Radius.circular(14);
  static const Radius cardLg  = Radius.circular(18);
  static const Radius panel   = Radius.circular(22);
  static const Radius sheet   = Radius.circular(24);
  static const Radius pill    = Radius.circular(100); // pill-shaped buttons
  static const Radius circle  = Radius.circular(999); // avatars, dots
}

/// Standard decorations (cards, soft cards, gold-heart container).
class CommunityDecorations {
  CommunityDecorations._();

  /// White card with 0.5px border — the default container in this module.
  static const BoxDecoration card = BoxDecoration(
    color: CommunityColors.primaryWhite,
    borderRadius: BorderRadius.all(CommunityRadius.card),
    border: Border.fromBorderSide(BorderSide(
      color: CommunityColors.borderPrimary,
      width: 0.5,
    )),
  );

  /// Soft (gray) card — no border, used for inline stat blocks.
  static const BoxDecoration cardSoft = BoxDecoration(
    color: CommunityColors.surface,
    borderRadius: BorderRadius.all(CommunityRadius.card),
  );

  /// Gold-heart container (active gold heart banner / thank-you note).
  static BoxDecoration goldHeartContainer = BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0x10A87F2A), // ~6%
        Color(0x05A87F2A), // ~2%
      ],
    ),
    border: Border.all(
      color: const Color(0x33A87F2A), // ~20%
      width: 0.5,
    ),
    borderRadius: const BorderRadius.all(CommunityRadius.field),
  );

  /// Sticky footer divider above primary CTAs.
  static const BoxDecoration footerWithTopDivider = BoxDecoration(
    color: CommunityColors.primaryWhite,
    border: Border(
      top: BorderSide(color: CommunityColors.borderSubtle, width: 0.5),
    ),
  );
}
