/// AnyTasks 3.0 — Category Service
///
/// Fetches task categories from Firestore `anytask_categories` collection
/// with in-memory caching. Falls back to [ANYTASK_CATEGORIES] constant
/// if Firestore is unavailable.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants.dart';

class AnytaskCategoryService {
  AnytaskCategoryService._();

  static final _db = FirebaseFirestore.instance;

  /// In-memory cache of categories.
  static List<Map<String, dynamic>>? _cache;
  static DateTime? _cacheTime;

  /// Cache TTL: 30 minutes (categories are quasi-static).
  static const _cacheTtl = Duration(minutes: 30);

  /// Returns all active AnyTask categories. Uses in-memory cache,
  /// falls back to Firestore, then to the hardcoded constant.
  static Future<List<Map<String, dynamic>>> getAll() async {
    // Return cached if fresh
    if (_cache != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      return _cache!;
    }

    try {
      final snap = await _db
          .collection('anytask_categories')
          .where('isActive', isEqualTo: true)
          .orderBy('sortOrder')
          .limit(50)
          .get();

      if (snap.docs.isNotEmpty) {
        _cache = snap.docs.map((d) {
          final data = d.data();
          return <String, dynamic>{
            'id':     d.id,
            'nameHe': data['nameHe'] as String? ?? '',
            'nameEn': data['nameEn'] as String? ?? '',
            'nameEs': data['nameEs'] as String? ?? '',
            'nameAr': data['nameAr'] as String? ?? '',
            'icon':   _iconFromName(data['iconName'] as String? ?? ''),
          };
        }).toList();
        _cacheTime = DateTime.now();
        return _cache!;
      }
    } catch (e) {
      debugPrint('[AnytaskCategoryService] getAll error: $e');
    }

    // Fallback to hardcoded constant
    return ANYTASK_CATEGORIES;
  }

  /// Stream for real-time category updates (used in admin catalog).
  static Stream<QuerySnapshot> stream() {
    return _db
        .collection('anytask_categories')
        .orderBy('sortOrder')
        .limit(50)
        .snapshots();
  }

  /// Get a single category by ID.
  static Future<Map<String, dynamic>?> getById(String catId) async {
    final all = await getAll();
    try {
      return all.firstWhere((c) => c['id'] == catId);
    } catch (_) {
      return null;
    }
  }

  /// Hebrew label for a category ID.
  static String labelHe(String catId) {
    for (final cat in ANYTASK_CATEGORIES) {
      if (cat['id'] == catId) return cat['nameHe'] as String? ?? catId;
    }
    return catId;
  }

  /// Icon for a category ID (from hardcoded fallback).
  static IconData iconFor(String catId) {
    for (final cat in ANYTASK_CATEGORIES) {
      if (cat['id'] == catId) return cat['icon'] as IconData? ?? Icons.task_alt_rounded;
    }
    return Icons.task_alt_rounded;
  }

  /// Invalidate cache (e.g., after admin edits categories).
  static void invalidateCache() {
    _cache = null;
    _cacheTime = null;
  }

  /// Maps a Material icon name string to an [IconData].
  static IconData _iconFromName(String name) {
    const map = <String, IconData>{
      'camera_alt':          Icons.camera_alt_rounded,
      'camera_alt_rounded':  Icons.camera_alt_rounded,
      'local_shipping':      Icons.local_shipping_rounded,
      'local_shipping_rounded': Icons.local_shipping_rounded,
      'search':              Icons.search_rounded,
      'search_rounded':      Icons.search_rounded,
      'storefront':          Icons.storefront_rounded,
      'storefront_rounded':  Icons.storefront_rounded,
      'analytics':           Icons.analytics_rounded,
      'analytics_rounded':   Icons.analytics_rounded,
      'translate':           Icons.translate_rounded,
      'translate_rounded':   Icons.translate_rounded,
      'campaign':            Icons.campaign_rounded,
      'campaign_rounded':    Icons.campaign_rounded,
      'spellcheck':          Icons.spellcheck_rounded,
      'spellcheck_rounded':  Icons.spellcheck_rounded,
      'poll':                Icons.poll_rounded,
      'poll_rounded':        Icons.poll_rounded,
      'explore':             Icons.explore_rounded,
      'explore_rounded':     Icons.explore_rounded,
      'videocam':            Icons.videocam_rounded,
      'videocam_rounded':    Icons.videocam_rounded,
      'mic':                 Icons.mic_rounded,
      'mic_rounded':         Icons.mic_rounded,
    };
    return map[name] ?? Icons.task_alt_rounded;
  }
}
