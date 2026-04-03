/// AnySkill — Opportunity Hunter Service
///
/// Reads today's AI-generated "Deal of the Day" from
/// daily_opportunities/{YYYY-MM-DD} and exposes it as a stream.
///
/// Also stamps users/{uid}.lastActiveAt on every app open, and
/// users/{uid}.lastSearchedCategory whenever the user taps a category,
/// so the Cloud Function can personalise dormant-client nudges.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class DailyOpportunity {
  final String headline;
  final String emoji;
  final String category;
  final String validDate; // YYYY-MM-DD

  const DailyOpportunity({
    required this.headline,
    required this.emoji,
    required this.category,
    required this.validDate,
  });

  factory DailyOpportunity.fromMap(Map<String, dynamic> m, String id) =>
      DailyOpportunity(
        headline:  m['headline']  as String? ?? '',
        emoji:     m['emoji']     as String? ?? '✨',
        category:  m['category']  as String? ?? '',
        validDate: m['validDate'] as String? ?? id,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class OpportunityHunterService {
  OpportunityHunterService._();

  /// Returns today's Firestore document key (YYYY-MM-DD, local clock).
  static String todayKey() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Live stream of today's deal.
  /// Emits null when no deal has been generated yet (before 08:00 on first run).
  static Stream<DailyOpportunity?> streamToday() {
    final key = todayKey();
    return FirebaseFirestore.instance
        .collection('daily_opportunities')
        .doc(key)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      final data     = snap.data() ?? {};
      final headline = data['headline'] as String? ?? '';
      if (headline.isEmpty) return null;
      // ── Strict same-day expiry check ────────────────────────────────
      // Only show the deal if its validDate matches today's key exactly.
      // This prevents stale "storm" / weather banners from persisting
      // if the CF regenerates with the same doc key but a past date.
      final validDate = data['validDate'] as String? ?? snap.id;
      if (validDate != key) return null;
      // Also respect an explicit expiresAt timestamp if present
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) return null;
      return DailyOpportunity.fromMap(data, snap.id);
    });
  }

  /// Stamps the user's lastActiveAt (called once on app open).
  static Future<void> markActive(String uid) async {
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('OpportunityHunterService.markActive error: $e');
    }
  }

  /// Records the category the user most recently searched / tapped.
  /// Throttled client-side: call on every category tap; the write is cheap.
  static Future<void> recordCategoryTap(String uid, String category) async {
    if (uid.isEmpty || category.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'lastSearchedCategory': category,
      });
    } catch (e) {
      debugPrint('OpportunityHunterService.recordCategoryTap error: $e');
    }
  }
}
