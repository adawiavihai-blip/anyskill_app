import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Wraps a `categories/{id}` document with v3 analytics + admin_meta + csm_module.
///
/// All v3 fields are nullable / defaulted because legacy category docs predate
/// them. Use [hasAnalytics] / [hasAdminMeta] to detect partial / full migration.
class CategoryV3Model {
  CategoryV3Model({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.parentId,
    required this.order,
    required this.clickCount,
    this.imageUrl,
    this.color,
    this.legacyCsm,
    this.analytics,
    this.adminMeta,
    this.csmModule,
    this.customTags = const [],
  });

  final String id;
  final String name;
  final String iconUrl;
  final String parentId;       // '' for root categories
  final int order;             // existing field — used as drag-reorder anchor
  final int clickCount;        // existing field — used for sparkline today
  final String? imageUrl;
  final String? color;         // hex
  final String? legacyCsm;

  // v3 additive fields:
  final CategoryAnalytics? analytics;
  final CategoryAdminMeta? adminMeta;
  final String? csmModule;     // 'cleaning' | 'massage' | 'delivery' | 'handyman' | 'pest_control' | 'fitness_trainer' | null
  final List<String> customTags;

  bool get hasAnalytics => analytics != null;
  bool get hasAdminMeta => adminMeta != null;
  bool get isRoot => parentId.isEmpty;
  bool get isPinned => adminMeta?.isPinned ?? false;
  bool get isHidden => adminMeta?.isHidden ?? false;
  bool get isCsm => csmModule != null && csmModule!.isNotEmpty;

  factory CategoryV3Model.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    // Defensive parsing: Firestore on Flutter Web returns nested maps as
    // `Map<Object?, Object?>` (NOT `Map<String, dynamic>`), so the previous
    // `is Map<String, dynamic>` check always returned false on web → analytics
    // + admin_meta were silently dropped. Use plain `is Map` here.
    final analyticsRaw = data['analytics'];
    final adminMetaRaw = data['admin_meta'];
    final tagsRaw = data['custom_tags'];

    return CategoryV3Model(
      id: doc.id,
      name: _safeString(data['name']) ?? doc.id,
      iconUrl: _safeString(data['iconUrl']) ?? '',
      parentId: _safeString(data['parentId']) ?? '',
      order: _safeInt(data['order']) ?? 999,
      clickCount: _safeInt(data['clickCount']) ?? 0,
      imageUrl: _safeString(data['imageUrl']),
      color: _safeString(data['color']),
      legacyCsm: _safeString(data['csm']),
      analytics: analyticsRaw is Map
          ? _safeAnalytics(analyticsRaw)
          : null,
      adminMeta: adminMetaRaw is Map
          ? _safeAdminMeta(adminMetaRaw)
          : null,
      csmModule: _safeString(data['csm_module']),
      customTags: tagsRaw is List
          ? List<String>.from(tagsRaw.whereType<String>())
          : const <String>[],
    );
  }

  // ── Internal safe-parse helpers (never throw) ──────────────────────────
  // Each one handles a hostile Firestore payload (wrong type, missing field,
  // web Map<Object?, Object?> nested maps) by returning a sensible default.

  static String? _safeString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static int? _safeInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static CategoryAnalytics? _safeAnalytics(Map raw) {
    try {
      // Convert Map<Object?, Object?> → Map<String, dynamic> safely.
      final m = <String, dynamic>{};
      raw.forEach((k, v) {
        if (k is String) m[k] = v;
      });
      return CategoryAnalytics.fromMap(m);
    } catch (e) {
      // ignore: avoid_print
      print('[CategoryV3] analytics parse failed: $e');
      return null;
    }
  }

  static CategoryAdminMeta? _safeAdminMeta(Map raw) {
    try {
      final m = <String, dynamic>{};
      raw.forEach((k, v) {
        if (k is String) m[k] = v;
      });
      return CategoryAdminMeta.fromMap(m);
    } catch (e) {
      // ignore: avoid_print
      print('[CategoryV3] admin_meta parse failed: $e');
      return null;
    }
  }
}

/// Cached metric aggregate written by `updateCategoryAnalytics` CF.
class CategoryAnalytics {
  CategoryAnalytics({
    this.views30d,
    this.clicks30d,
    this.orders30d = 0,
    // .0 required on double fields — dart2js treats `int` defaults passed
    // where `double` is expected as a runtime type error on Flutter Web.
    this.revenue30d = 0.0,
    this.ctr30d,
    this.growth30d = 0.0,
    this.sparkline30d = const <int>[],
    this.coverageCities = 0,
    this.activeProviders = 0,
    this.healthScore = 0,
    this.lastUpdated,
  });

