import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/banner_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Subcategory banner service — Phase 4 of Banners Studio.
///
/// All banners live in the same `banners/` collection (per Phase-2
/// decision — we don't fork the schema). Subcategory banners are
/// distinguished by `placement == 'subcategory'` + `subcategoryId`
/// (or `isDefaultGlobalSubcat: true`).
///
/// Phase 4 ships only the admin surface. The customer-side widget is
/// deferred until a real subcategory drill-down screen exists in the
/// app. **TODO(client-side):** when the customer's subcategory results
/// screen is built, mount [getBannersForSubcategory] in its header to
/// render the configured banner. The data layer is fully ready.
/// ═══════════════════════════════════════════════════════════════════════════
class SubcategoryBannerService {
  SubcategoryBannerService._();
  static final SubcategoryBannerService instance =
      SubcategoryBannerService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _banners =>
      _db.collection('banners');

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('categories');

  /// Live stream of EVERY subcategory-placement banner — both pinned
  /// banners (with `subcategoryId`) and the global default. The admin
  /// screen filters client-side.
  Stream<List<BannerModel>> watchAll() {
    return _banners
        .where('placement', isEqualTo: BannerType.subcategory.dbValue)
        .limit(200)
        .snapshots()
        .map(_safeMap);
  }

  /// Fetch banners that should render at the top of the given subcategory
  /// screen (customer side).
  ///
  /// Lookup priority:
  ///   1. Try to find banners pinned to this exact subcategoryId where
  ///      isActive: true. If found → return them sorted by `order`.
  ///   2. Else fall back to the global default banner (if it's active).
  ///   3. Else return an empty list (UI hides the slot).
  ///
  /// **TODO(client-side):** invoke from the customer's subcategory
  /// drill-down screen header once that screen ships. Data layer is
  /// ready and tested via the admin UI.
  Future<List<BannerModel>> getBannersForSubcategory(
      String subcategoryId) async {
    if (subcategoryId.isEmpty) return const [];
    final pinned = await _banners
        .where('placement', isEqualTo: BannerType.subcategory.dbValue)
        .where('subcategoryId', isEqualTo: subcategoryId)
        .where('isActive', isEqualTo: true)
        .limit(20)
        .get();
    if (pinned.docs.isNotEmpty) {
      final list = pinned.docs.map(BannerModel.fromDoc).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    }
    final defaults = await _banners
        .where('placement', isEqualTo: BannerType.subcategory.dbValue)
        .where('isDefaultGlobalSubcat', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    return defaults.docs.map(BannerModel.fromDoc).toList();
  }

  /// One-shot snapshot of the categories tree — root categories
  /// (parentId == '') + all subcategories. Used by the admin screen to
  /// build the accordion.
  Future<CategoryTree> loadCategoryTree() async {
    final snap = await _categories.limit(500).get();
    final roots = <_CatNode>[];
    final byParent = <String, List<_CatNode>>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final node = _CatNode(
        id: doc.id,
        name: (d['name'] as String?) ?? doc.id,
        parentId: (d['parentId'] as String?) ?? '',
        order: (d['order'] as num?)?.toInt() ?? 999,
        iconUrl: (d['iconUrl'] as String?) ?? '',
        emoji: _detectEmoji(d),
      );
      if (node.parentId.isEmpty) {
        roots.add(node);
      } else {
        (byParent[node.parentId] ??= <_CatNode>[]).add(node);
      }
    }
    roots.sort((a, b) => a.order.compareTo(b.order));
    final categoryNodes = <CategoryNode>[];
    for (final r in roots) {
      final subs = (byParent[r.id] ?? const <_CatNode>[]).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      categoryNodes.add(
        CategoryNode(
          id: r.id,
          name: r.name,
          emoji: r.emoji,
          subcategories: [
            for (final s in subs)
              SubcategoryNode(
                id: s.id,
                name: s.name,
                parentId: r.id,
                emoji: s.emoji,
              ),
          ],
        ),
      );
    }
    return CategoryTree(categories: categoryNodes);
  }

  static String _detectEmoji(Map<String, dynamic> d) {
    // Some category docs store an emoji in `iconEmoji` or `emoji`. If
    // neither is present, guess from the name's first non-Hebrew char.
    final ie = d['iconEmoji'] as String?;
    if (ie != null && ie.isNotEmpty) return ie;
    final em = d['emoji'] as String?;
    if (em != null && em.isNotEmpty) return em;
    return '📁';
  }

  static List<BannerModel> _safeMap(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final out = <BannerModel>[];
    for (final doc in snap.docs) {
      try {
        out.add(BannerModel.fromDoc(doc));
      } catch (e) {
        // ignore: avoid_print
        print('[SubcatBannerService] Skipped doc "${doc.id}": $e');
      }
    }
    return out;
  }
}

/// Internal aggregate of categories + their subcategories.
class CategoryTree {
  final List<CategoryNode> categories;
  const CategoryTree({required this.categories});

  int get totalSubcategories =>
      categories.fold(0, (a, c) => a + c.subcategories.length);
}

class CategoryNode {
  final String id;
  final String name;
  final String emoji;
  final List<SubcategoryNode> subcategories;

  const CategoryNode({
    required this.id,
    required this.name,
    required this.emoji,
    required this.subcategories,
  });
}

class SubcategoryNode {
  final String id;
  final String name;
  final String parentId;
  final String emoji;

  const SubcategoryNode({
    required this.id,
    required this.name,
    required this.parentId,
    required this.emoji,
  });
}

class _CatNode {
  final String id;
  final String name;
  final String parentId;
  final int order;
  final String iconUrl;
  final String emoji;
  const _CatNode({
    required this.id,
    required this.name,
    required this.parentId,
    required this.order,
    required this.iconUrl,
    required this.emoji,
  });
}
