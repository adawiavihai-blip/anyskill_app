/// AnySkill — AI Matchmaker Service
///
/// Calls the `matchmakerpitch` Cloud Function which:
///   1. Queries verified providers in the requested category
///   2. Ranks them using the same formula as SearchRankingService
///      (XP×0.6 + distance×0.2 + story×0.2 + online/promoted bonuses)
///   3. Calls Claude Haiku to generate a personalised Hebrew pitch
///   4. Falls back to a template pitch if the API key is absent
library;

import 'package:cloud_functions/cloud_functions.dart';
import '../constants.dart' show resolveCanonicalCategory;

// ── Data models ───────────────────────────────────────────────────────────────

class MatchedProvider {
  final String uid;
  final String name;
  final double rating;
  final double? distKm;
  final String profileImage;
  final String category;
  final String aboutMe;
  final double pricePerHour;
  final bool   isOnline;

  const MatchedProvider({
    required this.uid,
    required this.name,
    required this.rating,
    required this.distKm,
    required this.profileImage,
    required this.category,
    required this.aboutMe,
    required this.pricePerHour,
    required this.isOnline,
  });

  factory MatchedProvider.fromMap(Map<String, dynamic> m) => MatchedProvider(
    uid:          m['uid']          as String? ?? '',
    name:         m['name']         as String? ?? '',
    rating:       (m['rating']      as num?    ?? 4.5).toDouble(),
    distKm:       (m['distKm']      as num?)?.toDouble(),
    profileImage: m['profileImage'] as String? ?? '',
    category:     m['category']     as String? ?? '',
    aboutMe:      m['aboutMe']      as String? ?? '',
    pricePerHour: (m['pricePerHour'] as num?   ?? 0).toDouble(),
    isOnline:     m['isOnline']     as bool?   ?? false,
  );
}

class MatchmakerResult {
  final String           pitch;
  final MatchedProvider? topProvider;
  final int              totalMatches;

  const MatchmakerResult({
    required this.pitch,
    required this.totalMatches,
    this.topProvider,
  });

  factory MatchmakerResult.fromMap(Map<String, dynamic> m) => MatchmakerResult(
    pitch:        m['pitch']         as String? ?? '',
    totalMatches: (m['totalMatches'] as num?    ?? 0).toInt(),
    topProvider:  m['topProvider'] != null
        ? MatchedProvider.fromMap(
            Map<String, dynamic>.from(m['topProvider'] as Map))
        : null,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────

class MatchmakerService {
  MatchmakerService._();

  static final _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Returns null if no providers were found or the function fails.
  /// Never throws — callers should fall back to the plain snackbar flow.
  static Future<MatchmakerResult?> findMatch({
    required String requestText,
    required String category,
    required String clientName,
    double? clientLat,
    double? clientLng,
  }) async {
    try {
      final callable = _fn.httpsCallable(
        'matchmakerpitch',
        options: HttpsCallableOptions(
            timeout: const Duration(seconds: 20)),
      );
      // Resolve variant spellings (e.g. "מאמן כושר" → "אימון כושר") so the
      // Cloud Function queries Firestore with the canonical category name.
      final resolvedCategory = resolveCanonicalCategory(category);
      final result = await callable.call<Map<String, dynamic>>({
        'requestText': requestText,
        'category':    resolvedCategory,
        'clientName':  clientName,
        if (clientLat != null) 'clientLat': clientLat,
        if (clientLng != null) 'clientLng': clientLng,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      if ((data['pitch'] as String? ?? '').isEmpty) return null;
      return MatchmakerResult.fromMap(data);
    } catch (_) {
      // Non-fatal — caller will fall back to plain broadcast snackbar
      return null;
    }
  }
}