  /// Nullable — TODO(categories-v3 §4 Q4-B+C): require tracking events to
  /// populate. Currently stays null and the UI shows "—".
  final int? views30d;
  final int? clicks30d;
  final int orders30d;
  final double revenue30d;
  final double? ctr30d;
  final double growth30d;       // percentage delta, can be negative
  final List<int> sparkline30d; // up to 30 daily order counts (or clickCount fallback)
  final int coverageCities;
  final int activeProviders;
  final int healthScore;        // 0-100, see §4 of spec
  final DateTime? lastUpdated;

  factory CategoryAnalytics.fromMap(Map<String, dynamic> m) {
    final ts = m['last_updated'];
    return CategoryAnalytics(
      views30d: (m['views_30d'] as num?)?.toInt(),
      clicks30d: (m['clicks_30d'] as num?)?.toInt(),
      orders30d: (m['orders_30d'] as num?)?.toInt() ?? 0,
      // IMPORTANT: `.0` required on double defaults — dart2js on Flutter Web
      // does not auto-coerce `int 0` into `double` when assigning to a
      // `double` field via `??`. Plain `?? 0` compiles fine but throws
      // `type 'int' is not a subtype of 'double'` on render when the
      // analytics field is null (which it is for a freshly-backfilled doc
      // before the scheduled CF runs).
      revenue30d: (m['revenue_30d'] as num?)?.toDouble() ?? 0.0,
      ctr30d: (m['ctr_30d'] as num?)?.toDouble(),
      growth30d: (m['growth_30d'] as num?)?.toDouble() ?? 0.0,
      sparkline30d: m['sparkline_30d'] is List
          ? (m['sparkline_30d'] as List)
              .whereType<num>()
              .map((n) => n.toInt())
              .toList()
          : const <int>[],
      coverageCities: (m['coverage_cities'] as num?)?.toInt() ?? 0,
      activeProviders: (m['active_providers'] as num?)?.toInt() ?? 0,
      healthScore: (m['health_score'] as num?)?.toInt() ?? 0,
      lastUpdated: ts is Timestamp ? ts.toDate() : null,
    );
  }

  /// Color band per spec §4 thresholds. Caller must apply theme.
  HealthBand get healthBand {
    if (healthScore >= 75) return HealthBand.good;
    if (healthScore >= 50) return HealthBand.ok;
    return HealthBand.bad;
  }

  /// Returns `true` when sparkline has ≥1 non-zero point. UI uses this to
  /// decide between rendering the chart or a flat-line placeholder.
  bool get hasMeaningfulSparkline =>
      sparkline30d.isNotEmpty && sparkline30d.any((v) => v > 0);
}

enum HealthBand { bad, ok, good }

extension HealthBandColor on HealthBand {
  Color get color {
    switch (this) {
      case HealthBand.bad:
        return const Color(0xFFEF4444); // red — Brand.error
      case HealthBand.ok:
        return const Color(0xFFF59E0B); // amber — Brand.warning
      case HealthBand.good:
        return const Color(0xFF10B981); // green — Brand.success
    }
  }
}

/// Admin-only metadata stamped on each category by [CategoriesV3Service]
/// mutations. Not exposed to customer-facing surfaces.
class CategoryAdminMeta {
  CategoryAdminMeta({
    this.isPinned = false,
    this.isHidden = false,
    this.lastEditedBy,
    this.lastEditedAt,
    this.lastEditedAction,
    this.notes = '',
  });

  final bool isPinned;
  final bool isHidden;
  final String? lastEditedBy;       // admin uid
  final DateTime? lastEditedAt;
  final String? lastEditedAction;   // 'created' | 'image_changed' | 'reordered' | etc.
  final String notes;

  factory CategoryAdminMeta.fromMap(Map<String, dynamic> m) {
    final ts = m['last_edited_at'];
    return CategoryAdminMeta(
      isPinned: (m['is_pinned'] as bool?) ?? false,
      isHidden: (m['is_hidden'] as bool?) ?? false,
      lastEditedBy: m['last_edited_by'] as String?,
      lastEditedAt: ts is Timestamp ? ts.toDate() : null,
      lastEditedAction: m['last_edited_action'] as String?,
      notes: (m['notes'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'is_pinned': isPinned,
        'is_hidden': isHidden,
        if (lastEditedBy != null) 'last_edited_by': lastEditedBy,
        if (lastEditedAt != null)
          'last_edited_at': Timestamp.fromDate(lastEditedAt!),
        if (lastEditedAction != null) 'last_edited_action': lastEditedAction,
        if (notes.isNotEmpty) 'notes': notes,
      };
}
