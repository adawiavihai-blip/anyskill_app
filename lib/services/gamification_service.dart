/// AnySkill — Provider Gamification Service
/// XP thresholds, level computation, progress helpers.
library;

import 'package:flutter/material.dart';

enum ProviderLevel { bronze, silver, gold }

class GamificationService {
  GamificationService._();

  static const int silverThreshold = 500;
  static const int goldThreshold   = 1500;

  static ProviderLevel levelFor(int xp) {
    if (xp >= goldThreshold)   return ProviderLevel.gold;
    if (xp >= silverThreshold) return ProviderLevel.silver;
    return ProviderLevel.bronze;
  }

  static String levelName(ProviderLevel level) {
    switch (level) {
      case ProviderLevel.gold:   return 'זהב';
      case ProviderLevel.silver: return 'כסף';
      case ProviderLevel.bronze: return 'ברונזה';
    }
  }

  /// 0.0–1.0 progress within the current level band.
  static double levelProgress(int xp) {
    final level = levelFor(xp);
    switch (level) {
      case ProviderLevel.bronze:
        return (xp / silverThreshold).clamp(0.0, 1.0);
      case ProviderLevel.silver:
        return ((xp - silverThreshold) / (goldThreshold - silverThreshold))
            .clamp(0.0, 1.0);
      case ProviderLevel.gold:
        return 1.0;
    }
  }

  /// XP remaining to next level, or 0 if already Gold.
  static int xpToNextLevel(int xp) {
    final level = levelFor(xp);
    switch (level) {
      case ProviderLevel.bronze: return silverThreshold - xp;
      case ProviderLevel.silver: return goldThreshold - xp;
      case ProviderLevel.gold:   return 0;
    }
  }

  static String nextLevelName(ProviderLevel level) {
    switch (level) {
      case ProviderLevel.bronze: return 'כסף';
      case ProviderLevel.silver: return 'זהב';
      case ProviderLevel.gold:   return 'זהב';
    }
  }

  static List<Color> levelGradient(ProviderLevel level) {
    switch (level) {
      case ProviderLevel.gold:
        return [const Color(0xFFF59E0B), const Color(0xFFD97706)];
      case ProviderLevel.silver:
        return [const Color(0xFF9CA3AF), const Color(0xFF6B7280)];
      case ProviderLevel.bronze:
        return [const Color(0xFFCD7F32), const Color(0xFFA0522D)];
    }
  }

  static Color levelProgressColor(ProviderLevel level) {
    switch (level) {
      case ProviderLevel.gold:   return const Color(0xFFF59E0B);
      case ProviderLevel.silver: return const Color(0xFF9CA3AF);
      case ProviderLevel.bronze: return const Color(0xFFCD7F32);
    }
  }

  /// Proximity sort boost: Gold×0.6, Silver×0.8, Bronze×1.0.
  /// Multiply distance by this factor before comparing — higher level = lower effective distance.
  static double proximityBoost(int xp) {
    final level = levelFor(xp);
    switch (level) {
      case ProviderLevel.gold:   return 0.6;
      case ProviderLevel.silver: return 0.8;
      case ProviderLevel.bronze: return 1.0;
    }
  }
}
