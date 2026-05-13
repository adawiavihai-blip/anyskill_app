// Forward + structured geocoding helper for OpenStreetMap Nominatim.
//
// Three public surfaces:
//   1. [forwardGeocode] — free-text → first matching `LatLng`. Used by
//      Wolt-style map screens (flash auction, motorcycle tow) to drop a pin
//      after the user types a free-text address.
//   2. [searchStreets] — structured (city + query) → up to 8 street
//      suggestions with road/house number/lat/lng. Drives the autocomplete
//      dropdown in [AddressInput].
//   3. [reverseGeocode] — `LatLng` → structured address (road, city,
//      house number). Used when the user drags the map pin to refine the
//      typed address — we round-trip the new coordinates back into the
//      city + street fields.
//
// Nominatim usage policy
// (https://operations.osmfoundation.org/policies/nominatim/):
//   • Max 1 req/sec — every CALLER must debounce (typically 600-1000ms).
//     This service does NOT enforce its own rate limit; the shared 24h
//     cache + per-keystroke debounce on the widget side keep us well under.
//     If 429 errors appear in production logs, add a queue here.
//   • MUST send a real User-Agent header identifying the app.
//   • For high-volume traffic, host your own. Irrelevant at AnySkill's
//     current scale (single-digit DAU); flagged here for future scale.
//
// Return contract: ANY failure (timeout, 0 results, parse error, network
// error) returns `null` / empty list. Callers should treat that as "leave
// the user's free-text input alone" — NEVER crash.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One structured street suggestion from Nominatim.
class StreetSuggestion {
  /// Full human-readable address as Nominatim formatted it.
  /// Example: `"רוטשילד 10, תל אביב-יפו, ישראל"`.
  final String displayName;

  /// Street/road name only, when present.
  /// Example: `"רוטשילד"`.
  final String? road;

  /// House number, when Nominatim resolved one.
  final String? houseNumber;

  /// City/locality as Nominatim reported it.
  final String? city;

  /// Forward-geocoded latitude.
  final double? lat;

  /// Forward-geocoded longitude.
  final double? lng;

  const StreetSuggestion({
    required this.displayName,
    this.road,
    this.houseNumber,
    this.city,
    this.lat,
    this.lng,
  });

  /// What to render in the autocomplete dropdown row. Prefers
  /// `"<road> <houseNumber>"` for compactness; falls back to display name.
  String get listLabel {
    if (road != null && road!.isNotEmpty) {
      if (houseNumber != null && houseNumber!.isNotEmpty) {
        return '$road $houseNumber';
      }
      return road!;
    }
    return displayName;
  }

  /// What to write back into the street TextField when the user selects.
  /// Same as [listLabel] today; kept separate so future variants (e.g. with
  /// neighbourhood) don't bleed into the autocomplete row.
  String get fieldValue => listLabel;

  /// LatLng when both coords are present.
  LatLng? get latLng =>
      (lat != null && lng != null) ? LatLng(lat!, lng!) : null;
}

/// Simple time-stamped cache entry. Holds either a forward result, a list
/// of structured suggestions, or a reverse-geocode hit.
class _CachedEntry<T> {
  final T value;
  final DateTime fetchedAt;
  _CachedEntry(this.value) : fetchedAt = DateTime.now();
  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < GeocodingService._kCacheTtl;
}

class GeocodingService {
  static const _kBaseUrl = 'https://nominatim.openstreetmap.org/search';
  static const _kReverseUrl = 'https://nominatim.openstreetmap.org/reverse';
  static const _kUserAgent = 'AnySkill/1.0 (anyskill-6fdf3.web.app)';
  static const _kDefaultTimeout = Duration(seconds: 5);
  static const _kCacheTtl = Duration(hours: 24);
  static const _kCacheMaxEntries = 200;

  // Module-private shared cache. Key shape:
  //   - `"fwd:<q>:<cc>"`         → LatLng?
  //   - `"streets:<city>:<q>"`  → List<StreetSuggestion>
  //   - `"rev:<lat>,<lng>"`     → StreetSuggestion?
  // Insertion-order eviction (oldest entry dropped when full).
  static final Map<String, _CachedEntry<Object?>> _cache = {};

