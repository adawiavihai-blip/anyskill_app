import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category_v3_model.dart';

/// Read-side helper for category analytics. The cache is owned by the
/// `updateCategoryAnalytics` Cloud Function (every 15 min). This service
/// only EXPOSES the data + provides UI-helpful aggregates.
///
/// Per Q4-B+C decision (CLAUDE.md plan, Phase A):
///   - orders_30d / revenue_30d are real (sourced from `jobs` collection)
///   - sparkline_30d is a fallback synthesised from `clickCount` history
///   - views_30d / clicks_30d are LEFT NULL until tracking infra ships later;
///     the UI shows "—" placeholders.
class CategoryAnalyticsService {
  CategoryAnalyticsService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Live KPI dashboard derivation. Counts categories that match each KPI
  /// criterion. Designed to be O(N) over a single in-memory list — N is at
  /// most 200 (the watchAll() limit), so we don't issue extra Firestore reads.
  CategoriesKpis computeKpis(List<CategoryV3Model> all) {
    final root = all.where((c) => c.isRoot).toList();
    final sub = all.where((c) => !c.isRoot).toList();
    final missingImage = root
        .where((c) => (c.imageUrl ?? '').isEmpty && c.iconUrl.isEmpty)
        .length;
    final noProviders = root
        .where((c) => (c.analytics?.activeProviders ?? 0) == 0)
        .length;
    final inCsm = root.where((c) => c.isCsm).length;
    return CategoriesKpis(
      totalCategories: root.length,
      totalSubcategories: sub.length,
      missingImageCount: missingImage,
      noProvidersCount: noProviders,
      inCsmCount: inCsm,
    );
  }

  /// Average health score across all root categories (excludes hidden).
  /// Returns null if there are no eligible categories.
  double? averageHealthScore(List<CategoryV3Model> all) {
    final eligible = all
        .where((c) => c.isRoot && !c.isHidden && c.hasAnalytics)
        .toList();
    if (eligible.isEmpty) return null;
    final sum = eligible.fold<int>(
        0, (acc, c) => acc + (c.analytics?.healthScore ?? 0));
    return sum / eligible.length;
  }

  /// Last-update timestamp across the whole list. The UI uses this to render
  /// a "מעודכן לפני X דקות" hint in the toolbar.
  DateTime? mostRecentUpdate(List<CategoryV3Model> all) {
    DateTime? best;
    for (final c in all) {
      final t = c.analytics?.lastUpdated;
      if (t == null) continue;
      if (best == null || t.isAfter(best)) best = t;
    }
    return best;
  }

  /// Used by the in-row sparkline. Always returns a 30-element list.
  /// Pads the head with zeros if the cached series is shorter.
  List<int> sparklineForDisplay(CategoryV3Model c) {
    final data = c.analytics?.sparkline30d ?? const <int>[];
    if (data.length >= 30) return data.sublist(data.length - 30);
    return List<int>.filled(30 - data.length, 0) + data;
  }

  /// One-shot read used by Edit dialog "stats" tab.
  Future<CategoryAnalytics?> readAnalyticsOnce(String categoryId) async {
    final doc = await _db.collection('categories').doc(categoryId).get();
    if (!doc.exists) return null;
    final raw = doc.data()?['analytics'];
    if (raw is! Map) return null;
    return CategoryAnalytics.fromMap(Map<String, dynamic>.from(raw));
  }
}

/// Aggregated counts for the 5 KPI cards strip (spec §7.1 row 2).
class CategoriesKpis {
  const CategoriesKpis({
    required this.totalCategories,
    required this.totalSubcategories,
    required this.missingImageCount,
    required this.noProvidersCount,
    required this.inCsmCount,
  });

  final int totalCategories;
  final int totalSubcategories;
  final int missingImageCount;
  final int noProvidersCount;
  final int inCsmCount;

  static const empty = CategoriesKpis(
    totalCategories: 0,
    totalSubcategories: 0,
    missingImageCount: 0,
    noProvidersCount: 0,
    inCsmCount: 0,
  );
}
