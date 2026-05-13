import 'package:geolocator/geolocator.dart';
import '../models/filter_schema.dart';

/// מסנן רשימת נותני שירות לפי שאילתת שם, מחיר, דירוג, ורדיוס מיקום.
///
/// [query]          — חיפוש חופשי לפי שם (לא רגיש לרישיות, ריק = ללא סינון)
/// [underHundred]   — אם true, מסנן רק נותני שירות עם pricePerHour < 100
/// [minRating]      — דירוג מינימלי (0 = ללא סינון)
/// [maxPricePerHour]— מחיר מקסימלי (null = ללא הגבלה)
/// [maxDistanceKm]  — רדיוס מקסימלי בק"מ (null = ללא הגבלה)
/// [myPosition]     — המיקום הנוכחי של הלקוח (נדרש אם maxDistanceKm != null)
/// [onlineOnly]     — (v12.9.0) אם true, מציג רק נותני שירות עם `isOnline == true`
/// [schema]         — (v15.x §50, stage 5) FilterSchema של הקטגוריה הנוכחית.
///                    משמש למיפוי dynamicFilters[sectionId] → providerField.
/// [dynamicFilters] — (v15.x §50, stage 5) Map של פילטרים מ-DynamicFilterSheet.
///                    מתעלם אם null/ריק או אם schema לא הועבר.
List<Map<String, dynamic>> filterExperts(
  List<Map<String, dynamic>> experts, {
  String query = '',
  bool underHundred = false,
  double minRating = 0,
  double? maxPricePerHour,
  double? maxDistanceKm,
  Position? myPosition,
  bool onlineOnly = false,
  FilterSchema? schema,
  Map<String, dynamic>? dynamicFilters,
}) {
  var result = experts.where((data) {
    // סינון שם
    if (query.isNotEmpty) {
      final name = (data['name'] ?? '').toString().toLowerCase();
      if (!name.contains(query.toLowerCase())) return false;
    }

    // סינון מחיר (מתחת ל-100)
    final price = (data['pricePerHour'] is num)
        ? (data['pricePerHour'] as num).toDouble()
        : double.tryParse(data['pricePerHour']?.toString() ?? '') ?? 9999.0;
    if (underHundred && price >= 100) return false;

    // סינון מחיר מקסימלי (slider)
    if (maxPricePerHour != null && price > maxPricePerHour) return false;

    // סינון דירוג מינימלי
    if (minRating > 0) {
      final rating = (data['rating'] is num)
          ? (data['rating'] as num).toDouble()
          : double.tryParse(data['rating']?.toString() ?? '') ?? 0.0;
      if (rating < minRating) return false;
    }

    // סינון רדיוס מיקום
    if (maxDistanceKm != null && myPosition != null) {
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final distMeters = Geolocator.distanceBetween(
          myPosition.latitude, myPosition.longitude, lat, lng,
        );
        if (distMeters > maxDistanceKm * 1000) return false;
      }
      // If provider has no location, don't filter them out — they just won't
      // benefit from the proximity sort.
    }

    // Online-only filter (v12.9.0)
    if (onlineOnly && data['isOnline'] != true) return false;

    return true;
  }).toList();

  // Stage 5 (CLAUDE.md §50): apply schema-driven dynamic filters.
  // No-op if either schema or dynamicFilters is missing — keeps every
  // existing call site working unchanged.
  if (schema != null &&
      dynamicFilters != null &&
      dynamicFilters.isNotEmpty) {
    result = _applyDynamicFilters(result, schema, dynamicFilters);
  }

  return result;
}

// ── Dynamic filters (v15.x §50) ────────────────────────────────────────────
//
// Schema-aware applier. For every active filter:
//   1. Look up its FilterSection in the schema.
//   2. Resolve the section's `providerField` (supports dotted paths like
//      `pestControlProfile.pestTypes`).
//   3. Compare the provider's value against the filter's value, dispatching
//      on the FilterSection's TYPE — NOT its sectionId. This way new sections
//      added to a category in Firestore "just work" without touching this code.
//
// Sections without a `providerField` are skipped (they're informational —
// e.g. banner sections never filter anything).
List<Map<String, dynamic>> _applyDynamicFilters(
  List<Map<String, dynamic>> experts,
  FilterSchema schema,
  Map<String, dynamic> filters,
) {
  // Build a quick id→section index. Sections without a providerField are
  // dropped here so the per-expert loop is cheap.
  final activeSections = <FilterSection>[];
  for (final entry in filters.entries) {
    final section = _findSection(schema, entry.key);
    if (section == null) continue;
    if (section.type == FilterSectionType.banner) continue;
    if ((section.providerField ?? '').isEmpty &&
        section.type != FilterSectionType.daysTime) {
      continue;
    }
    activeSections.add(section);
  }
  if (activeSections.isEmpty) return experts;

  return experts.where((expert) {
    for (final section in activeSections) {
      final value = filters[section.id];
      if (!_matchesSection(expert, section, value)) return false;
    }
    return true;
  }).toList();
}

FilterSection? _findSection(FilterSchema schema, String id) {
  for (final s in schema.sections) {
    if (s.id == id) return s;
  }
  return null;
}

