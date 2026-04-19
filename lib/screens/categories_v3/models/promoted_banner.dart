import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in `promoted_banners/{bannerId}`. Per Q5-A this collection is a
/// **read-only mirror** during Phase A-B — the live home_tab still renders the
/// AnyTasks + נתינה מהלב banners from hardcoded values per CLAUDE.md §35.
/// Editing here updates the doc but does NOT yet flow to the customer screen.
class PromotedBanner {
  PromotedBanner({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
    required this.position,
    required this.displayOrder,
    required this.isActive,
    required this.linkTarget,
    this.analytics,
    this.lastEditedBy,
    this.lastEditedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final BannerType type;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final String icon;          // emoji or storage URL
  final String gradientStart; // hex
  final String gradientEnd;
  final BannerPosition position;
  final int displayOrder;
  final bool isActive;
  final String linkTarget;    // route name, e.g. '/anytasks'
  final BannerAnalytics? analytics;
  final String? lastEditedBy;
  final DateTime? lastEditedAt;
  final DateTime createdAt;

  factory PromotedBanner.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final adminMeta = data['admin_meta'] is Map
        ? Map<String, dynamic>.from(data['admin_meta'] as Map)
        : <String, dynamic>{};
    final createdTs = data['created_at'];
    final editedTs = adminMeta['last_edited_at'];
    return PromotedBanner(
      id: doc.id,
      type: _parseType(data['type'] as String?),
      title: (data['title'] as String?) ?? '',
      subtitle: (data['subtitle'] as String?) ?? '',
      ctaLabel: (data['cta_label'] as String?) ?? '',
      icon: (data['icon'] as String?) ?? '',
      gradientStart: (data['gradient_start'] as String?) ?? '#6366F1',
      gradientEnd: (data['gradient_end'] as String?) ?? '#8B5CF6',
      position: _parsePosition(data['position'] as String?),
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
      isActive: (data['is_active'] as bool?) ?? true,
      linkTarget: (data['link_target'] as String?) ?? '',
      analytics: data['analytics'] is Map
          ? BannerAnalytics.fromMap(
              Map<String, dynamic>.from(data['analytics'] as Map))
          : null,
      lastEditedBy: adminMeta['last_edited_by'] as String?,
      lastEditedAt: editedTs is Timestamp ? editedTs.toDate() : null,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': type.wire,
        'title': title,
        'subtitle': subtitle,
        'cta_label': ctaLabel,
        'icon': icon,
        'gradient_start': gradientStart,
        'gradient_end': gradientEnd,
        'position': position.wire,
        'display_order': displayOrder,
        'is_active': isActive,
        'link_target': linkTarget,
        'created_at': Timestamp.fromDate(createdAt),
        if (analytics != null) 'analytics': analytics!.toMap(),
        'admin_meta': <String, dynamic>{
          if (lastEditedBy != null) 'last_edited_by': lastEditedBy,
          if (lastEditedAt != null)
            'last_edited_at': Timestamp.fromDate(lastEditedAt!),
        },
      };

  static BannerType _parseType(String? raw) {
    switch (raw) {
      case 'community':
        return BannerType.community;
      case 'custom':
        return BannerType.custom;
      case 'anytasks':
      default:
        return BannerType.anytasks;
    }
  }

  static BannerPosition _parsePosition(String? raw) {
    switch (raw) {
      case 'top':
        return BannerPosition.top;
      case 'end_of_page':
        return BannerPosition.endOfPage;
      case 'after_categories':
      default:
        return BannerPosition.afterCategories;
    }
  }
}

class BannerAnalytics {
  const BannerAnalytics({
    this.impressions7d = 0,
    this.clicks7d = 0,
    this.ctr7d,
    this.sparkline7d = const <int>[],
  });

  final int impressions7d;
  final int clicks7d;
  final double? ctr7d;
  final List<int> sparkline7d;

  factory BannerAnalytics.fromMap(Map<String, dynamic> m) => BannerAnalytics(
        impressions7d: (m['impressions_7d'] as num?)?.toInt() ?? 0,
        clicks7d: (m['clicks_7d'] as num?)?.toInt() ?? 0,
        ctr7d: (m['ctr_7d'] as num?)?.toDouble(),
        sparkline7d: m['sparkline_7d'] is List
            ? (m['sparkline_7d'] as List)
                .whereType<num>()
                .map((n) => n.toInt())
                .toList()
            : const <int>[],
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'impressions_7d': impressions7d,
        'clicks_7d': clicks7d,
        if (ctr7d != null) 'ctr_7d': ctr7d,
        'sparkline_7d': sparkline7d,
      };
}

enum BannerType { anytasks, community, custom }

extension BannerTypeWire on BannerType {
  String get wire {
    switch (this) {
      case BannerType.community:
        return 'community';
      case BannerType.custom:
        return 'custom';
      case BannerType.anytasks:
        return 'anytasks';
    }
  }
}

enum BannerPosition { top, afterCategories, endOfPage }

extension BannerPositionWire on BannerPosition {
  String get wire {
    switch (this) {
      case BannerPosition.top:
        return 'top';
      case BannerPosition.endOfPage:
        return 'end_of_page';
      case BannerPosition.afterCategories:
        return 'after_categories';
    }
  }
}
