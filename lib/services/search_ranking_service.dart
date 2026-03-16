/// AnySkill — Search Ranking Service
///
/// Implements the weighted scoring formula:
///   Score = (XP_Score × 0.6) + (Distance_Score × 0.2) + (Story_Bonus × 0.2)
///           + Promoted_Add
///
/// Higher score = higher position in search results.
/// All component scores are normalised to a 0–100 range before weighting,
/// so each dimension contributes proportionally regardless of raw magnitude.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'gamification_service.dart';

class SearchRankingService {
  SearchRankingService._();

  /// Max distance beyond which the distance score is 0 (50 km).
  static const double _maxDistMeters = 50000.0;

  /// Promoted providers always appear before non-promoted ones.
  /// This flat bonus ensures that no amount of XP+story+distance can
  /// push a non-promoted provider above a promoted one.
  static const double _promotedBonus = 200.0;

  // ── Formula ─────────────────────────────────────────────────────────────

  /// Returns a rank score for a single provider.
  /// Higher → better rank.
  ///
  ///   [xp]             Raw XP value from Firestore.
  ///   [distanceMeters] Euclidean distance to the searching user, or null
  ///                    if location is unknown (treated as neutral = 50 pts).
  ///   [hasActiveStory] True if provider posted a Skills Story in the last 24 h.
  ///   [isPromoted]     Admin-promoted providers float above all others.
  static double score({
    required int    xp,
    required double? distanceMeters,
    required bool   hasActiveStory,
    bool isPromoted = false,
  }) {
    // ── 1. XP Score (0–100) ──────────────────────────────────────────────
    // Capped at goldThreshold (default 2000 XP = 100 pts).
    // Providers at Gold level or above all receive the maximum XP score.
    final double xpScore =
        (xp / GamificationService.goldThreshold).clamp(0.0, 1.0) * 100.0;

    // ── 2. Distance Score (0–100) ────────────────────────────────────────
    // 0 m    → 100   (right next to user)
    // 50 km  → 0     (edge of range)
    // null   → 50    (location unknown → neutral)
    final double distScore = distanceMeters == null
        ? 50.0
        : ((_maxDistMeters - distanceMeters.clamp(0, _maxDistMeters)) /
               _maxDistMeters *
               100.0);

    // ── 3. Active Story Bonus (0 or 100) ─────────────────────────────────
    // Binary boost: posting a story in the last 24 h gives a full 100 pts.
    // Combined with the 0.2 weight this adds 20 pts to the final score —
    // enough to jump several positions in a typical result set.
    final double storyBonus = hasActiveStory ? 100.0 : 0.0;

    // ── Weighted sum ──────────────────────────────────────────────────────
    final double weighted =
        (xpScore  * 0.6) +
        (distScore * 0.2) +
        (storyBonus * 0.2);

    return weighted + (isPromoted ? _promotedBonus : 0.0);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns true if the given story Timestamp is within the last 24 hours.
  static bool isStoryActive(Timestamp? ts) {
    if (ts == null) return false;
    return DateTime.now().difference(ts.toDate()).inHours < 24;
  }

  /// Sorts [experts] in-place using [score()].
  /// Each map must contain: 'xp', 'latitude', 'longitude',
  /// 'hasActiveStory', 'isPromoted'.
  static void sortExperts(
    List<Map<String, dynamic>> experts, {
    required double? myLat,
    required double? myLng,
    required double? Function(double myLat, double myLng, double? lat, double? lng)
        distanceFn,
  }) {
    experts.sort((a, b) {
      final double sa = _expertScore(a, myLat, myLng, distanceFn);
      final double sb = _expertScore(b, myLat, myLng, distanceFn);
      return sb.compareTo(sa); // descending
    });
  }

  static double _expertScore(
    Map<String, dynamic> e,
    double? myLat,
    double? myLng,
    double? Function(double, double, double?, double?) distanceFn,
  ) {
    final int    xp         = (e['xp'] as num? ?? 0).toInt();
    final bool   hasStory   = e['hasActiveStory'] as bool? ?? false;
    final bool   isPromoted = e['isPromoted']     as bool? ?? false;

    double? distM;
    if (myLat != null && myLng != null) {
      distM = distanceFn(
        myLat, myLng,
        (e['latitude']  as num?)?.toDouble(),
        (e['longitude'] as num?)?.toDouble(),
      );
    }

    return score(
      xp:             xp,
      distanceMeters: distM,
      hasActiveStory: hasStory,
      isPromoted:     isPromoted,
    );
  }
}
