import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/activity_log_entry.dart';
import '../models/category_v3_model.dart';
import '../models/saved_view.dart';
import '../services/activity_log_service.dart';
import '../services/categories_v3_service.dart';
import '../services/category_analytics_service.dart';
import '../services/command_palette_service.dart';
import '../services/saved_views_service.dart';
import 'selection_controller.dart';

part 'categories_v3_controller.g.dart';

// ── Service providers (singletons — survive tab switches) ───────────────────

@Riverpod(keepAlive: true)
CategoriesV3Service categoriesV3Service(Ref ref) => CategoriesV3Service();

@Riverpod(keepAlive: true)
ActivityLogService activityLogService(Ref ref) => ActivityLogService();

@Riverpod(keepAlive: true)
CategoryAnalyticsService categoryAnalyticsService(Ref ref) =>
    CategoryAnalyticsService();

@Riverpod(keepAlive: true)
SavedViewsService savedViewsService(Ref ref) => SavedViewsService();

@Riverpod(keepAlive: true)
CommandPaletteService commandPaletteService(Ref ref) =>
    CommandPaletteService();

@Riverpod(keepAlive: true)
SelectionController selectionController(Ref ref) {
  final ctrl = SelectionController();
  ref.onDispose(ctrl.dispose);
  return ctrl;
}

// ── Streams used by the UI ──────────────────────────────────────────────────

@riverpod
Stream<List<CategoryV3Model>> categoriesV3Stream(Ref ref) {
  final svc = ref.watch(categoriesV3ServiceProvider);
  return svc.watchAll();
}

@riverpod
Stream<List<ActivityLogEntry>> activityLogStream(Ref ref, {int limit = 50}) {
  final svc = ref.watch(activityLogServiceProvider);
  return svc.watch(limit: limit);
}

@riverpod
Stream<List<SavedView>> savedViewsStream(Ref ref) {
  final svc = ref.watch(savedViewsServiceProvider);
  return svc.watchMine();
}

// ── Screen-level UI state ───────────────────────────────────────────────────

/// Pure UI state for the new categories tab. Holds search query, active
/// filter, sort key, view mode, panel visibility flags. Does NOT own the
/// category list itself — that comes from [categoriesV3StreamProvider].
class CategoriesScreenState {
  const CategoriesScreenState({
    this.searchQuery = '',
    this.filters = const SavedViewFilters(),
    this.sortBy = CategorySort.manualOrder,
    this.viewMode = ViewMode.tree,
    this.activityPanelOpen = false,
    this.commandPaletteOpen = false,
    this.shortcutsHintDismissed = false,
    this.expandedCategoryId,
  });

  final String searchQuery;
  final SavedViewFilters filters;
  final CategorySort sortBy;
  final ViewMode viewMode;
  final bool activityPanelOpen;
  final bool commandPaletteOpen;
  final bool shortcutsHintDismissed;

  /// When set, that category's sub-categories grid is rendered inline.
  final String? expandedCategoryId;

  CategoriesScreenState copyWith({
    String? searchQuery,
    SavedViewFilters? filters,
    CategorySort? sortBy,
    ViewMode? viewMode,
    bool? activityPanelOpen,
    bool? commandPaletteOpen,
    bool? shortcutsHintDismissed,
    Object? expandedCategoryId = _sentinel,
  }) =>
      CategoriesScreenState(
        searchQuery: searchQuery ?? this.searchQuery,
        filters: filters ?? this.filters,
        sortBy: sortBy ?? this.sortBy,
        viewMode: viewMode ?? this.viewMode,
        activityPanelOpen: activityPanelOpen ?? this.activityPanelOpen,
        commandPaletteOpen: commandPaletteOpen ?? this.commandPaletteOpen,
        shortcutsHintDismissed:
            shortcutsHintDismissed ?? this.shortcutsHintDismissed,
        expandedCategoryId: expandedCategoryId == _sentinel
            ? this.expandedCategoryId
            : expandedCategoryId as String?,
      );
}

const Object _sentinel = Object();

/// The screen-level controller — Riverpod Notifier (new API, no deprecated
/// `Ref` typedefs). Exposes commands the UI calls without rebuilding on
/// every Firestore tick.
@Riverpod(keepAlive: true)
class CategoriesV3Controller extends _$CategoriesV3Controller {
  @override
  CategoriesScreenState build() => const CategoriesScreenState();

  // Search
  void setSearch(String q) =>
      state = state.copyWith(searchQuery: q);

  // Filters / sort / view
  void setFilters(SavedViewFilters f) => state = state.copyWith(filters: f);
  void setSort(CategorySort s) => state = state.copyWith(sortBy: s);
  void setViewMode(ViewMode m) => state = state.copyWith(viewMode: m);

