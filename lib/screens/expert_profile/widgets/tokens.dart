import 'package:flutter/material.dart';

/// Shared color tokens for the expert profile screen + its extracted widgets.
/// Used by every file under `lib/screens/expert_profile/widgets/`.
///
/// History: pre-§80, these were private constants inside
/// `expert_profile_screen.dart`. As §80 extracted methods into sibling
/// widget files, the constants needed a single home. The screen still
/// imports + uses them.
class ExpertProfileTokens {
  ExpertProfileTokens._();

  /// Primary indigo. Used for buttons, accents, and the "Book Now" CTA.
  static const purple = Color(0xFF6366F1);

  /// Tinted background for purple accents (chips, hover states, info cards).
  static const purpleSoft = Color(0xFFF0F0FF);

  /// Gold for ratings, volunteer hearts, and premium accents.
  static const gold = Color(0xFFD4AF37);
}