/// Resolves a dotted path like `pestControlProfile.pestTypes` against a
/// nested map. Returns null if any segment is missing or not a map.
dynamic _resolvePath(Map<String, dynamic> data, String? path) {
  if (path == null || path.isEmpty) return null;
  final parts = path.split('.');
  dynamic current = data;
  for (final part in parts) {
    if (current is Map) {
      current = current[part];
    } else {
      return null;
    }
    if (current == null) return null;
  }
  return current;
}

/// Per-section matcher. Dispatches on `section.type` so adding a new section
/// to Firestore (with a known type) doesn't require changing this file.
bool _matchesSection(
  Map<String, dynamic> expert,
  FilterSection section,
  dynamic value,
) {
  switch (section.type) {
    case FilterSectionType.cards:
      // Single-select: value is String. Multi-select: value is Set<String>.
      // The provider's stored value can be either a String, a List, or a
      // single boolean flag (e.g. `isVerified == true`). Match if any
      // selected value equals/is-contained-in the provider value.
      final selected = _asStringSet(value);
      if (selected.isEmpty) return true;
      return _providerHasAnyOf(expert, section.providerField, selected);

    case FilterSectionType.chips:
      // Always multi-select. Match if at least one selected chip is in the
      // provider's array (logical OR across selections — same UX as Airbnb).
      final selected = _asStringSet(value);
      if (selected.isEmpty) return true;
      return _providerHasAnyOf(expert, section.providerField, selected);

    case FilterSectionType.switches:
      // Multi-select. Each enabled switch is a REQUIREMENT — provider must
      // have ALL of them (logical AND). Compatible with two storage shapes:
      //   1. Each option's `value` is a top-level bool field on the user doc
      //      (e.g. `hasInsurance: true`)
      //   2. The providerField points to an array (e.g. `categoryTags`) and
      //      each switch value should be present in it.
      final required = _asStringSet(value);
      if (required.isEmpty) return true;
      for (final flag in required) {
        if (!_providerHasFlag(expert, section.providerField, flag)) {
          return false;
        }
      }
      return true;

    case FilterSectionType.price:
      final raw = _resolvePath(expert, section.providerField);
      final price = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '') ?? 0.0;
      if (value is Map) {
        final from = (value['from'] as num?)?.toDouble() ?? 0;
        final to = (value['to'] as num?)?.toDouble() ?? double.infinity;
        if (price < from || price > to) return false;
      }
      return true;

    case FilterSectionType.rating:
      if (value is num && value > 0) {
        final raw = _resolvePath(expert, section.providerField ?? 'rating');
        final rating = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ?? 0.0;
        if (rating < value.toDouble()) return false;
      }
      return true;

    case FilterSectionType.daysTime:
      // value is `{days?: Set<int>, times?: Set<String>}`. We check against
      // the provider's `workingHours` map keyed by day-of-week (0..6).
      // If any day is selected, at least ONE of those days must exist in
      // workingHours. (Time-of-day filtering is currently not enforced —
      // requires extending the workingHours schema; for now the chip is
      // treated as a soft filter that only days are enforced.)
      if (value is! Map) return true;
      final days = _asIntSet(value['days']);
      if (days.isEmpty) return true;
      final workingHours = expert['workingHours'];
      if (workingHours is! Map) return false;
      for (final d in days) {
        if (workingHours.containsKey(d.toString()) ||
            workingHours.containsKey(d)) {
          return true;
        }
      }
      return false;

    case FilterSectionType.banner:
      return true;
  }
}

bool _providerHasAnyOf(
  Map<String, dynamic> expert,
  String? providerField,
  Set<String> selected,
) {
  if (providerField == null || providerField.isEmpty) return true;
  final raw = _resolvePath(expert, providerField);
  if (raw is List) {
    final providerSet = raw.map((e) => e.toString()).toSet();
    return selected.any(providerSet.contains);
  }
  if (raw is String) return selected.contains(raw);
  return false;
}

bool _providerHasFlag(
  Map<String, dynamic> expert,
  String? providerField,
  String flag,
) {
  // Try array-style first: providerField points to a List, check membership.
  if (providerField != null && providerField.isNotEmpty) {
    final raw = _resolvePath(expert, providerField);
    if (raw is List) {
      return raw.map((e) => e.toString()).contains(flag);
    }
  }
  // Fallback: top-level boolean flag (e.g. expert['hasInsurance'] == true).
  return expert[flag] == true;
}

Set<String> _asStringSet(dynamic v) {
  if (v == null) return const {};
  if (v is Set) return v.map((e) => e.toString()).toSet();
  if (v is List) return v.map((e) => e.toString()).toSet();
  if (v is String) return {v};
  return const {};
}

Set<int> _asIntSet(dynamic v) {
  if (v == null) return const {};
  if (v is Set) return v.map((e) => e is int ? e : int.tryParse('$e') ?? -1).where((e) => e >= 0).toSet();
  if (v is List) return v.map((e) => e is int ? e : int.tryParse('$e') ?? -1).where((e) => e >= 0).toSet();
  return const {};
}
