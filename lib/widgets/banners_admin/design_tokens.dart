import 'package:flutter/material.dart';

/// Scoped design system for the v15.x admin banners tab redesign.
///
/// This palette intentionally diverges from the app-wide `Brand.indigo`
/// (`#6366F1`) — see decision #1 in
/// `docs/ui-specs/banners_redesign/docs/02_claude_code_prompt.md`:
/// the admin banners tab uses purple `#6B5CFF` per the product spec,
/// while the customer-facing `_PromoCarousel` in
/// [home_tab.dart:1666](lib/screens/home_tab.dart#L1666) continues to
/// render with `Brand.indigo`.
///
/// Pattern follows `MonetizationTokens` in
/// [lib/widgets/monetization/design_tokens.dart] (§31 of CLAUDE.md).
/// Do NOT read through `Theme.of(context)` — every color here is a
/// const hex so consuming widgets can be cheap `const` trees.
///
/// ── Spec source ─────────────────────────────────────────────────────
/// Values come verbatim from `01_product_spec.md` section
/// "עקרונות עיצוב מנחים" + the two HTML mockups
/// (`mockups/01_banners_list.html`, `mockups/02_provider_carousel_builder.html`).
/// If a value here conflicts with the mockup, the mockup wins.
class BannersTokens {
  BannersTokens._();

  // ── Ink (text) ─────────────────────────────────────────────────────
  /// Primary text — softened black, not pure `#000`.
  static const ink   = Color(0xFF0A0A0A);
  /// Secondary text.
  static const ink2  = Color(0xFF3F3F46);
  /// Muted text (captions, meta).
  static const ink3  = Color(0xFF71717A);
  /// Hints / placeholder.
  static const ink4  = Color(0xFFA1A1AA);

  // ── Lines ──────────────────────────────────────────────────────────
  /// 0.5px divider — `rgba(10,10,10,0.08)`.
  static const line  = Color(0x140A0A0A); // alpha 20 ≈ 8%
  /// 1px divider — `rgba(10,10,10,0.14)`.
  static const line2 = Color(0x240A0A0A); // alpha 36 ≈ 14%

  // ── Surfaces ───────────────────────────────────────────────────────
  /// Page background.
  static const bg      = Color(0xFFFAFAF9);
  /// Card / surface.
  static const surface = Color(0xFFFFFFFF);

  // ── Accent (the lone color in a monochrome design) ─────────────────
  /// Primary accent — purple, scoped ONLY to admin banners UI.
  static const accent     = Color(0xFF6B5CFF);
  /// Darker accent for text on accent-wash.
  static const accentInk  = Color(0xFF3C33A8);
  /// Accent tint for AI insights, provider_carousel highlights, focus rings.
  static const accentWash = Color(0xFFF4F2FF);

  // ── Status (success / warn / danger) ───────────────────────────────
  static const success     = Color(0xFF0F7A4D);
  static const successWash = Color(0xFFE8F5EE);
  static const warn        = Color(0xFF9C5A0B);
  static const warnWash    = Color(0xFFFBF3E4);
  static const danger      = Color(0xFFB02D2D);

  // ── Spacing ────────────────────────────────────────────────────────
  static const spaceXs  = 4.0;
  static const spaceSm  = 8.0;
  static const spaceMd  = 12.0;
  static const spaceLg  = 16.0;
  static const spaceXl  = 20.0;
  static const spaceXxl = 28.0;

  // ── Radii ──────────────────────────────────────────────────────────
  /// Buttons.
  static const radiusSm = 6.0;
  /// Metric cards, small surfaces.
  static const radiusMd = 8.0;
  /// Large cards.
  static const radiusLg = 10.0;
  /// Hero panels.
  static const radiusXl = 12.0;
  /// Chips / pills.
  static const radiusPill = 999.0;

  // ── Typography (only 2 weights — 400 + 500, never 600/700) ─────────
  /// h1 — page title (22px).
  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    color: ink,
    letterSpacing: -0.22, // -0.01em ≈ -0.22px at 22
    height: 1.2,
  );
  /// h2 — section header (18px).
  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: ink,
    letterSpacing: -0.18,
    height: 1.3,
  );
  /// h3 — card title (16px).
  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: ink,
    height: 1.35,
  );
  /// body — default 14px.
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: ink,
    height: 1.5,
  );
  /// bodySm — 13px for table cells, secondary rows.
  static const TextStyle bodySm = TextStyle(
    fontSize: 13,
    color: ink,
    height: 1.5,
  );
  /// bodyMuted — 13px for descriptions.
  static const TextStyle bodyMuted = TextStyle(
    fontSize: 13,
    color: ink2,
    height: 1.5,
  );
  /// caption — 12px.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: ink3,
    height: 1.4,
  );
  /// captionSm — 11px for labels, trends.
  static const TextStyle captionSm = TextStyle(
    fontSize: 11,
    color: ink3,
    height: 1.3,
  );
  /// micro — 10px, used in badges.
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    color: ink3,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );
  /// metric — large numeric display (22px + tighter tracking).
  static const TextStyle metric = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    color: ink,
    letterSpacing: -0.44, // -0.02em ≈ -0.44px at 22
    height: 1.1,
  );

  // ── Animation durations (spec: 120-180ms for interactions) ─────────
  static const Duration hoverDuration  = Duration(milliseconds: 140);
  static const Duration toggleDuration = Duration(milliseconds: 180);
  static const Duration fadeDuration   = Duration(milliseconds: 350);

  // ── Shared decorations ─────────────────────────────────────────────
  /// Card shell — 0.5px border on monochrome line color. No shadow.
  static BoxDecoration cardDecoration({
    Color? borderColor,
    double radius = radiusLg,
  }) =>
      BoxDecoration(
        color: surface,
        border: Border.all(
          color: borderColor ?? line,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(radius),
      );

  /// Focus ring — accent color at 30% opacity, 2px outset.
  static BoxShadow get focusRing => BoxShadow(
        color: accent.withValues(alpha: 0.30),
        blurRadius: 0,
        spreadRadius: 2,
      );
}

/// A reusable admin card matching `.card` in the mockup — white surface,
/// 0.5px border on [BannersTokens.line], radius 10px, default padding 16.
class BannersCard extends StatelessWidget {
  const BannersCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BannersTokens.spaceLg),
    this.borderColor,
    this.radius = BannersTokens.radiusLg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BannersTokens.cardDecoration(
        borderColor: borderColor,
        radius: radius,
      ),
      child: child,
    );
  }
}

/// Thin horizontal divider — the `0.5px solid line` in the spec.
class BannersDivider extends StatelessWidget {
  const BannersDivider({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: color ?? BannersTokens.line,
    );
  }
}
