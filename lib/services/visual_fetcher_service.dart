import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI Visual Fetcher — automatically assigns Unsplash background images to
/// categories and sub-categories that have no [img] field in Firestore.
///
/// ── Setup ──────────────────────────────────────────────────────────────────
/// 1. Register a free app at https://unsplash.com/developers
/// 2. Copy your Access Key and paste it into [_accessKey] below.
///    (Demo apps get 50 requests/hour — enough for all your categories.)
/// ── Copyright ──────────────────────────────────────────────────────────────
/// All Unsplash photos are released under the Unsplash License, which permits
/// free commercial use. The content_filter=high param keeps results SFW.
class VisualFetcherService {
  VisualFetcherService._();

  // ── Configuration ─────────────────────────────────────────────────────────
  // Replace with your Unsplash Access Key (free at https://unsplash.com/developers)
  static const String _accessKey = 'fHAfevTPQYtTy4Awuh408-6HcQY713RdBxPoEfRq4yg';

  static const String _baseUrl = 'https://api.unsplash.com';

  // Prevents duplicate backfill runs within the same app session.
  static bool _backfillScheduled = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetches a high-quality, commercial-use Unsplash image URL for [keyword].
  ///
  /// The query appends "professional workplace" to ensure a polished look.
  /// Returns `null` if the API key is unset or the request fails.
  // ── Hebrew → English keyword translation ───────────────────────────────────
  // Unsplash's search engine is English-only. Hebrew text returns empty results.
  // This map translates the most common Hebrew category names before querying.
  static const Map<String, String> _hebrewToEnglish = {
    'שיפוצים':         'renovation construction',
    'ניקיון':           'cleaning home service',
    'צילום':            'photography camera portrait',
    'אימון כושר':      'fitness gym personal trainer',
    'שיעורים פרטיים':  'private tutoring education classroom',
    'עיצוב גרפי':     'graphic design creative studio',
    'מוזיקה':          'music musician instrument',
    'תכנות':            'software developer programming code',
    'עריכת וידאו':     'video editing film production',
    'בישול':            'cooking chef kitchen',
    'שפה':              'language learning books education',
    'גינון':            'gardening garden landscape',
    'רכב':              'car mechanic automotive',
    'בית':              'interior design home decor',
    'ילדים':            'childcare babysitter kids',
    'בריאות':           'healthcare medical wellness',
    'עסקים':            'business consulting office professional',
    'אמנות':            'art painting creative studio',
    'ספורט':            'sports fitness athlete',
    'יוגה':             'yoga meditation wellness',
    'תזונה':            'nutrition healthy food diet',
    'משפטים':           'law legal office',
    'חשבונאות':         'accounting finance office',
    'שיווק':            'marketing digital advertising',
    'אוכל':             'food gourmet restaurant',
    'חשמל':             'electrical electrician wiring',
    'אינסטלציה':        'plumbing pipes home repair',
    'גינות':            'garden landscape outdoor',
    'כושר':             'fitness gym workout',
    'ספא':              'spa wellness massage relaxation',
    'עיסוי':            'massage therapy relaxation',
    'הסעות':            'transportation driving car',
    'אירועים':          'events catering celebration',
    'עיצוב':            'design studio creative',
    'בניה':             'construction building architect',
    'מחשבים':           'computers technology IT support',
    'ייעוץ':            'consulting business professional meeting',
    'כתיבה':            'writing copywriting content',
    'תרגום':            'translation language global',
  };

  /// Translates a Hebrew keyword to an English equivalent for Unsplash search.
  /// Falls back to the original if no translation is found.
  static String _translate(String keyword) {
    // Direct lookup
    if (_hebrewToEnglish.containsKey(keyword)) return _hebrewToEnglish[keyword]!;
    // Partial-match lookup
    for (final entry in _hebrewToEnglish.entries) {
      if (keyword.contains(entry.key)) return entry.value;
    }
    // Return the original — might be English already (AI-generated sub-category)
    return keyword;
  }

