// Defensive Map cast for Firestore-returned maps.
//
// **Problem:** Firestore SDK on web sometimes returns nested maps as
// `Map<dynamic, dynamic>` instead of `Map<String, dynamic>`. A direct
// `as Map<String, dynamic>?` cast crashes the entire screen with
// "Null check operator used on a null value" / "Cannot read properties of
// null (reading 'toString')" — a notoriously hard-to-debug class of crash
// in Dart-on-web because the minified stack trace doesn't reveal the
// offending line.
//
// **Fix:** Use this helper in every nested-map cast pattern. It returns
// `null` for missing or non-Map values, and constructs a fresh
// `Map<String, dynamic>` from any Map shape (including
// `Map<dynamic, dynamic>` and `_InternalLinkedHashMap<dynamic, dynamic>`).
//
// **Usage:**
//   Before:  `raw['display'] as Map<String, dynamic>?`         ← unsafe
//   After:   `safeMap(raw['display'])`                         ← safe
//
// History: discovered in §51 (Banners Studio) and codified during the
// 2026-04-26 QA sweep. See CLAUDE.md §53 follow-up notes.

Map<String, dynamic>? safeMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

/// Same as [safeMap] but returns an empty map instead of null. Use when
/// downstream code expects a non-null map.
Map<String, dynamic> safeMapOrEmpty(Object? value) =>
    safeMap(value) ?? const <String, dynamic>{};
