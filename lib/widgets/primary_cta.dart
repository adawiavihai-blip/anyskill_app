import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// PrimaryCTA — single source of truth for the app's primary action button.
///
/// Replaces the inconsistency where "Pay & Secure" / "הזמן עכשיו" /
/// "תפוס עכשיו" / "אשר משימה" / "שלח" all rendered with different colors,
/// radii, font weights, and loading patterns. Every conversion-funnel CTA
/// should use this widget so that every screen feels like the same product.
///
/// **Variants:**
/// - `PrimaryCTAVariant.primary`   — indigo, default action
/// - `PrimaryCTAVariant.urgent`    — red gradient, emergency dispatch
/// - `PrimaryCTAVariant.success`   — green, confirm/release/done
/// - `PrimaryCTAVariant.secondary` — outlined, less weighty action
///
/// **States:**
/// - `loading: true`  — replaces icon with spinner, blocks taps
/// - `onPressed: null` — disabled (greyed out)
///
/// **Accessibility:**
/// Built-in Semantics with role=button, enabled state, and optional `hint`
/// for screen readers. Required by EU EAA 2025 + WCAG 2.1 AA on payment
/// flows.
///
/// **Migration:** When converting an existing `ElevatedButton.icon` →
/// `PrimaryCTA`, drop the wrapping `Semantics` widget — it's built in.
/// ═══════════════════════════════════════════════════════════════════════════

enum PrimaryCTAVariant { primary, urgent, success, secondary }

class PrimaryCTA extends StatelessWidget {
  /// Button label (Hebrew or English).
  final String label;

  /// Callback. `null` = disabled.
  final VoidCallback? onPressed;

  /// Optional leading icon (rendered at the start in RTL — i.e. right side).
  final IconData? icon;

  /// Visual style. Defaults to primary indigo.
  final PrimaryCTAVariant variant;

  /// Replace icon with spinner + block taps.
  final bool loading;

  /// Full-width when true (default). Otherwise wraps content.
  final bool expanded;

  /// Screen-reader hint (action description).
  final String? semanticHint;

  /// Optional override for height. Default 52 — matches mockup spec.
  final double? height;

  /// Optional smaller variant for in-card / sticky-bar usage.
  final bool dense;

  const PrimaryCTA({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = PrimaryCTAVariant.primary,
    this.loading = false,
    this.expanded = true,
    this.semanticHint,
    this.height,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final palette = _resolvePalette(variant, disabled);
    final effectiveHeight = height ?? (dense ? 44.0 : 52.0);
    final fontSize = dense ? 14.5 : 16.0;
    final iconSize = dense ? 16.0 : 18.0;

    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.foreground,
            ),
          )
        else if (icon != null)
          Icon(icon, color: palette.foreground, size: iconSize),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              color: palette.foreground,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );

    final button = Material(
      color: palette.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: effectiveHeight,
          width: expanded ? double.infinity : null,
          padding: EdgeInsets.symmetric(
              horizontal: dense ? 16 : 22, vertical: 0),
          decoration: BoxDecoration(
            gradient: palette.gradient,
            borderRadius: BorderRadius.circular(14),
            border: palette.border,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      hint: semanticHint,
      child: button,
    );
  }

  // ── Palette resolution ──────────────────────────────────────────────────

  _CTAPalette _resolvePalette(PrimaryCTAVariant v, bool disabled) {
    if (disabled) {
      return _CTAPalette(
        background: const Color(0xFFE5E7EB), // grey-200
        foreground: const Color(0xFF9CA3AF), // grey-400
        gradient:   null,
        border:     null,
      );
    }
    switch (v) {
      case PrimaryCTAVariant.primary:
        return _CTAPalette(
          background: Brand.indigo,
          foreground: Colors.white,
          gradient: const LinearGradient(
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
            colors: [Brand.indigo, Brand.indigoDark],
          ),
          border: null,
        );
      case PrimaryCTAVariant.urgent:
        return _CTAPalette(
          background: Brand.error,
          foreground: Colors.white,
          gradient: const LinearGradient(
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
          ),
          border: null,
        );
      case PrimaryCTAVariant.success:
        return _CTAPalette(
          background: Brand.success,
          foreground: Colors.white,
          gradient: const LinearGradient(
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
            colors: [Color(0xFF10B981), Color(0xFF059669)],
          ),
          border: null,
        );
      case PrimaryCTAVariant.secondary:
        return _CTAPalette(
          background: Colors.white,
          foreground: Brand.indigo,
          gradient:   null,
          border: Border.all(color: Brand.indigo, width: 1.5),
        );
    }
  }
}

class _CTAPalette {
  final Color background;
  final Color foreground;
  final LinearGradient? gradient;
  final BoxBorder? border;

  const _CTAPalette({
    required this.background,
    required this.foreground,
    required this.gradient,
    required this.border,
  });
}