  static Future<String?> fetchCategoryImage(String keyword) async {
    if (_accessKey == 'YOUR_UNSPLASH_ACCESS_KEY' || _accessKey.isEmpty) {
      return _curated(keyword);
    }

    // Translate Hebrew → English before querying the English-only Unsplash API
    final englishKeyword = _translate(keyword);

    try {
      final query = Uri.encodeComponent('$englishKeyword professional');
      final uri = Uri.parse(
        '$_baseUrl/search/photos'
        '?query=$query'
        '&orientation=landscape'
        '&per_page=5'
        '&order_by=relevant'
        '&content_filter=high',
      );

      final response = await http
          .get(uri, headers: {'Authorization': 'Client-ID $_accessKey'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return _curated(keyword);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return _curated(keyword);

      // Pick the first result and take the "regular" resolution (≈1080px wide)
      final urls = (results[0] as Map<String, dynamic>)['urls']
          as Map<String, dynamic>?;
      final url = urls?['regular'] as String?;
      return url ?? _curated(keyword);
    } catch (e) {
      debugPrint('VisualFetcher: fetch failed for "$keyword" (→$englishKeyword): $e');
      return _curated(keyword);
    }
  }

  /// Scans every document in `categories` that has an empty or missing `img`
  /// field and back-fills it with a fetched URL. Runs once per app session.
  static Future<void> backfillAll() async {
    if (_backfillScheduled) return;
    _backfillScheduled = true;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .limit(200)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final existing = (data['img'] as String? ?? '').trim();
        if (existing.isNotEmpty) continue; // already has an image — skip

        final name = (data['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;

        final url = await fetchCategoryImage(name);
        if (url != null && url.isNotEmpty) {
          await doc.reference.update({'img': url});
          debugPrint('VisualFetcher: updated "$name" → $url');
        }

        // Respect Unsplash rate limit (50 req/hr on demo keys)
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      debugPrint('VisualFetcher: backfillAll error: $e');
    }
  }

  // ── Curated fallback map ────────────────────────────────────────────────────
  // High-quality Unsplash photos (free commercial license) for common keywords.
  // Used when no API key is configured or as an instant result before the API
  // responds.
  static const Map<String, String> _curatedMap = {
    'שיפוצים':        'https://images.unsplash.com/photo-1581094794329-c8112a89af12?w=800&q=80',
    'ניקיון':          'https://images.unsplash.com/photo-1581578731548-c64695cc6958?w=800&q=80',
    'צילום':           'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&q=80',
    'אימון כושר':     'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&q=80',
    'שיעורים פרטיים': 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=800&q=80',
    'עיצוב גרפי':    'https://images.unsplash.com/photo-1558655146-d09347e92766?w=800&q=80',
    'מוזיקה':         'https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=800&q=80',
    'תכנות':           'https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=800&q=80',
    'עריכת וידאו':    'https://images.unsplash.com/photo-1574717024653-61fd2cf4d44d?w=800&q=80',
    'בישול':           'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800&q=80',
    'שפה':             'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=800&q=80',
    'גינון':           'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=800&q=80',
    'רכב':             'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?w=800&q=80',
    'בית':             'https://images.unsplash.com/photo-1484154218962-a197022b5858?w=800&q=80',
    'ילדים':           'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&q=80',
    'בריאות':          'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=800&q=80',
    'עסקים':           'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=80',
    'אמנות':           'https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=800&q=80',
    'ספורט':           'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?w=800&q=80',
    'יוגה':            'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=800&q=80',
    'תזונה':           'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=800&q=80',
    'משפטים':          'https://images.unsplash.com/photo-1589829545856-d10d557cf95f?w=800&q=80',
    'חשבונאות':        'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800&q=80',
    'שיווק':           'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=800&q=80',
    'אוכל':            'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800&q=80',
  };

  static String? _curated(String keyword) {
    // Direct lookup
    if (_curatedMap.containsKey(keyword)) return _curatedMap[keyword];

    // Partial-match lookup — returns first entry whose key is contained in keyword
    for (final entry in _curatedMap.entries) {
      if (keyword.contains(entry.key) || entry.key.contains(keyword)) {
        return entry.value;
      }
    }

    // Generic high-quality professional abstract — always works
    return 'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=800&q=80';
  }
}
