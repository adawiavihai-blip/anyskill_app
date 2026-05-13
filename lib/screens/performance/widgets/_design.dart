import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared dark glassmorphism palette + helpers for the Performance Observatory.
/// Scoped to `lib/screens/performance/` — does NOT replace `Brand.*`.
class PerfDesign {
  PerfDesign._();

  // Background gradient
  static const bgDeep1 = Color(0xFF050816);
  static const bgDeep2 = Color(0xFF0A0E1A);
  static const bgDeep3 = Color(0xFF0F1420);
  static const bgDeep4 = Color(0xFF1A0A2E);

  // Business palette
  static const pink = Color(0xFFEC4899);
  static const rose = Color(0xFFDB2777);
  static const indigo = Color(0xFF6366F1);
  static const purple = Color(0xFFA855F7);
  static const orange = Color(0xFFFB923C);

  // Status palette
  static const statusGreen = Color(0xFF4ADE80);
  static const statusYellow = Color(0xFFFDBA74);
  static const statusRed = Color(0xFFFCA5A5);
  static const statusBlue = Color(0xFF60A5FA);

  // Text tiers
  static const textHi = Colors.white;
  static Color get textMid => Colors.white.withValues(alpha: 0.78);
  static Color get textLo => Colors.white.withValues(alpha: 0.52);

  // Glass tokens
  static Color get glassFill => Colors.white.withValues(alpha: 0.03);
  static Color get glassFillStrong => Colors.white.withValues(alpha: 0.05);
  static Color get glassBorder => Colors.white.withValues(alpha: 0.08);

  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgDeep1, bgDeep2, bgDeep3, bgDeep4],
    stops: [0.0, 0.35, 0.65, 1.0],
  );

  /// A glass card with blur + subtle gradient border. Use everywhere for
  /// consistency.
  static Widget glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    double radius = 18,
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: glassFill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? glassBorder,
              width: 1,
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  /// A decorative radial orb. Overlay 3-5 of these on the scaffold background
  /// for the signature "Observatory" feel.
  static Widget orb({
    required double left,
    required double top,
    required double size,
    required Color color,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.35),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
