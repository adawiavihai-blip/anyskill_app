import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/category_specs_widget.dart' show ServiceSchema;
import 'cache_service.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// CachedReaders — typed convenience wrappers on top of [CacheService].
///
/// Codifies the right (path, TTL, parser) tuple for the app's hottest
/// read patterns so individual screens don't reinvent it. Each reader
/// is a one-line replacement for ad-hoc Firestore .get() calls.
///
/// **Why this layer exists**
/// At 5 DAU the difference between "every screen open hits the network"
/// and "5-min cache" is invisible. At 10K DAU it's the difference
/// between $50/mo and $500/mo of Firestore reads. CLAUDE.md §17 Rule 5
/// says the same thing in policy form — this file makes it executable.
///
/// **What's covered**
/// - [adminFeePercentage] — global commission fee (1-min TTL)
/// - [serviceSchemaForCategory] — CSM v2 schema lookup (30-min TTL)
/// - [providerProfile] — user doc read (5-min TTL)
/// - [categoryByName] — category doc lookup (30-min TTL)
///
/// **What's NOT covered (intentionally)**
/// - Own-user `.snapshots()` streams — those are real-time and shouldn't
///   be cached; the StreamBuilder owns freshness.
/// - Reads inside Firestore transactions (`tx.get`) — by SDK contract
///   transactions must read fresh data; cache doesn't apply.
/// - Per-job / per-message / per-task reads — high cardinality, low
///   re-read rate; not worth caching.
///
/// **Invalidation contract**
/// Any code path that mutates a cached entity MUST call the matching
/// `invalidate*` method below. Without this, callers see stale data
/// until the natural TTL expires.
/// ═══════════════════════════════════════════════════════════════════════════

class CachedReaders {
  CachedReaders._(); // static-only

  // ── 1. Admin fee percentage ─────────────────────────────────────────────
  // Path: admin/admin/settings/settings.feePercentage
  // Used by: booking summary, commission preview, search ranking.
  // Note: NEVER use this inside a Firestore transaction — read via
  // `tx.get(adminSettingsRef)` directly there (CLAUDE.md §4.3 + §50 audit).
  // The cache is for DISPLAY/PREVIEW reads only.

  /// Returns the platform commission fraction (e.g. `0.10` = 10%).
  /// Defaults to `0.10` on any error.
  static Future<double> adminFeePercentage() async {
    try {
      final data = await CacheService.getDoc(
        'admin/admin/settings',
        'settings',
        ttl: CacheService.kAdminSettings,
      );
      final raw = data['feePercentage'];
      if (raw is num) return raw.toDouble();
      return 0.10;
    } catch (_) {
      return 0.10;
    }
  }

  /// Invalidate after the admin updates the fee in the Monetization tab.
  static void invalidateAdminSettings() =>
      CacheService.invalidate('admin/admin/settings/settings');

  // ── 2. Service schema for a category (CSM v2) ──────────────────────────
  // Used by: every expert profile open, every edit profile open, every
  // booking sheet that needs to know about depositPercent / surcharge /
  // walkTracking / dailyProof / requireVisualDiagnosis.
  //
  // Quasi-static — admin changes via Categories v3 are rare (~1/day).

  static String _schemaKey(String categoryName) => 'serviceSchema/$categoryName';

  /// Returns the [ServiceSchema] for [categoryName], cached for 30 min.
  /// Returns [ServiceSchema.empty] when the category doesn't exist.
  static Future<ServiceSchema> serviceSchemaForCategory(
    String categoryName,
  ) async {
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) return ServiceSchema.empty();

    final key = _schemaKey(trimmed);
    final cached = CacheService.get<ServiceSchema>(key);
    if (cached != null) return cached;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('name', isEqualTo: trimmed)
          .limit(1)
          .get();
      final schema = snap.docs.isEmpty
          ? ServiceSchema.empty()
          : ServiceSchema.fromRaw(snap.docs.first.data()['serviceSchema']);
      CacheService.set(key, schema, ttl: CacheService.kCategories);
      return schema;
    } catch (_) {
      // On error, return empty + DON'T cache so the next call retries.
      return ServiceSchema.empty();
    }
  }

  /// Invalidate after Categories v3 admin edits the schema for a category.
  static void invalidateServiceSchema(String categoryName) =>
      CacheService.invalidate(_schemaKey(categoryName.trim()));

  /// Invalidate every cached schema (used after a bulk migration).
  static void invalidateAllServiceSchemas() =>
      CacheService.invalidatePrefix('serviceSchema/');

  // ── 3. Provider profile (user doc) ─────────────────────────────────────
  // Used by: chat header (other user's name + avatar), search card hover,
  // public profile, expert profile preload.
  //
  // 5-min TTL strikes a balance — reviews + balance update don't need to
  // be instant on cross-screen reads (the screen with the live data has
  // its own .snapshots() stream).

  /// Returns the user doc for [uid], cached for 5 minutes.
  /// Returns `{}` when the user doesn't exist.
  ///
  /// **Testing hook (§71)**: pass a `db` (e.g. `FakeFirebaseFirestore`)
  /// to inject a fake. Defaults to `FirebaseFirestore.instance` for prod.
  static Future<Map<String, dynamic>> providerProfile(
    String uid, {
    FirebaseFirestore? db,
  }) =>
      CacheService.getDoc(
        'users',
        uid,
        ttl: CacheService.kExpertProfile,
        db: db,
      );

  /// Batched provider profile lookup — uses cache for warm uids and
  /// pipelines the cold ones in parallel. Returns `uid → data`.
  ///
  /// **Testing hook (§74)**: pass `db` to inject a fake. Same pattern as
  /// [providerProfile] (§71).
  static Future<Map<String, Map<String, dynamic>>> providerProfiles(
    List<String> uids, {
    FirebaseFirestore? db,
  }) =>
      CacheService.getDocs(
        'users',
        uids,
        ttl: CacheService.kExpertProfile,
        db: db,
      );

  /// Invalidate after the user updates their profile (edit_profile_screen)
  /// or after admin grants credit / verifies / bans.
  static void invalidateProvider(String uid) =>
      CacheService.invalidate('users/$uid');

  // ── 4. Category doc by name ────────────────────────────────────────────
  // Used by: home tab category strip render, category results screen
  // header, edit profile dropdown lookup.
  //
  // The doc ID convention is mixed (legacy: doc.id == name; new: auto-id)
  // so callers MUST query by name. We cache by name → first match.

  static String _catByNameKey(String name) => 'categoryByName/$name';

  /// Returns the category doc data + id for [categoryName], cached 30min.
  /// Returns `null` when no category exists with that name.
  static Future<({String id, Map<String, dynamic> data})?> categoryByName(
    String categoryName,
  ) async {
    final trimmed = categoryName.trim();
    if (trimmed.isEmpty) return null;

    final key = _catByNameKey(trimmed);
    final cached =
        CacheService.get<({String id, Map<String, dynamic> data})>(key);
    if (cached != null) return cached;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('name', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      final result = (id: doc.id, data: doc.data());
      CacheService.set(key, result, ttl: CacheService.kCategories);
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Invalidate after Categories v3 admin renames / edits / deletes.
  static void invalidateCategory(String categoryName) =>
      CacheService.invalidate(_catByNameKey(categoryName.trim()));

  static void invalidateAllCategories() {
    CacheService.invalidatePrefix('categoryByName/');
    CacheService.invalidatePrefix('serviceSchema/');
  }
}
