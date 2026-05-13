// Motorcycle Towing CSM — scoped palette + shared design tokens.
// Used by every screen under `lib/screens/motorcycle_tow/`.
//
// Light cream + soft purple/green/amber. Does NOT replace `Brand.*` (used
// everywhere else in the app — see CLAUDE.md §3d / §29 / §31 / §51 for the
// "scoped palette" convention).
//
// Source of truth: `docs/ui-specs/Motorcycle/PROMPT_FOR_CLAUDE_CODE.md`
// → Color Palette section. Do not change values without updating the spec.
import 'package:flutter/material.dart';

class MotorcycleTowPalette {
  // ── Primary — purple ────────────────────────────────────────────────────
  static const purple900 = Color(0xFF26215C);
  static const purple700 = Color(0xFF3C3489);
  static const purple500 = Color(0xFF534AB7);
  static const purple300 = Color(0xFF7F77DD);
  static const purple200 = Color(0xFFCECBF6);
  static const purple50 = Color(0xFFEEEDFE);

  // ── Success — green ─────────────────────────────────────────────────────
  static const green700 = Color(0xFF0F6E56);
  static const green500 = Color(0xFF1D9E75);
  static const green300 = Color(0xFF5DCAA5);
  static const green50 = Color(0xFFE1F5EE);

  // ── Warning — amber ─────────────────────────────────────────────────────
  static const amber800 = Color(0xFF854F0B);
  static const amber600 = Color(0xFFBA7517);
  static const amber50 = Color(0xFFFAEEDA);

  // ── Error — red (used on tracking screen SOS button) ────────────────────
  static const red700 = Color(0xFF791F1F);
  static const red500 = Color(0xFFA32D2D);
  static const red50 = Color(0xFFFCEBEB);

  // ── Neutrals ────────────────────────────────────────────────────────────
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFF5F4EE);
  static const textPrimary = Color(0xFF2C2C2A);
  static const textSecondary = Color(0xFF5F5E5A);
  static const textTertiary = Color(0xFF888780);
  static const borderTertiary = Color(0xFFE8E6DD);
  static const borderSecondary = Color(0xFFD3D1C7);
  static const switchOff = Color(0xFFD3D1C7);
}
