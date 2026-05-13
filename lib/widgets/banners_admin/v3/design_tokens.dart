import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Studio design system — scoped tokens for the redesigned admin "Banners"
/// experience (CLAUDE.md §49 + future §51 redesign per
/// `docs/ui-specs/Baner/banners-mockup-v3.html`).
///
/// **Scope rule:** This palette lives ONLY inside `lib/screens/admin_banners/`
/// and `lib/widgets/banners_admin/v3/`. Customer-facing code keeps `Brand.*`
/// from `lib/theme/app_theme.dart`. Same scoping pattern as Vault (§29) and
/// Monetization (§31).
///
/// **Typography decision (user sign-off, 2026-04-25):**
///   The mockup uses Fraunces (Latin-only serif/display). Hebrew text in
///   Fraunces falls back to a sans-serif that ruins the premium feel.
///   The app already wires `GoogleFonts.assistantTextTheme(...)` into the
///   global Theme at [app_theme.dart:185]. Studio inherits that —
///   `StudioText.*` returns plain TextStyles **without** re-invoking
///   GoogleFonts, so we don't trigger a per-build network fetch (the
///   first deploy of Phase 1 crashed in production with "Cannot read
///   properties of null (reading 'toString')" — most likely root cause
///   was google_fonts.assistant() failing during render due to web font
///   fetch races). `inherit: true` lets each Text inherit family/weight
///   from the ambient `DefaultTextStyle` of the admin scaffold.
///
/// **Backwards compatibility:** [BannersTokens] from
/// `lib/widgets/banners_admin/design_tokens.dart` is the older v2 palette
/// (purple `#6B5CFF`). It stays alive so v1 + v2 + VIP tabs keep working
/// during the rollout. This new system uses `Studio` as its prefix.
/// ═══════════════════════════════════════════════════════════════════════════

class StudioColors {
  StudioColors._();

  // ── Backgrounds ──────────────────────────────────────────────────────────
  /// Page background — soft warm off-white.
  static const bg = Color(0xFFFAFAF7);

  /// Card surface.
  static const bgElevated = Color(0xFFFFFFFF);

  /// Input fields, hover states, secondary surfaces.
  static const bgSubtle = Color(0xFFF4F3EF);

  /// Selected rows, deeper hover, bulk-action zones.
  static const bgTonal = Color(0xFFEFEEE8);

  // ── Ink (text) ──────────────────────────────────────────────────────────
  /// Primary text — softened black, never pure `#000`.
  static const ink = Color(0xFF1A1A1A);
  static const ink2 = Color(0xFF3A3A38);
  static const ink3 = Color(0xFF6B6B68);
  static const ink4 = Color(0xFF9A9A95);
  static const ink5 = Color(0xFFC8C7BF);

  // ── Lines ───────────────────────────────────────────────────────────────
  static const line = Color(0x0F000000); // rgba(0,0,0,.06)
  static const line2 = Color(0x1A000000); // rgba(0,0,0,.10)
  static const lineStrong = Color(0x24000000); // rgba(0,0,0,.14)

  // ── Status ──────────────────────────────────────────────────────────────
  static const success = Color(0xFF1A7F4E);
  static const successBg = Color(0xFFE8F5EE);
  static const warn = Color(0xFFB8651A);
  static const warnBg = Color(0xFFFBF1E2);
  static const danger = Color(0xFFB83A2A);
  static const dangerBg = Color(0xFFFBEBE7);
  static const info = Color(0xFF2C5BA8);
  static const infoBg = Color(0xFFE9F0FB);

  // ── Gold (VIP) ──────────────────────────────────────────────────────────
  static const gold = Color(0xFFB89855);
  static const goldSoft = Color(0xFFF5EDD9);
  static const goldDeep = Color(0xFF8C6F36);

  // ── Subcategory (new placement) ─────────────────────────────────────────
  static const subcatBg = Color(0xFFE0F2EC);
  static const subcatInk = Color(0xFF0F7A55);

  // ── Wallet (purple) ─────────────────────────────────────────────────────
  static const walletBg = Color(0xFFF0E5F8);
  static const walletInk = Color(0xFF6B3A8F);

  // ── Gradients ───────────────────────────────────────────────────────────
  /// VIP-featured surface (Placement card + VIP hero on Screen C).
  static const vipGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF1F1B14), Color(0xFF2A2317), Color(0xFF1A1A1A)],
    stops: [0.0, 0.5, 1.0],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFFB89855), Color(0xFF8C6F36)],
  );

  static const ctrBarGradient = LinearGradient(
    colors: [success, gold],
  );
}

class StudioRadius {
  StudioRadius._();
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

class StudioSpacing {
  StudioSpacing._();
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s7 = 32.0;
  static const s8 = 40.0;
  static const s9 = 56.0;
}

class StudioShadows {
  StudioShadows._();
  static const sh1 = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const sh2 = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const sh3 = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
  static const sh4 = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 64, offset: Offset(0, 24)),
  ];
  static const goldGlow = [
    BoxShadow(
      color: Color(0x40B89855),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}

/// Display & body typography. Display = Assistant SemiBold (the chosen
/// substitute for the mockup's Fraunces); body = Assistant.
class StudioText {
  StudioText._();

  /// Big page title — "באנרים · Studio". Mockup spec: 38px, FontWeight 400,
  /// letterSpacing -.025em. We use w600 because Assistant has no display
  /// weight under SemiBold. fontFamily intentionally omitted so it
  /// inherits Assistant from the global Theme.
  static TextStyle display({Color? color}) => TextStyle(
        fontSize: 38,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.95, // 38 * -.025
        height: 1.1,
        color: color ?? StudioColors.ink,
      );

  /// Section titles ("4 מיקומים פעילים", "כל הבאנרים").
  static TextStyle h2({Color? color}) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.44,
        color: color ?? StudioColors.ink,
      );

  /// Sub-section titles, placement card names.
  static TextStyle h3({Color? color}) => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.27,
        color: color ?? StudioColors.ink,
      );

  /// KPI big numbers, metric values in tables — tabular numerals.
  static TextStyle metricLarge({Color? color}) => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.64,
        height: 1,
        color: color ?? StudioColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Mid-size metrics (Placement card stats, table cells).
  static TextStyle metricMd({Color? color}) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color ?? StudioColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle metricSm({Color? color}) => TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: color ?? StudioColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Body — labels, table headers (uppercase via .copyWith(letterSpacing)).
  static TextStyle body({Color? color}) => TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: color ?? StudioColors.ink2,
      );

  static TextStyle bodyMedium({Color? color}) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color ?? StudioColors.ink2,
      );

  /// Caption / meta text under titles.
  static TextStyle caption({Color? color}) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color ?? StudioColors.ink3,
      );

  static TextStyle captionSm({Color? color}) => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        color: color ?? StudioColors.ink4,
      );

  /// Tiny uppercase labels — KPI labels, "ספקים", "CTR" etc.
  static TextStyle overline({Color? color}) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.42,
        color: color ?? StudioColors.ink4,
      );

  /// Pill / chip text.
  static TextStyle chip({Color? color}) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color ?? StudioColors.ink2,
      );
}

/// Common card decoration — used as the base for KPI / Placement / Insight.
BoxDecoration studioCard({
  double radius = StudioRadius.md,
  Color? color,
  Color? borderColor,
  List<BoxShadow>? shadow,
}) {
  return BoxDecoration(
    color: color ?? StudioColors.bgElevated,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? StudioColors.line),
    boxShadow: shadow ?? StudioShadows.sh1,
  );
}
