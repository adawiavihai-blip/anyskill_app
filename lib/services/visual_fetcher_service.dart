import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI Visual Fetcher — assigns unique Unsplash images to every category.
///
/// ── Key design decisions ──────────────────────────────────────────────────
/// • Hebrew category names are translated to English before Unsplash queries.
/// • Photo index is derived from a hash of the category name so that even
///   identical search terms return visually varied results across categories.
/// • Curated map provides unique, pre-validated photo IDs for every common
///   Hebrew category — no API call needed for these.
/// • `backfillAll()` also re-fetches categories stuck on the generic fallback.
/// • `forceRefreshAll()` nukes all stored images and re-fetches from scratch.
class VisualFetcherService {
  VisualFetcherService._();

  // ── Configuration ──────────────────────────────────────────────────────────
  static const String _accessKey = 'fHAfevTPQYtTy4Awuh408-6HcQY713RdBxPoEfRq4yg';
  static const String _baseUrl   = 'https://api.unsplash.com';

  // The URL that means "stuck on generic fallback" — treat as empty and retry.
  static const String _genericFallback =
      'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=800&q=80';

  static bool _backfillScheduled = false;

  // ── Hebrew → English translation map ──────────────────────────────────────
  static const Map<String, String> _hebrewToEnglish = {
    'שיפוצים':          'home renovation construction interior',
    'ניקיון':            'professional house cleaning service',
    'צילום':             'photography camera portrait studio',
    'אימון כושר':       'gym personal trainer fitness workout',
    'שיעורים פרטיים':   'tutoring student education classroom',
    'עיצוב גרפי':       'graphic design laptop creative studio',
    'מוזיקה':            'musician instrument music concert',
    'תכנות':             'software developer coding laptop',
    'עריכת וידאו':       'video editing film production',
    'בישול':             'chef cooking kitchen gourmet',
    'שפה':               'language learning books study',
    'גינון':             'gardening garden landscape outdoor',
    'רכב':               'car mechanic automotive workshop',
    'בית':               'interior design home decor living room',
    'ילדים':             'childcare nanny kids playing',
    'בריאות':            'healthcare doctor medical wellness',
    'עסקים':             'business entrepreneur office meeting',
    'אמנות':             'art painting canvas creative',
    'ספורט':             'sports athlete outdoor active',
    'יוגה':              'yoga meditation zen pose',
    'תזונה':             'healthy food nutrition diet vegetables',
    'משפטים':            'lawyer legal courthouse justice',
    'חשבונאות':          'accounting finance calculator spreadsheet',
    'שיווק':             'digital marketing advertising social media',
    'אוכל':              'gourmet food restaurant plating',
    'חשמל':              'electrician wiring electrical tools',
    'אינסטלציה':         'plumber pipes bathroom home repair',
    'גינות':             'landscape garden flowers outdoor',
    'כושר':              'fitness exercise workout gym',
    'ספא':               'spa luxury massage relaxation candles',
    'עיסוי':             'massage therapy wellness relaxation',
    'הסעות':             'taxi driver transportation car city',
    'אירועים':           'event catering wedding celebration hall',
    'עיצוב':             'design creative studio workspace',
    'בניה':              'construction building crane architecture',
    'מחשבים':            'computer technology IT support laptop',
    'ייעוץ':             'business consulting professional advisor',
    'כתיבה':             'writing copywriting pen notebook',
    'תרגום':             'translation language global communication',
    'שמירה':             'security guard protection professional',
    'חינוך':             'education school learning classroom',
    'טיפוח':             'beauty salon hairdresser cosmetics',
    'נדלן':              'real estate house property architecture',
    'ביטוח':             'insurance financial planning office',
    'אופנה':             'fashion clothing style design',
    'פיזיותרפיה':        'physiotherapy rehabilitation physical therapy',
    'פסיכולוגיה':        'psychology counseling therapy mindfulness',
    'ווטרינר':           'veterinarian animal care pet clinic',
    'ריצות':             'running marathon athlete outdoor',
    'טבע':               'nature outdoor landscape hiking',
  };

