import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-admin filter / sort / view-mode preset stored at
/// `admin_saved_views/{viewId}`. Loaded into the toolbar dropdown.
class SavedView {
  SavedView({
    required this.id,
    required this.adminUid,
    required this.name,
    required this.filters,
    required this.sortBy,
    required this.viewMode,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String adminUid;
  final String name;
  final SavedViewFilters filters;
  final CategorySort sortBy;
  final ViewMode viewMode;
  final bool isDefault;
  final DateTime createdAt;

  factory SavedView.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['created_at'];
    return SavedView(
      id: doc.id,
      adminUid: (data['admin_uid'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      filters: SavedViewFilters.fromMap(
          data['filters'] is Map ? Map<String, dynamic>.from(data['filters'] as Map) : const {}),
      sortBy: CategorySortWire.fromWire(data['sort_by'] as String?),
      viewMode: ViewModeWire.fromWire(data['view_mode'] as String?),
      isDefault: (data['is_default'] as bool?) ?? false,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'admin_uid': adminUid,
        'name': name,
        'filters': filters.toMap(),
        'sort_by': sortBy.wire,
        'view_mode': viewMode.wire,
        'is_default': isDefault,
        'created_at': Timestamp.fromDate(createdAt),
      };
}

class SavedViewFilters {
  const SavedViewFilters({
    this.statuses = const <String>[],
    this.hasImage,
    this.hasProviders,
    this.isCsm,
    this.customQuery = '',
  });

  /// e.g. ['active', 'popular', 'hot']. Empty = no filter.
  final List<String> statuses;
  final bool? hasImage;
  final bool? hasProviders;
  final bool? isCsm;
  final String customQuery;

  bool get isAnyApplied =>
      statuses.isNotEmpty ||
      hasImage != null ||
      hasProviders != null ||
      isCsm != null ||
      customQuery.isNotEmpty;

  factory SavedViewFilters.fromMap(Map<String, dynamic> m) => SavedViewFilters(
        statuses: m['status'] is List
            ? List<String>.from(
                (m['status'] as List).whereType<String>())
            : const <String>[],
        hasImage: m['has_image'] as bool?,
        hasProviders: m['has_providers'] as bool?,
        isCsm: m['is_csm'] as bool?,
        customQuery: (m['custom_query'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'status': statuses,
        'has_image': hasImage,
        'has_providers': hasProviders,
        'is_csm': isCsm,
        'custom_query': customQuery,
      };

  SavedViewFilters copyWith({
    List<String>? statuses,
    Object? hasImage = _sentinel,
    Object? hasProviders = _sentinel,
    Object? isCsm = _sentinel,
    String? customQuery,
  }) =>
      SavedViewFilters(
        statuses: statuses ?? this.statuses,
        hasImage: hasImage == _sentinel ? this.hasImage : hasImage as bool?,
        hasProviders:
            hasProviders == _sentinel ? this.hasProviders : hasProviders as bool?,
        isCsm: isCsm == _sentinel ? this.isCsm : isCsm as bool?,
        customQuery: customQuery ?? this.customQuery,
      );
}

const Object _sentinel = Object();

enum CategorySort {
  manualOrder,
  nameAsc,
  ordersDesc,
  revenueDesc,
  growthDesc,
  healthAsc,
  healthDesc,
  recentlyEdited,
}

extension CategorySortWire on CategorySort {
  String get wire {
    switch (this) {
      case CategorySort.manualOrder:
        return 'manual_order';
      case CategorySort.nameAsc:
        return 'name_asc';
      case CategorySort.ordersDesc:
        return 'orders_desc';
      case CategorySort.revenueDesc:
        return 'revenue_desc';
      case CategorySort.growthDesc:
        return 'growth_desc';
      case CategorySort.healthAsc:
        return 'health_asc';
      case CategorySort.healthDesc:
        return 'health_desc';
      case CategorySort.recentlyEdited:
        return 'recently_edited';
    }
  }

  String get hebrewLabel {
    switch (this) {
      case CategorySort.manualOrder:
        return 'סדר ידני';
      case CategorySort.nameAsc:
        return 'שם (א-ת)';
      case CategorySort.ordersDesc:
        return 'הזמנות (גבוה-נמוך)';
      case CategorySort.revenueDesc:
        return 'הכנסות (גבוה-נמוך)';
      case CategorySort.growthDesc:
        return 'צמיחה (חזק לחלש)';
      case CategorySort.healthAsc:
        return 'בריאות (בעייתי קודם)';
      case CategorySort.healthDesc:
        return 'בריאות (בריא קודם)';
      case CategorySort.recentlyEdited:
        return 'עודכן לאחרונה';
    }
  }

  static CategorySort fromWire(String? raw) {
    switch (raw) {
      case 'name_asc':
        return CategorySort.nameAsc;
      case 'orders_desc':
        return CategorySort.ordersDesc;
      case 'revenue_desc':
        return CategorySort.revenueDesc;
      case 'growth_desc':
        return CategorySort.growthDesc;
      case 'health_asc':
        return CategorySort.healthAsc;
      case 'health_desc':
        return CategorySort.healthDesc;
      case 'recently_edited':
        return CategorySort.recentlyEdited;
      case 'manual_order':
      default:
        return CategorySort.manualOrder;
    }
  }
}

enum ViewMode { tree, grid, analytics }

extension ViewModeWire on ViewMode {
  String get wire {
    switch (this) {
      case ViewMode.grid:
        return 'grid';
      case ViewMode.analytics:
        return 'analytics';
      case ViewMode.tree:
        return 'tree';
    }
  }

  static ViewMode fromWire(String? raw) {
    switch (raw) {
      case 'grid':
        return ViewMode.grid;
      case 'analytics':
        return ViewMode.analytics;
      case 'tree':
      default:
        return ViewMode.tree;
    }
  }
}
