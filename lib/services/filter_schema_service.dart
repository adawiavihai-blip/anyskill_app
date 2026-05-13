// lib/services/filter_schema_service.dart
//
// שירות לטעינת FilterSchema מ-Firestore עם cache בזיכרון.
// TTL של 30 דקות (זהה ל-CacheService שכבר קיים בפרויקט לקטגוריות).

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/filter_schema.dart';

class FilterSchemaService {
  FilterSchemaService._internal();
  static final FilterSchemaService instance = FilterSchemaService._internal();

  final Map<String, _CachedSchema> _cache = {};
  static const Duration _ttl = Duration(minutes: 30);

  /// טוען schema לקטגוריה. מחזיר fallback אם הקטגוריה לא קיימת או בלי schema.
  Future<FilterSchema> getSchema(String categoryId) async {
    // בדיקת cache
    final cached = _cache[categoryId];
    if (cached != null && !cached.isExpired) {
      return cached.schema;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('categories')
          .doc(categoryId)
          .get();

      final FilterSchema schema;
      if (!doc.exists) {
        schema = FilterSchema.fallback(categoryId, categoryId);
      } else {
        final data = doc.data() ?? {};
        if (data['filterSchema'] == null) {
          schema = FilterSchema.fallback(
            categoryId,
            data['name'] as String? ?? categoryId,
          );
        } else {
          schema = FilterSchema.fromFirestore(categoryId, data);
        }
      }

      _cache[categoryId] = _CachedSchema(schema, DateTime.now());
      return schema;
    } catch (e) {
      // נופל ל-fallback בכל מקרה של שגיאה
      return FilterSchema.fallback(categoryId, categoryId);
    }
  }

  /// מנקה cache לקטגוריה ספציפית (כשאדמין עורך)
  void invalidate(String categoryId) {
    _cache.remove(categoryId);
  }

  /// מנקה את כל ה-cache
  void clearAll() {
    _cache.clear();
  }
}

class _CachedSchema {
  final FilterSchema schema;
  final DateTime cachedAt;

  _CachedSchema(this.schema, this.cachedAt);

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > FilterSchemaService._ttl;
}