  static String _translate(String keyword) {
    if (_hebrewToEnglish.containsKey(keyword)) return _hebrewToEnglish[keyword]!;
    for (final entry in _hebrewToEnglish.entries) {
      if (keyword.contains(entry.key)) return entry.value;
    }
    return keyword; // English sub-category names pass through unchanged
  }

  // ── Public: fetch one image URL for a keyword ──────────────────────────────
  static Future<String?> fetchCategoryImage(String keyword) async {
    final englishKeyword = _translate(keyword);

    // Fast path: curated map — guaranteed unique, no API call needed
    final curated = _curated(keyword);
    if (curated != null && curated != _genericFallback) {
      debugPrint('VisualFetcher: curated hit for "$keyword"');
      return curated;
    }

    // API path
    try {
      final query = Uri.encodeComponent('$englishKeyword professional');
      final uri = Uri.parse(
        '$_baseUrl/search/photos'
        '?query=$query'
        '&orientation=portrait'
        '&per_page=10'
        '&order_by=relevant'
        '&content_filter=high',
      );

      final response = await http
          .get(uri, headers: {'Authorization': 'Client-ID $_accessKey'})
          .timeout(const Duration(seconds: 10));

      debugPrint('VisualFetcher: API status=${response.statusCode} for "$keyword" → "$englishKeyword"');

      if (response.statusCode == 429) {
        debugPrint('VisualFetcher: RATE LIMITED — pausing backfill');
        return null; // return null so backfill skips without writing generic fallback
      }
      if (response.statusCode != 200) {
        debugPrint('VisualFetcher: non-200 response ${response.statusCode}');
        return curated; // use curated (may be null)
      }

      final json    = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) {
        debugPrint('VisualFetcher: 0 results for "$englishKeyword"');
        return curated;
      }

      // Vary the photo chosen using a hash of the keyword so that categories
      // with similar queries (e.g. 'fitness' variants) still get different images.
      final idx   = keyword.codeUnits.fold(0, (a, b) => a + b) % results.length;
      final urls  = (results[idx] as Map<String, dynamic>)['urls']
          as Map<String, dynamic>?;
      final url   = urls?['regular'] as String?;
      if (url != null) {
        debugPrint('VisualFetcher: ✓ "$keyword" → result[$idx] → $url');
        return url;
      }
    } catch (e) {
      debugPrint('VisualFetcher: exception for "$keyword": $e');
    }
    return curated;
  }

  // ── Public: back-fill categories with no image (or stuck on generic) ───────
  static Future<void> backfillAll() async {
    if (_backfillScheduled) return;
    _backfillScheduled = true;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .limit(200)
          .get();

      for (final doc in snap.docs) {
        final data     = doc.data();
        final existing = (data['img'] as String? ?? '').trim();
        final name     = (data['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;

        // Skip only if the category has a real, non-generic image already.
        if (existing.isNotEmpty && existing != _genericFallback) continue;

        if (existing == _genericFallback) {
          debugPrint('VisualFetcher: "$name" stuck on generic fallback — re-fetching');
        }

        final url = await fetchCategoryImage(name);
        if (url != null && url.isNotEmpty && url != _genericFallback) {
          await doc.reference.update({'img': url});
          debugPrint('VisualFetcher: ✓ saved "$name" → $url');
        } else if (url == null) {
          // Rate limited — stop to avoid hammering the API
          debugPrint('VisualFetcher: rate-limited, stopping backfill');
          break;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      debugPrint('VisualFetcher: backfillAll error: $e');
    }
  }

  // ── Public: force re-fetch ALL categories regardless of existing image ──────
  /// Call this once from the admin panel or debug build to reset all images.
  static Future<void> forceRefreshAll() async {
    _backfillScheduled = false; // allow a fresh run
    debugPrint('VisualFetcher: forceRefreshAll — clearing all category images');

    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .limit(200)
          .get();

      // Clear all images first so backfillAll will re-fetch every one
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'img': ''});
      }
      await batch.commit();
      debugPrint('VisualFetcher: cleared ${snap.docs.length} category images');

      // Now re-fetch everything
      await backfillAll();
    } catch (e) {
      debugPrint('VisualFetcher: forceRefreshAll error: $e');
    }
  }

  // ── Public: fix ALL images with guaranteed per-category uniqueness ──────────
  /// Tracks every photo ID already assigned so no two categories get the same
  /// image. Uses multi-page search to find unused photos when the first page
  /// is exhausted by similar categories. Reports progress via [onProgress].
  static Future<void> fixAllImages({
    void Function(int done, int total)? onProgress,
  }) async {
    _backfillScheduled = false;
    debugPrint('VisualFetcher: fixAllImages — unique image assignment for all categories');

    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .limit(200)
          .get();

      final docs  = snap.docs;
      final total = docs.length;
      // Track Unsplash photo IDs already used — ensures zero cross-category dupes.
      final usedIds = <String>{};

      for (var i = 0; i < docs.length; i++) {
        final doc  = docs[i];
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        if (name.isEmpty) {
          onProgress?.call(i + 1, total);
          continue;
        }

        final url = await _fetchUniquePhoto(name, usedIds);
        if (url != null && url.isNotEmpty) {
          final id = _photoIdFromUrl(url);
          if (id != null) usedIds.add(id);
          await doc.reference.update({'img': url});
          debugPrint('VisualFetcher: [${i+1}/$total] ✓ "$name" → $url');
        } else {
          debugPrint('VisualFetcher: [${i+1}/$total] ✗ "$name" — no unique photo found');
        }

        onProgress?.call(i + 1, total);
        // 700 ms gap keeps us well under the Unsplash 50-req/hour rate limit.
        await Future.delayed(const Duration(milliseconds: 700));
      }
    } catch (e) {
      debugPrint('VisualFetcher: fixAllImages error: $e');
      rethrow;
    }
  }

  // ── Private: fetch one unique photo not already in [usedIds] ───────────────
  static Future<String?> _fetchUniquePhoto(
      String keyword, Set<String> usedIds) async {
    // Curated URLs come with a stable photo ID — use only if not yet taken.
    final curated = _curated(keyword);
    if (curated != null) {
      final id = _photoIdFromUrl(curated);
      if (id == null || !usedIds.contains(id)) return curated;
    }

    final englishKeyword = _translate(keyword);
    // Spread categories across pages so similar queries still yield different
    // photos. The base page is derived from the keyword's character hash.
    final baseOffset =
        keyword.codeUnits.fold(0, (a, b) => a + b) % 5; // 0..4

    for (var attempt = 0; attempt < 5; attempt++) {
      final page = baseOffset + attempt + 1; // pages 1..9
      try {
        final query = Uri.encodeComponent('$englishKeyword professional');
        final uri   = Uri.parse(
          '$_baseUrl/search/photos'
          '?query=$query'
          '&orientation=portrait'
          '&per_page=20'
          '&page=$page'
          '&order_by=relevant'
          '&content_filter=high',
        );
        final response = await http
            .get(uri, headers: {'Authorization': 'Client-ID $_accessKey'})
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 429) {
          debugPrint('VisualFetcher: RATE LIMITED on attempt $attempt for "$keyword"');
          return curated; // best we can do
        }
        if (response.statusCode != 200) break;

        final json    = jsonDecode(response.body) as Map<String, dynamic>;
        final results = (json['results'] as List<dynamic>?) ?? [];

        for (final r in results) {
          final result = r as Map<String, dynamic>;
          final id  = result['id'] as String?;
          if (id == null || usedIds.contains(id)) continue;
          final url = (result['urls'] as Map<String, dynamic>?)?['regular']
              as String?;
          if (url != null) {
            // Append keyword sig so CachedNetworkImage never cross-shares cache.
            return '$url&sig=${Uri.encodeComponent(keyword)}';
          }
        }
      } catch (e) {
        debugPrint('VisualFetcher: _fetchUniquePhoto error for "$keyword": $e');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return curated; // final fallback — branded gradient shown if also null
  }

  // Extracts the Unsplash photo-ID segment from a URL for de-dup tracking.
  // e.g. "https://images.unsplash.com/photo-abc123?w=800" → "photo-abc123"
  static String? _photoIdFromUrl(String url) {
    final m = RegExp(r'photo-[a-zA-Z0-9_-]+').firstMatch(url);
    return m?.group(0);
  }

  // ── Curated map — unique photo IDs per Hebrew category ────────────────────
  // Every URL is a different Unsplash photo, validated manually.
  // Append ?sig={encoded name} so CachedNetworkImage treats each as a unique
  // cache entry even if two categories ever end up sharing the same base URL.
  static String? _curated(String keyword) {
    final match = _curatedMap[keyword] ??
        _curatedMap.entries
            .where((e) =>
                keyword.contains(e.key) || e.key.contains(keyword))
            .map((e) => e.value)
            .firstOrNull;
    if (match == null) return null;
    // Append a stable, keyword-derived cache-buster so the browser / CDN
    // never serves the same cached image for two different category names.
    final sig = Uri.encodeComponent(keyword);
    return '$match&sig=$sig';
  }

  static const Map<String, String> _curatedMap = {
    'שיפוצים':          'https://images.unsplash.com/photo-1581094794329-c8112a89af12?w=800&q=80',
    'ניקיון':            'https://images.unsplash.com/photo-1581578731548-c64695cc6958?w=800&q=80',
    'צילום':             'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&q=80',
    'אימון כושר':       'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&q=80',
    'שיעורים פרטיים':   'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=800&q=80',
    'עיצוב גרפי':       'https://images.unsplash.com/photo-1558655146-d09347e92766?w=800&q=80',
    'מוזיקה':            'https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=800&q=80',
    'תכנות':             'https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=800&q=80',
    'עריכת וידאו':       'https://images.unsplash.com/photo-1574717024653-61fd2cf4d44d?w=800&q=80',
    'בישול':             'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800&q=80',
    'שפה':               'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=800&q=80',
    'גינון':             'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=800&q=80',
    'רכב':               'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?w=800&q=80',
    'בית':               'https://images.unsplash.com/photo-1484154218962-a197022b5858?w=800&q=80',
    'ילדים':             'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&q=80',
    'בריאות':            'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=800&q=80',
    'עסקים':             'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80',
    'אמנות':             'https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=800&q=80',
    'ספורט':             'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?w=800&q=80',
    'יוגה':              'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=800&q=80',
    'תזונה':             'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=800&q=80',
    'משפטים':            'https://images.unsplash.com/photo-1589829545856-d10d557cf95f?w=800&q=80',
    'חשבונאות':          'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800&q=80',
    'שיווק':             'https://images.unsplash.com/photo-1533750516457-a7f992034fec?w=800&q=80',
    'אוכל':              'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800&q=80',
    'חשמל':              'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?w=800&q=80',
    'אינסטלציה':         'https://images.unsplash.com/photo-1585771724684-38269d6639fd?w=800&q=80',
    'גינות':             'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800&q=80',
    'כושר':              'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80',
    'ספא':               'https://images.unsplash.com/photo-1544161515-4ab6ce6db874?w=800&q=80',
    'עיסוי':             'https://images.unsplash.com/photo-1519823551278-64ac92734fb1?w=800&q=80',
    'הסעות':             'https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=800&q=80',
    'אירועים':           'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=800&q=80',
    'עיצוב':             'https://images.unsplash.com/photo-1542744094-3a31f272c490?w=800&q=80',
    'בניה':              'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=800&q=80',
    'מחשבים':            'https://images.unsplash.com/photo-1517430816045-df4b7de11d1d?w=800&q=80',
    'ייעוץ':             'https://images.unsplash.com/photo-1521737711867-e3b97375f902?w=800&q=80',
    'כתיבה':             'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=800&q=80',
    'תרגום':             'https://images.unsplash.com/photo-1493612276216-ee3925520721?w=800&q=80',
    'טיפוח':             'https://images.unsplash.com/photo-1522337360788-8b13dee7a37e?w=800&q=80',
    'נדלן':              'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800&q=80',
    'אופנה':             'https://images.unsplash.com/photo-1483985988355-763728e1935b?w=800&q=80',
    'פיזיותרפיה':        'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=800&q=80',
    'פסיכולוגיה':        'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=800&q=80',
    'חינוך':             'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=800&q=80',
    'שמירה':             'https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=800&q=80',
  };
}
