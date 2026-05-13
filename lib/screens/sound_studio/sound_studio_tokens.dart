/// Sound Studio §53 — scoped design tokens.
///
/// Mirrors `docs/ui-specs/sound_studio_mockups/assets/styles.css`.
/// Scoped to `lib/screens/sound_studio/` only — does NOT replace
/// `Brand.*` from `app_theme.dart`. Same pattern as Vault (§29),
/// Monetization (§31), Banners (§51).
library;

import 'package:flutter/material.dart';

class StudioPalette {
  // ── Surfaces ───────────────────────────────────────────────────────────────
  static const bgPage = Color(0xFFFAFAF9);
  static const bgSurface = Color(0xFFFFFFFF);
  static const bgMuted = Color(0xFFF4F3EE);
  static const bgTertiary = Color(0xFFF1EFE8);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF5F5E5A);
  static const textTertiary = Color(0xFF888780);

  // ── Borders ────────────────────────────────────────────────────────────────
  static const borderLight = Color(0x14000000);   // rgba(0,0,0,0.08)
  static const borderMedium = Color(0x26000000);  // rgba(0,0,0,0.15)
  static const borderStrong = Color(0x40000000);  // rgba(0,0,0,0.25)

  // ── Brand palette (matches existing #6366F1-ish family but scoped) ────────
  static const primary = Color(0xFF534AB7);
  static const primaryDark = Color(0xFF3C3489);
  static const primaryLight = Color(0xFFEEEDFE);
  static const primaryLighter = Color(0xFFCECBF6);

  static const blue = Color(0xFF185FA5);
  static const blueDark = Color(0xFF0C447C);
  static const blueLight = Color(0xFFE6F1FB);

  static const green = Color(0xFF1D9E75);
  static const greenDark = Color(0xFF0F6E56);
  static const greenLight = Color(0xFFE1F5EE);

  static const amber = Color(0xFFBA7517);
  static const amberDark = Color(0xFF854F0B);
  static const amberLight = Color(0xFFFAEEDA);

  static const red = Color(0xFFA32D2D);
  static const redDark = Color(0xFF501313);
  static const redLight = Color(0xFFFCEBEB);

  // ── Per-AppSound colour assignments (mirrors mockup) ───────────────────────
  static Color soundColor(String soundId) {
    switch (soundId) {
      case 'wealthCrystal':
        return primary;
      case 'solutionSnap':
        return blue;
      case 'opportunityPulse':
        return greenDark;
      case 'growthAscend':
        return amberDark;
      default:
        return textTertiary;
    }
  }

  static Color soundLight(String soundId) {
    switch (soundId) {
      case 'wealthCrystal':
        return primaryLight;
      case 'solutionSnap':
        return blueLight;
      case 'opportunityPulse':
        return greenLight;
      case 'growthAscend':
        return amberLight;
      default:
        return bgMuted;
    }
  }

  static Color soundDark(String soundId) {
    switch (soundId) {
      case 'wealthCrystal':
        return primaryDark;
      case 'solutionSnap':
        return blueDark;
      case 'opportunityPulse':
        return greenDark;
      case 'growthAscend':
        return amberDark;
      default:
        return textSecondary;
    }
  }

  // ── Card decoration helpers ────────────────────────────────────────────────
  static BoxDecoration card({bool selected = false, bool dashed = false}) {
    return BoxDecoration(
      color: bgSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: selected ? primary : borderLight,
        width: selected ? 2 : 0.5,
        style: dashed ? BorderStyle.solid : BorderStyle.solid,
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 1)),
      ],
    );
  }

  static BoxShadow get cardShadow =>
      const BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2));
}

class StudioPills {
  static Widget pill({
    required String text,
    Color background = StudioPalette.bgTertiary,
    Color foreground = StudioPalette.textSecondary,
    Widget? leading,
    double fontSize = 11,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  static Widget statusDot({Color color = StudioPalette.green, bool pulse = false}) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse) return dot;
    return _PulsingDot(child: dot);
  }
}

class _PulsingDot extends StatefulWidget {
  final Widget child;
  const _PulsingDot({required this.child});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: 0.5 + 0.5 * (1 - _ctrl.value),
        child: child,
      ),
    );
  }
}