  // Panels
  void toggleActivityPanel() =>
      state = state.copyWith(activityPanelOpen: !state.activityPanelOpen);
  void openCommandPalette() =>
      state = state.copyWith(commandPaletteOpen: true);
  void closeCommandPalette() =>
      state = state.copyWith(commandPaletteOpen: false);

  // Inline sub-category expand/collapse
  void toggleExpand(String categoryId) {
    final newId =
        state.expandedCategoryId == categoryId ? null : categoryId;
    state = state.copyWith(expandedCategoryId: newId);
  }

  void dismissShortcutsHint() =>
      state = state.copyWith(shortcutsHintDismissed: true);

  /// Loads a saved view's filter / sort / view-mode into the screen state.
  void applySavedView(SavedView view) {
    state = state.copyWith(
      filters: view.filters,
      sortBy: view.sortBy,
      viewMode: view.viewMode,
    );
    if (kDebugMode) {
      debugPrint('[CategoriesV3] Applied saved view: ${view.name}');
    }
  }
}

// ── Derived data ────────────────────────────────────────────────────────────

/// Filter + sort the live category list per the current screen state. Pure
/// in-memory transform — no extra Firestore reads.
@riverpod
List<CategoryV3Model> filteredCategoriesV3(Ref ref) {
  final asyncList = ref.watch(categoriesV3StreamProvider);
  final s = ref.watch(categoriesV3ControllerProvider);

  return asyncList.maybeWhen(
    data: (categories) => _applyScreenStateToList(categories, s),
    orElse: () => const <CategoryV3Model>[],
  );
}

List<CategoryV3Model> _applyScreenStateToList(
  List<CategoryV3Model> all,
  CategoriesScreenState s,
) {
  Iterable<CategoryV3Model> result = all;

  // Search
  final q = s.searchQuery.trim().toLowerCase();
  if (q.isNotEmpty) {
    result = result.where((c) {
      if (c.name.toLowerCase().contains(q)) return true;
      for (final t in c.customTags) {
        if (t.toLowerCase().contains(q)) return true;
      }
      return false;
    });
  }

  // Filters
  final f = s.filters;
  if (f.statuses.isNotEmpty) {
    result = result.where((c) {
      if (f.statuses.contains('hidden') && c.isHidden) return true;
      if (f.statuses.contains('pinned') && c.isPinned) return true;
      if (f.statuses.contains('csm') && c.isCsm) return true;
      // 'active' = not hidden
      if (f.statuses.contains('active') && !c.isHidden) return true;
      return false;
    });
  }
  if (f.hasImage != null) {
    result = result.where((c) {
      final has = (c.imageUrl ?? '').isNotEmpty || c.iconUrl.isNotEmpty;
      return has == f.hasImage;
    });
  }
  if (f.hasProviders != null) {
    result = result.where((c) {
      final has = (c.analytics?.activeProviders ?? 0) > 0;
      return has == f.hasProviders;
    });
  }
  if (f.isCsm != null) {
    result = result.where((c) => c.isCsm == f.isCsm);
  }

  // Sort
  final list = result.toList();
  switch (s.sortBy) {
    case CategorySort.manualOrder:
      list.sort((a, b) => a.order.compareTo(b.order));
    case CategorySort.nameAsc:
      list.sort((a, b) => a.name.compareTo(b.name));
    case CategorySort.ordersDesc:
      list.sort((a, b) =>
          (b.analytics?.orders30d ?? 0).compareTo(a.analytics?.orders30d ?? 0));
    case CategorySort.revenueDesc:
      list.sort((a, b) => (b.analytics?.revenue30d ?? 0)
          .compareTo(a.analytics?.revenue30d ?? 0));
    case CategorySort.growthDesc:
      list.sort((a, b) => (b.analytics?.growth30d ?? 0)
          .compareTo(a.analytics?.growth30d ?? 0));
    case CategorySort.healthAsc:
      list.sort((a, b) => (a.analytics?.healthScore ?? 0)
          .compareTo(b.analytics?.healthScore ?? 0));
    case CategorySort.healthDesc:
      list.sort((a, b) => (b.analytics?.healthScore ?? 0)
          .compareTo(a.analytics?.healthScore ?? 0));
    case CategorySort.recentlyEdited:
      list.sort((a, b) {
        final at = a.adminMeta?.lastEditedAt;
        final bt = b.adminMeta?.lastEditedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
  }

  return list;
}

/// KPIs derived from the live (unfiltered) list — top of the dashboard.
@riverpod
CategoriesKpis categoriesKpis(Ref ref) {
  final asyncList = ref.watch(categoriesV3StreamProvider);
  final analytics = ref.watch(categoryAnalyticsServiceProvider);
  return asyncList.maybeWhen(
    data: analytics.computeKpis,
    orElse: () => CategoriesKpis.empty,
  );
}
