// Delivery Express — scoped palette + design tokens.
//
// Mirrors FlashPalette structure (lib/screens/flash_auction/) for layout
// consistency across emergency-dispatch flows, but swaps the motorcycle
// purple for delivery gold/amber. Light cream surface like Flash Auction —
// keeps urgency cues red (emergency banner + CTA), success green, and
// text neutral.
//
// Source of inspiration: Delivery CSM dark gold palette (CLAUDE.md §33).
// We can't use the dark surface here because Flash Auction's UX has been
// validated by users on light backgrounds — splitting the design language
// between two emergency flows would feel disjointed.
import 'package:flutter/material.dart';

class DeliveryExpressPalette {
  // Primary — delivery gold/amber (matches Delivery CSM brand tokens).
  static const gold900 = Color(0xFF7C2D12);
  static const gold700 = Color(0xFFB45309);
  static const gold500 = Color(0xFFD97706);
  static const gold400 = Color(0xFFF59E0B);
  static const gold200 = Color(0xFFFCD34D);
  static const gold50 = Color(0xFFFEF3C7);

  // Success — green (matches Flash Auction).
  static const green700 = Color(0xFF0F6E56);
  static const green500 = Color(0xFF1D9E75);
  static const green300 = Color(0xFF5DCAA5);
  static const green50 = Color(0xFFE1F5EE);

  // Warning — amber accent for "tip" callouts.
  static const amber800 = Color(0xFF854F0B);
  static const amber600 = Color(0xFFBA7517);
  static const amber50 = Color(0xFFFAEEDA);

  // Danger / urgency — red for "מצב חירום פעיל" banner + emergency calls.
  static const red700 = Color(0xFF7F1D1D);
  static const red500 = Color(0xFFDC2626);
  static const red400 = Color(0xFFEF4444);
  static const red50 = Color(0xFFFEE2E2);

  // Neutrals (identical to FlashPalette — cream surface).
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFF5F4EE);
  static const textPrimary = Color(0xFF2C2C2A);
  static const textSecondary = Color(0xFF5F5E5A);
  static const textTertiary = Color(0xFF888780);
  static const borderTertiary = Color(0xFFE8E6DD);
  static const borderSecondary = Color(0xFFD3D1C7);
}
