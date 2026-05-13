// Scoped palette for the Babysitter Emergency Dispatch screens.
// Soft pink/purple cream — child-friendly, with red urgency accents.
// Mirrors FlashPalette structure (CLAUDE.md §57 / §59) but tuned for
// childcare context. Does NOT replace `Brand.*` — only used inside
// `lib/screens/babysitter_emergency/`.
import 'package:flutter/material.dart';

class BabyEmergencyPalette {
  // ── Primary — soft purple/pink ───────────────────────────────────────
  static const purple900 = Color(0xFF3B1E5C);
  static const purple700 = Color(0xFF6633A8);
  static const purple500 = Color(0xFF8B5CF6);
  static const purple300 = Color(0xFFB196F1);
  static const purple200 = Color(0xFFDED5FA);
  static const purple50 = Color(0xFFF5F1FE);

  // ── Pink accent (child-warm) ─────────────────────────────────────────
  static const pink600 = Color(0xFFDB2777);
  static const pink400 = Color(0xFFEC4899);
  static const pink50 = Color(0xFFFCE7F3);

  // ── Trust green (background-checked badge, "verified" sitter) ────────
  static const green700 = Color(0xFF166534);
  static const green500 = Color(0xFF16A34A);
  static const green400 = Color(0xFF22C55E);
  static const green50 = Color(0xFFE7F8ED);

  // ── Warning amber ────────────────────────────────────────────────────
  static const amber700 = Color(0xFF92400E);
  static const amber500 = Color(0xFFF59E0B);
  static const amber50 = Color(0xFFFEF3C7);

  // ── Danger / emergency red ───────────────────────────────────────────
  static const red700 = Color(0xFF991B1B);
  static const red500 = Color(0xFFDC2626);
  static const red400 = Color(0xFFEF4444);
  static const red50 = Color(0xFFFEE2E2);

  // ── Neutrals ─────────────────────────────────────────────────────────
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFFAF7FE); // soft purple-tinted cream
  static const bgTertiary = Color(0xFFF3EFF9);
  static const textPrimary = Color(0xFF231C2D);
  static const textSecondary = Color(0xFF5B5269);
  static const textTertiary = Color(0xFF8C8395);
  static const borderTertiary = Color(0xFFE8E1F0);
  static const borderSecondary = Color(0xFFD4CADF);
}
