// Flash Auction — scoped palette + design tokens.
//
// Mirrors the Motorcycle CSM palette (lib/screens/motorcycle_tow/) so the
// urgent flow feels visually consistent with the parent category. The
// urgency is communicated through layout density + the red banner on the
// issue screen, NOT through a totally different color system.
//
// Source of truth: docs/ui-specs/Motorcycle/Motorcycle 2/customer-flow.html
// CSS `:root` variables. Anything that diverges here should be flagged in
// the screen's section comment so future devs know it's intentional.
import 'package:flutter/material.dart';

class FlashPalette {
  // Primary — purple (matches Motorcycle CSM).
  static const purple900 = Color(0xFF26215C);
  static const purple700 = Color(0xFF3C3489);
  static const purple500 = Color(0xFF534AB7);
  static const purple300 = Color(0xFF7F77DD);
  static const purple200 = Color(0xFFCECBF6);
  static const purple50 = Color(0xFFEEEDFE);

  // Success — green (matches Motorcycle CSM).
  static const green700 = Color(0xFF0F6E56);
  static const green500 = Color(0xFF1D9E75);
  static const green300 = Color(0xFF5DCAA5);
  static const green50 = Color(0xFFE1F5EE);

  // Warning — amber (matches Motorcycle CSM).
  static const amber800 = Color(0xFF854F0B);
  static const amber600 = Color(0xFFBA7517);
  static const amber50 = Color(0xFFFAEEDA);

  // Danger / urgency — red (Flash-Auction-specific accent for urgent
  // banner + emergency bullets in the safety dialog).
  static const red700 = Color(0xFF7F1D1D);
  static const red500 = Color(0xFFDC2626);
  static const red400 = Color(0xFFEF4444);
  static const red50 = Color(0xFFFEE2E2);

  // Neutrals.
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFF5F4EE);
  static const textPrimary = Color(0xFF2C2C2A);
  static const textSecondary = Color(0xFF5F5E5A);
  static const textTertiary = Color(0xFF888780);
  static const borderTertiary = Color(0xFFE8E6DD);
  static const borderSecondary = Color(0xFFD3D1C7);
}