  static T? _readCache<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (!entry.isFresh) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  static void _writeCache<T>(String key, T value) {
    if (_cache.length >= _kCacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CachedEntry<Object?>(value);
  }

  /// Forward geocode: free-text address → first matching lat/lng.
  ///
  /// [countryCode] is a 2-letter ISO code (default `il` for Israel) that
  /// scopes the search — keeps Tel Aviv from accidentally matching Tel
  /// Aviv, Florida. Set to empty string to disable the country bias.
  static Future<LatLng?> forwardGeocode(
    String query, {
    String countryCode = 'il',
    String acceptLanguage = 'he,en',
    Duration timeout = _kDefaultTimeout,
  }) async {
    final q = query.trim();
    if (q.length < 3) return null;

    final cacheKey = 'fwd:$q:$countryCode';
    final cached = _readCache<LatLng?>(cacheKey);
    if (cached != null) return cached;

    final params = <String, String>{
      'format': 'json',
      'q': q,
      'limit': '1',
      'accept-language': acceptLanguage,
    };
    if (countryCode.isNotEmpty) {
      params['countrycodes'] = countryCode;
    }
    final uri = Uri.parse(_kBaseUrl).replace(queryParameters: params);

    try {
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': _kUserAgent,
          'Accept': 'application/json',
        },
      ).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! List || body.isEmpty) return null;
      final first = body.first;
      if (first is! Map) return null;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      if (lat == null || lon == null) return null;
      final result = LatLng(lat, lon);
      _writeCache(cacheKey, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Structured search: returns up to [limit] street suggestions in [city].
  ///
  /// Uses Nominatim's structured query (`street=` + `city=`) which is
  /// significantly more accurate than free-text `q=` for "street in this
  /// city" lookups. Caller is expected to debounce 300-600ms.
  ///
  /// Returns empty list on ANY failure — UI should fall back to plain
  /// free-text entry and not block the user.
  static Future<List<StreetSuggestion>> searchStreets({
    required String city,
    required String query,
    int limit = 8,
    String countryCode = 'il',
    String acceptLanguage = 'he,en',
    Duration timeout = _kDefaultTimeout,
  }) async {
    final c = city.trim();
    final q = query.trim();
    if (c.isEmpty || q.length < 2) return const [];

    final cacheKey = 'streets:$c:$q';
    final cached = _readCache<List<StreetSuggestion>>(cacheKey);
    if (cached != null) return cached;

    final params = <String, String>{
      'format': 'jsonv2',
      'street': q,
      'city': c,
      'limit': '$limit',
      'addressdetails': '1',
      'accept-language': acceptLanguage,
    };
    if (countryCode.isNotEmpty) {
      params['countrycodes'] = countryCode;
    }
    final uri = Uri.parse(_kBaseUrl).replace(queryParameters: params);

    try {
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': _kUserAgent,
          'Accept': 'application/json',
        },
      ).timeout(timeout);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body);
      if (body is! List) return const [];
      final results = <StreetSuggestion>[];
      for (final item in body) {
        if (item is! Map) continue;
        final addr = item['address'];
        final addrMap = addr is Map ? addr : const {};
        results.add(StreetSuggestion(
          displayName: '${item['display_name'] ?? ''}',
          road: _firstNonEmpty([
            addrMap['road'],
            addrMap['pedestrian'],
            addrMap['residential'],
            addrMap['neighbourhood'],
          ]),
          houseNumber: _stringOrNull(addrMap['house_number']),
          city: _firstNonEmpty([
            addrMap['city'],
            addrMap['town'],
            addrMap['village'],
            addrMap['municipality'],
          ]),
          lat: double.tryParse('${item['lat'] ?? ''}'),
          lng: double.tryParse('${item['lon'] ?? ''}'),
        ));
      }
      _writeCache(cacheKey, results);
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Reverse-geocode a [LatLng] to a structured address.
  ///
  /// Used when the user drags the map pin to refine a typed address — we
  /// round-trip the new coordinates back into the city + street fields so
  /// they stay in sync. ANY failure returns `null`; caller should leave
  /// the existing text untouched.
  static Future<StreetSuggestion?> reverseGeocode(
    LatLng pos, {
    String acceptLanguage = 'he,en',
    Duration timeout = _kDefaultTimeout,
  }) async {
    // Round to 5 decimal places (~1m) so tiny drags don't bust the cache.
    final latStr = pos.latitude.toStringAsFixed(5);
    final lngStr = pos.longitude.toStringAsFixed(5);
    final cacheKey = 'rev:$latStr,$lngStr';
    final cached = _readCache<StreetSuggestion?>(cacheKey);
    if (cached != null) return cached;

    final uri = Uri.parse(_kReverseUrl).replace(queryParameters: {
      'format': 'jsonv2',
      'lat': latStr,
      'lon': lngStr,
      'addressdetails': '1',
      'accept-language': acceptLanguage,
      'zoom': '18',
    });

    try {
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': _kUserAgent,
          'Accept': 'application/json',
        },
      ).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map) return null;
      final addr = body['address'];
      final addrMap = addr is Map ? addr : const {};
      final result = StreetSuggestion(
        displayName: '${body['display_name'] ?? ''}',
        road: _firstNonEmpty([
          addrMap['road'],
          addrMap['pedestrian'],
          addrMap['residential'],
          addrMap['neighbourhood'],
        ]),
        houseNumber: _stringOrNull(addrMap['house_number']),
        city: _firstNonEmpty([
          addrMap['city'],
          addrMap['town'],
          addrMap['village'],
          addrMap['municipality'],
        ]),
        lat: double.tryParse('${body['lat'] ?? ''}') ?? pos.latitude,
        lng: double.tryParse('${body['lon'] ?? ''}') ?? pos.longitude,
      );
      _writeCache(cacheKey, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Test/dev hook: wipe the in-memory cache.
  static void clearCache() => _cache.clear();
}

// ─── private helpers ────────────────────────────────────────────────────

String? _stringOrNull(Object? raw) {
  if (raw == null) return null;
  final s = '$raw'.trim();
  return s.isEmpty ? null : s;
}

String? _firstNonEmpty(List<Object?> candidates) {
  for (final c in candidates) {
    final s = _stringOrNull(c);
    if (s != null) return s;
  }
  return null;
}
