import 'package:flutter/material.dart';

/// AnySkill — AnyTasks Module Palette (v14.0.0)
///
/// Scoped palette for the AnyTasks micro-task marketplace module ONLY.
/// Keeps the rest of the app on `Brand.*` — follows the same pattern as
/// `MapPalette` (v12.9.0). Based on the UI/UX spec at
/// `docs/ui-specs/AnyTasks/AnyTasks_UI_UX_Spec.docx`.
///
/// Design intent (from spec):
///   • Client screens lean on purple primary (`#6C63FF`)
///   • Provider screens lean on green primary (`#2D6A4F`) — reinforces
///     "Accept task" as dominant CTA.
///   • Earnings/price tags in amber, urgency in coral, escrow in blue.
abstract final class TasksPalette {
  // ── Client (purple) ────────────────────────────────────────────
  static const clientPrimary      = Color(0xFF6C63FF);
  static const clientPrimaryDark  = Color(0xFF5048C7);
  static const clientPrimarySoft  = Color(0xFFEDEAFF);

  // ── Provider (green) — Accept CTA ──────────────────────────────
  static const providerPrimary    = Color(0xFF2D6A4F);
  static const providerPrimaryDk  = Color(0xFF1F4D38);
  static const providerPrimarySft = Color(0xFFE8F2EC);

  // ── Accents ────────────────────────────────────────────────────
  static const amber              = Color(0xFFB5651D); // price tag / streak
  static const amberSoft          = Color(0xFFFFF4E5);
  static const coral              = Color(0xFFD85A30); // urgency badge
  static const coralSoft          = Color(0xFFFDECE5);
  static const escrowBlue         = Color(0xFF185FA5);
  static const escrowBlueSoft     = Color(0xFFE5F0FA);

  // ── Semantic ───────────────────────────────────────────────────
  static const success            = Color(0xFF0F6E56);
  static const danger             = Color(0xFFE24B4A);

  // ── Text ───────────────────────────────────────────────────────
  static const textPrimary        = Color(0xFF1B1B1B);
  static const textSecondary      = Color(0xFF6B7280);
  static const textHint           = Color(0xFF9CA3AF);

  // ── Surfaces ───────────────────────────────────────────────────
  static const scaffoldBg         = Color(0xFFF8F9FA);
  static const cardBg             = Color(0xFFFFFFFF);
  static const border             = Color(0xFFE0E0E0);
  static const borderSoft         = Color(0xFFF0F0F0);

  // ── Shadows ────────────────────────────────────────────────────
  static const cardShadow = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  // ── Radii (from spec) ──────────────────────────────────────────
  static const rCard    = 12.0;
  static const rButton  = 8.0;
  static const rPill    = 24.0;
  static const rChip    = 20.0;
}
