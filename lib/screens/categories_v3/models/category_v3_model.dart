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
    return CategoryV3Model(
      id: doc.id,
      name: (data['name'] as String?) ?? doc.id,
      iconUrl: (data['iconUrl'] as String?) ?? '',
      parentId: (data['parentId'] as String?) ?? '',
      order: (data['order'] as num?)?.toInt() ?? 999,
      clickCount: (data['clickCount'] as num?)?.toInt() ?? 0,
      imageUrl: data['imageUrl'] as String?,
      color: data['color'] as String?,
      legacyCsm: data['csm'] as String?,
      analytics: data['analytics'] is Map<String, dynamic>
          ? CategoryAnalytics.fromMap(
              Map<String, dynamic>.from(data['analytics'] as Map))
          : null,
      adminMeta: data['admin_meta'] is Map<String, dynamic>
          ? CategoryAdminMeta.fromMap(
              Map<String, dynamic>.from(data['admin_meta'] as Map))
          : null,
      csmModule: data['csm_module'] as String?,
      customTags: data['custom_tags'] is List
          ? List<String>.from(
              (data['custom_tags'] as List).whereType<String>())
          : const <String>[],
    );
  }
}

/// Cached metric aggregate written by `updateCategoryAnalytics` CF.
class CategoryAnalytics {
  CategoryAnalytics({
    this.views30d,
    this.clicks30d,
    this.orders30d = 0,
    this.revenue30d = 0,
    this.ctr30d,
    this.growth30d = 0,
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
      revenue30d: (m['revenue_30d'] as num?)?.toDouble() ?? 0,
      ctr30d: (m['ctr_30d'] as num?)?.toDouble(),
      growth30d: (m['growth_30d'] as num?)?.toDouble() ?? 0,
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
