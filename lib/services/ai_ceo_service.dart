/// AnySkill — AI CEO Strategic Agent Service
///
/// Calls the `generateCeoInsight` Cloud Function which:
///   1. Collects ALL platform metrics server-side (Admin SDK — no permission issues)
///   2. Sends them to Claude Sonnet for strategic analysis
///   3. Returns: Morning Brief, 3 Recommendations, Red Flags
///
/// All data aggregation runs on the server to bypass Firestore security rules
/// that block cross-collection client-side reads.
library;

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CeoInsight {
  final String morningBrief;
  final List<String> recommendations;
  final List<String> redFlags;
  final DateTime generatedAt;

  const CeoInsight({
    required this.morningBrief,
    required this.recommendations,
    required this.redFlags,
    required this.generatedAt,
  });
}

class AiCeoService {
  AiCeoService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Calls the Cloud Function which collects metrics server-side (Admin SDK)
  /// and generates the AI CEO insight. No client-side Firestore queries needed.
  static Future<CeoInsight> generateInsight() async {
    try {
      final callable = _fn.httpsCallable(
        'generateCeoInsight',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      final result = await callable.call<Map<String, dynamic>>({});

      final data = result.data;
      return CeoInsight(
        morningBrief: data['morningBrief'] as String? ?? 'לא ניתן ליצור סיכום כרגע.',
        recommendations: List<String>.from(data['recommendations'] ?? []),
        redFlags: List<String>.from(data['redFlags'] ?? []),
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[AiCeoService] error: $e');
      return CeoInsight(
        morningBrief: 'שגיאה ביצירת הסיכום: $e',
        recommendations: [],
        redFlags: [],
        generatedAt: DateTime.now(),
      );
    }
  }
}
