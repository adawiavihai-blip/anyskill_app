import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/service_provider.dart';

/// Result of a paginated search — includes the data and cursor for next page.
class SearchPage {
  final List<ServiceProvider> providers;

  /// Pass this to [SearchRepository.searchByCategory] as `startAfter`
  /// to fetch the next page. Null means no more results.
  final DocumentSnapshot? cursor;

  /// True if the returned page was full (more results likely exist).
  final bool hasMore;

  const SearchPage({
    required this.providers,
    this.cursor,
    this.hasMore = false,
  });

  /// Empty result — no providers found.
  static const empty = SearchPage(providers: []);
}

/// Handles all search and discovery queries.
///
/// Cursor-based pagination ensures we never load unbounded result sets.
/// Client-side filtering handles flags that can't be efficiently indexed
/// (isHidden, isDemo) without creating composite indexes for every combo.
class SearchRepository {
  SearchRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  SearchRepository.dummy();

  late final FirebaseFirestore _db;

  static const _pageSize = 15;

  // ── Category search (primary flow) ────────────────────────────────────

  /// Fetch one page of providers in a category.
  ///
  /// [startAfter] is the cursor from a previous [SearchPage.cursor].
  /// Returns a [SearchPage] with providers and a cursor for the next page.
  Future<SearchPage> searchByCategory({
    required String categoryName,
    DocumentSnapshot? startAfter,
    int pageSize = _pageSize,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('serviceType', isEqualTo: categoryName);

    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }

    // Fetch one extra to detect if more pages exist
    q = q.limit(pageSize + 1);

    final snap = await q.get();

    final hasMore = snap.docs.length > pageSize;
    final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;

    // Client-side filter: remove hidden, banned, demo, unverified
    final providers = docs
        .map(ServiceProvider.fromFirestore)
        .where((p) => p.isSearchVisible)
        .toList();

    return SearchPage(
      providers: providers,
      cursor:    docs.isNotEmpty ? docs.last : null,
      hasMore:   hasMore,
    );
  }

  // ── Text search (name/bio matching) ───────────────────────────────────

  /// Search providers by name prefix (Hebrew-friendly).
  ///
  /// Firestore doesn't support full-text search, so this uses
  /// startAt/endAt on the name field for prefix matching.
  /// For production scale, replace with Algolia/Typesense.
  Future<SearchPage> searchByName({
    required String query,
    DocumentSnapshot? startAfter,
    int pageSize = _pageSize,
  }) async {
    if (query.trim().isEmpty) return SearchPage.empty;

    final q = query.trim();
    // Unicode trick: append a high character to create an upper bound
    // for prefix matching. Works for Hebrew, Arabic, and Latin.
    final end = '$q\uf8ff';

    Query<Map<String, dynamic>> ref = _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .orderBy('name')
        .startAt([q])
        .endAt([end]);

    if (startAfter != null) {
      ref = ref.startAfterDocument(startAfter);
    }

    ref = ref.limit(pageSize + 1);

    final snap = await ref.get();

    final hasMore = snap.docs.length > pageSize;
    final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;

    final providers = docs
        .map(ServiceProvider.fromFirestore)
        .where((p) => p.isSearchVisible)
        .toList();

    return SearchPage(
      providers: providers,
      cursor:    docs.isNotEmpty ? docs.last : null,
      hasMore:   hasMore,
    );
  }

  // ── Nearby providers (geo-filtered) ───────────────────────────────────

  /// Fetch providers within a rough bounding box.
  ///
  /// Firestore doesn't support geo-radius queries natively.
  /// This uses lat/lng range filter + client-side distance calc.
  /// For production: use GeoFlutterFire2 or server-side geohash.
  Future<SearchPage> searchNearby({
    required double lat,
    required double lng,
    double radiusKm = 15,
    String? categoryName,
    int pageSize = _pageSize,
  }) async {
    // Rough bounding box (1 degree ≈ 111 km)
    final delta = radiusKm / 111.0;
    final minLat = lat - delta;
    final maxLat = lat + delta;

    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('latitude', isGreaterThanOrEqualTo: minLat)
        .where('latitude', isLessThanOrEqualTo: maxLat)
        .limit(pageSize);

    if (categoryName != null && categoryName.isNotEmpty) {
      q = q.where('serviceType', isEqualTo: categoryName);
    }

    final snap = await q.get();

    final providers = snap.docs
        .map(ServiceProvider.fromFirestore)
        .where((p) {
          if (!p.isSearchVisible) return false;
          if (!p.hasLocation) return false;
          // Client-side distance filter (rough, not Haversine — good enough for filtering)
          final dLng = (p.longitude! - lng).abs();
          return dLng <= delta; // longitude check (latitude already filtered by query)
        })
        .toList();

    return SearchPage(
      providers: providers,
      cursor:    snap.docs.isNotEmpty ? snap.docs.last : null,
      hasMore:   snap.docs.length >= pageSize,
    );
  }

  // ── Online providers (real-time) ──────────────────────────────────────

  /// Stream of online providers in a category (for "available now" badge).
  Stream<List<ServiceProvider>> watchOnline({String? categoryName}) {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('isOnline', isEqualTo: true)
        .limit(50);

    if (categoryName != null && categoryName.isNotEmpty) {
      q = q.where('serviceType', isEqualTo: categoryName);
    }

    return q.snapshots().map((snap) => snap.docs
        .map(ServiceProvider.fromFirestore)
        .where((p) => p.isSearchVisible)
        .toList());
  }

  // ── Suggestion / autocomplete ─────────────────────────────────────────

  /// Quick suggestion list (3-5 results) for search-as-you-type.
  Future<List<ServiceProvider>> suggest(String query, {int limit = 5}) async {
    if (query.trim().length < 2) return const [];

    final page = await searchByName(query: query, pageSize: limit);
    return page.providers;
  }
}
