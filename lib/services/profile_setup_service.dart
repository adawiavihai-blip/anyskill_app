// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ai_analysis_service.dart';
import 'visual_fetcher_service.dart';

/// Result returned by [ProfileSetupService.classifyAndResolve].
class ClassifyResult {
  /// The canonical category name to save on the expert's user document.
  final String categoryName;

  /// True when no existing category matched and a new one was created.
  final bool isNewCategory;

  const ClassifyResult({
    required this.categoryName,
    required this.isNewCategory,
  });
}

/// Smart onboarding service for expert registration.
///
/// Given a free-text service description (Hebrew or English):
///   1. Runs [AiAnalysisService.analyze] to extract a category suggestion.
///   2. Fuzzy-matches the suggestion against all existing Firestore categories.
///   3. If a match is found → returns it (no Firestore write).
///   4. If no match → creates a new top-level category in Firestore and
///      fetches a unique hero image via [VisualFetcherService].
class ProfileSetupService {
  ProfileSetupService._();

  static final _db = FirebaseFirestore.instance;

  // ── Public entry point ─────────────────────────────────────────────────────

  /// Classifies [description] and resolves to an existing or newly-created
  /// category name.  Never throws — falls back to the raw suggested name on
  /// any Firestore / network error.
  static Future<ClassifyResult> classifyAndResolve(String description) async {
    if (description.trim().isEmpty) {
      return const ClassifyResult(categoryName: '', isNewCategory: false);
    }

    // 1. Ask the AI to suggest a category name
    final analysis = AiAnalysisService.analyze(description);
    final suggested = (analysis.suggestedCategory ?? '').trim();

    if (suggested.isEmpty) {
      // AI could not classify — return empty so UI can prompt user to pick manually
      return const ClassifyResult(categoryName: '', isNewCategory: false);
    }

    // 2. Fetch all current top-level Firestore categories
    final existingCategories = await _fetchTopLevelCategories();

    // 3. Try to find a fuzzy match
    final matched = _fuzzyMatch(suggested, existingCategories);
    if (matched != null) {
      return ClassifyResult(categoryName: matched, isNewCategory: false);
    }

    // 4. No match — create the new category
    final newName = suggested;
    await _createCategory(newName);
    return ClassifyResult(categoryName: newName, isNewCategory: true);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<List<String>> _fetchTopLevelCategories() async {
    try {
      final snap = await _db
          .collection('categories')
          .where('parentId', isEqualTo: '')
          .limit(200)
          .get();
      return snap.docs
          .map((d) => (d.data()['name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ProfileSetupService: failed to fetch categories: $e');
      return [];
    }
  }

  /// Case-insensitive partial match.
  /// Returns the existing name if [suggested] is a substring of it or vice-versa.
  static String? _fuzzyMatch(String suggested, List<String> existing) {
    final s = suggested.toLowerCase();
    for (final name in existing) {
      final n = name.toLowerCase();
      if (n == s || n.contains(s) || s.contains(n)) return name;
    }
    return null;
  }

  /// Creates a new top-level category document in Firestore and fetches a
  /// unique hero image for it via [VisualFetcherService].
  static Future<void> _createCategory(String name) async {
    try {
      // Determine the next `order` value so the new category goes to the end
      final countSnap = await _db
          .collection('categories')
          .where('parentId', isEqualTo: '')
          .get();
      final nextOrder = countSnap.docs.length;

      // Fetch a unique image (best-effort — null is fine, backfill will fill later)
      final imgUrl = await VisualFetcherService.fetchCategoryImage(name);

      await _db.collection('categories').add({
        'name':         name,
        'parentId':     '',
        'order':        nextOrder,
        'img':          imgUrl ?? '',
        'iconName':     'work_outline',  // generic fallback icon
        'bookingCount': 0,
        'createdAt':    FieldValue.serverTimestamp(),
        'autoCreated':  true,            // flag for admin review
      });

      debugPrint('ProfileSetupService: created new category "$name" (order=$nextOrder)');
    } catch (e) {
      debugPrint('ProfileSetupService: failed to create category "$name": $e');
    }
  }
}
