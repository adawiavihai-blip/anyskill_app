/// AnySkill — Provider Gamification Service
/// XP thresholds, level computation, progress helpers, and the client-side
/// helper to call the updateUserXP Cloud Function.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

enum ProviderLevel { bronze, silver, gold }

class GamificationService {
  GamificationService._();

  // ── Thresholds (updated at runtime via loadThresholds()) ─────────────────
  // These match the defaults seeded into settings_gamification/__levels__
  static int silverThreshold = 500;
  static int goldThreshold   = 2000;

  /// Loads level thresholds from Firestore and caches them in memory.
  /// Call once during app init (e.g., in HomeScreen.initState) so all
  /// downstream level calculations use the admin-configured values.
  static Future<void> loadThresholds() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings_gamification')
          .doc('__levels__')
          .get();
      final d = doc.data() ?? {};
      final silver = (d['silver'] as num?)?.toInt();
      final gold   = (d['gold']   as num?)?.toInt();
      if (silver != null && silver > 0)          silverThreshold = silver;
      if (gold   != null && gold   > silver!)    goldThreshold   = gold;
    } catch (_) {
      // Non-fatal: keep hardcoded defaults if Firestore unreachable
    }
  }

  // ── XP event IDs — use these constants when calling updateUserXP ─────────
  static const String evFinishJob       = 'finish_job';
  static const String evFiveStarReview  = 'five_star_review';
  static const String evQuickResponse   = 'quick_response';
  static const String evStoryUpload     = 'story_upload';
  static const String evJoinOpportunity = 'join_opportunity';
  static const String evProviderCancel  = 'provider_cancel';
  static const String evNoResponse      = 'no_response';

  /// Calls the updateUserXP Cloud Function.
  /// Returns the new XP value, or null on failure.
  ///
  /// Example:
  ///   await GamificationService.awardXP(uid, GamificationService.evFinishJob);
  static Future<int?> awardXP(String userId, String eventId) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('updateUserXP')
          .call({'userId': userId, 'eventId': eventId});
      final data = result.data as Map<String, dynamic>;
      return (data['newXp'] as num?)?.toInt();
    } catch (e) {
      debugPrint('[GamificationService] awardXP error: $e');
      return null;
    }
  }

  // ── Level computation ─────────────────────────────────────────────────────
  static ProviderLevel levelFor(int xp) {
    if (xp >= goldThreshold)   return ProviderLevel.gold;
    if (xp >= silverThreshold) return ProviderLevel.silver;
    return ProviderLevel.bronze;
  }

  /// Converts the Firestore level string ('gold' / 'silver' / 'bronze') to enum.
  static ProviderLevel levelFromString(String? s) {
    switch (s) {
      case 'gold':   return ProviderLevel.gold;
      case 'silver': return ProviderLevel.silver;
      default:       return ProviderLevel.bronze;
    }
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
    switch (levelFor(xp)) {
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
    switch (levelFor(xp)) {
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
    switch (levelFor(xp)) {
      case ProviderLevel.gold:   return 0.6;
      case ProviderLevel.silver: return 0.8;
      case ProviderLevel.bronze: return 1.0;
    }
  }
}
