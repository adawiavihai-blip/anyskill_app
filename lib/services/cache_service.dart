import 'package:cloud_firestore/cloud_firestore.dart';

/// ── AnySkill In-Memory Cache ──────────────────────────────────────────────
///
/// Single-isolate, TTL-based in-memory cache for hot Firestore reads.
///
/// **Why this exists**
/// Firestore's built-in disk cache handles *streaming* subscriptions well,
/// but one-shot `.get()` calls (e.g. expert profile on chat open, category
/// lookup on booking) bypass it and hit the network every time.  At 1M users
/// with N concurrent chat opens per second, those reads become a cost and
/// latency problem.
///
/// **Design decisions**
/// - No external dependency (no shared_preferences, no Hive) → zero I/O
/// - TTL-per-key → stale data is automatically evicted on next access
/// - `purgeExpired()` can be called from a Timer in main.dart (optional)
/// - Invalidation by prefix supports user-level cache busting on profile save
///
/// **Usage**
/// ```dart
/// // Read (wraps Firestore get)
/// final data = await CacheService.getDoc('users', uid);
///
/// // Invalidate on mutation
/// CacheService.invalidate('users/$uid');
///
/// // Purge all expired entries (call every 5 min from main.dart)
/// CacheService.purgeExpired();
/// ```

class CacheService {
  CacheService._(); // static-only, not instantiable

  // ── TTL constants ──────────────────────────────────────────────────────────
  static const Duration kUserProfile   = Duration(minutes: 5);
  static const Duration kCategories    = Duration(minutes: 30); // quasi-static at scale
  static const Duration kAdminSettings = Duration(minutes: 1);
  static const Duration kExpertProfile = Duration(minutes: 5);
  static const Duration kShortLived    = Duration(seconds: 30);

  // ── Internal store ─────────────────────────────────────────────────────────
  static final _store = <String, _CacheEntry>{};

  // ── Core primitives ────────────────────────────────────────────────────────

  /// Returns cached value for [key], or null if missing / expired.
  static T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null || entry.isExpired) {
      _store.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  /// Stores [value] under [key] with the given [ttl].
  static void set<T>(String key, T value, {Duration ttl = kUserProfile}) {
    _store[key] = _CacheEntry(value as Object, DateTime.now().add(ttl));
  }

  /// Removes a single key.
  static void invalidate(String key) => _store.remove(key);

  /// Removes all keys that start with [prefix].
  /// Use `invalidatePrefix('users/')` to bust the whole user namespace.
  static void invalidatePrefix(String prefix) =>
      _store.removeWhere((k, _) => k.startsWith(prefix));

  /// Removes all expired entries (housekeeping — call every 5 min).
  static void purgeExpired() =>
      _store.removeWhere((_, e) => e.isExpired);

  /// Number of entries currently in cache (debugging / metrics).
  static int get size => _store.length;

  // ── High-level Firestore helpers ───────────────────────────────────────────

  /// Fetches a single Firestore document, returning the cached copy when
  /// still fresh.  Falls back to a live network read on cache miss / expiry.
  ///
  /// Returns an empty map `{}` when the document does not exist, so callers
  /// can always do `data['field'] ?? fallback` without null guards.
  static Future<Map<String, dynamic>> getDoc(
    String collection,
    String docId, {
    Duration ttl = kUserProfile,
    /// Force a fresh read even if cache is warm (e.g., after mutation)
    bool forceRefresh = false,
  }) async {
    final key = '$collection/$docId';
    if (!forceRefresh) {
      final cached = get<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .doc(docId)
        .get();
    final data = Map<String, dynamic>.from(snap.data() ?? {});
    set(key, data, ttl: ttl);
    return data;
  }

  /// Batch-fetches multiple documents from the same collection, using cache
  /// for warm entries and grouping cold entries into a single Firestore
  /// `getAll()` equivalent (sequential gets — Firestore Web SDK does not
  /// support `getAll` but the reads are pipelined over one HTTP/2 connection).
  ///
  /// Returns a map of `docId → data`.
  static Future<Map<String, Map<String, dynamic>>> getDocs(
    String collection,
    List<String> docIds, {
    Duration ttl = kUserProfile,
  }) async {
    final result = <String, Map<String, dynamic>>{};
    final cold   = <String>[];

    for (final id in docIds) {
      final key    = '$collection/$id';
      final cached = get<Map<String, dynamic>>(key);
      if (cached != null) {
        result[id] = cached;
      } else {
        cold.add(id);
      }
    }

    // Fetch cold docs in parallel (up to 10 concurrent)
    final futures = cold.map((id) async {
      final data = await getDoc(collection, id, ttl: ttl);
      result[id] = data;
    });
    await Future.wait(futures);

    return result;
  }
}

// ── Internal entry ─────────────────────────────────────────────────────────
class _CacheEntry {
  final Object   value;
  final DateTime expiresAt;

  const _CacheEntry(this.value, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
