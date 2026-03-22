/// AnySkill — Business Coach Service
///
/// Wraps the `analyzeProviderProfile` Cloud Function.
/// Provides typed models, CF invocation, and Firestore cache reads.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class CoachingTip {
  final String icon;
  final String text;
  final String priority; // 'high' | 'medium' | 'low'

  const CoachingTip({
    required this.icon,
    required this.text,
    required this.priority,
  });

  factory CoachingTip.fromMap(Map<String, dynamic> m) => CoachingTip(
    icon:     m['icon']     as String? ?? '💡',
    text:     m['text']     as String? ?? '',
    priority: m['priority'] as String? ?? 'medium',
  );
}

class CoachingResult {
  final String          summary;
  final int             scorePct;
  final List<CoachingTip> tips;
  final DateTime?       updatedAt;

  const CoachingResult({
    required this.summary,
    required this.scorePct,
    required this.tips,
    this.updatedAt,
  });

  factory CoachingResult.fromMap(Map<String, dynamic> m) {
    final rawTips = m['tips'] as List? ?? [];
    final ts      = m['updatedAt'];
    return CoachingResult(
      summary:   m['summary']  as String? ?? '',
      scorePct:  ((m['scorePct'] as num?) ?? 0).toInt().clamp(0, 100),
      tips:      rawTips
          .map((t) => CoachingTip.fromMap(Map<String, dynamic>.from(t as Map)))
          .toList(),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class BusinessCoachService {
  BusinessCoachService._();

  static final _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Calls `analyzeProviderProfile` CF to (re)generate tips.
  /// The CF caches the result in users/{uid}.aiCoachingTips for 24 h.
  /// Returns null on any error — callers should fall back gracefully.
  static Future<CoachingResult?> analyze() async {
    try {
      final callable = _fn.httpsCallable(
        'analyzeProviderProfile',
        options: HttpsCallableOptions(
            timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({});
      final data   = Map<String, dynamic>.from(result.data as Map);
      if ((data['tips'] as List? ?? []).isEmpty) return null;
      return CoachingResult.fromMap(data);
    } catch (e) {
      debugPrint('BusinessCoachService.analyze error: $e');
      return null;
    }
  }

  /// Reads cached coaching tips from Firestore (no CF call).
  /// Returns null if no tips are stored or they are older than [maxAgeHours].
  static Future<CoachingResult?> getCached(
      String uid, {int maxAgeHours = 48}) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = (doc.data() ?? {})['aiCoachingTips']
          as Map<String, dynamic>?;
      if (raw == null) return null;
      final result = CoachingResult.fromMap(raw);
      if (result.updatedAt != null &&
          DateTime.now().difference(result.updatedAt!).inHours > maxAgeHours) {
        return null; // stale
      }
      return result;
    } catch (e) {
      debugPrint('BusinessCoachService.getCached error: $e');
      return null;
    }
  }
}
