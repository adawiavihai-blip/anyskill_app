import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/categories_v3_controller.dart';
import 'models/category_v3_model.dart';
import 'models/promoted_banner.dart';
import 'models/saved_view.dart';
import 'widgets/banner_row_card.dart';
import 'widgets/bulk_actions_bar.dart';
import 'widgets/category_row_card.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/keyboard_shortcuts_hint.dart';
import 'widgets/kpi_metrics_row.dart';
import 'widgets/subcategory_grid.dart';
import 'widgets/toolbar_bar.dart';

/// v3 categories admin tab — Phase C wiring.
///
/// Layout:
///   1. Header strip (title + v3 PRO pill)
///   2. KPI strip (5 cards)
///   3. Toolbar (search + sort + view switcher)
///   4. Keyboard shortcuts hint (dismissable)
///   5. Promoted banners section (mock cards)
///   6. Categories list (ReorderableListView in tree view, expandable rows)
///   7. Bulk actions bar (sticky bottom, slides in when count > 0)
///
/// Keyboard shortcuts (web only): ↑↓ navigate · Space select · E edit · H hide ·
/// P pin · Del delete · ⌘K palette · ⌘Z undo · Esc clear · / focus search.
class AdminCategoriesV3Tab extends ConsumerStatefulWidget {
  const AdminCategoriesV3Tab({super.key});

  @override
  ConsumerState<AdminCategoriesV3Tab> createState() =>
      _AdminCategoriesV3TabState();
}

class _AdminCategoriesV3TabState extends ConsumerState<AdminCategoriesV3Tab> {
  /// Highlighted-by-keyboard row id. Independent of selection.
  String? _focusedId;
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'CategoriesV3Screen');
  Timer? _reorderDebounce;
  List<String>? _pendingOrder;

  @override
  void initState() {
    super.initState();
    // Grab focus once mounted so keyboard shortcuts work immediately on web.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _screenFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _reorderDebounce?.cancel();
    _screenFocusNode.dispose();
    super.dispose();
  }

  // ── Reorder (debounced 500ms per spec §10) ────────────────────────────────
  void _scheduleReorderWrite(List<String> orderedIds) {
    _pendingOrder = orderedIds;
    _reorderDebounce?.cancel();
    _reorderDebounce = Timer(const Duration(milliseconds: 500), () async {
      final ids = _pendingOrder;
      _pendingOrder = null;
      if (ids == null || ids.isEmpty) return;
      try {
        await ref
            .read(categoriesV3ServiceProvider)
            .reorderRootCategories(ids);
      } catch (e) {
        if (kDebugMode) debugPrint('[CategoriesV3] reorder failed: $e');
      }
    });
  }

  // ── Keyboard handler ──────────────────────────────────────────────────────
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = ref.read(categoriesV3ControllerProvider.notifier);
    final selection = ref.read(selectionControllerProvider);
    final list = ref.read(filteredCategoriesV3Provider)
        .where((c) => c.isRoot)
        .toList();
    if (list.isEmpty) return KeyEventResult.ignored;

    final logicalKey = event.logicalKey;
    final isMod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    int currentIdx = _focusedId == null
        ? -1
        : list.indexWhere((c) => c.id == _focusedId);

    if (logicalKey == LogicalKeyboardKey.arrowDown) {
      final next = (currentIdx + 1).clamp(0, list.length - 1);
      setState(() => _focusedId = list[next].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.arrowUp) {
      final next = currentIdx <= 0 ? 0 : currentIdx - 1;
      setState(() => _focusedId = list[next].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.space) {
      if (currentIdx < 0) return KeyEventResult.ignored;
      selection.toggle(list[currentIdx].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.escape) {
      selection.clear();
      setState(() => _focusedId = null);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.slash) {
      // The toolbar's text field has its own focus node — but a quick-and-
      // dirty approach is to pop a snackbar telling the user to click search.
      // Phase C ships this minimal behaviour; deeper focus management is
      // Phase D when CommandPalette + saved views land.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('לחץ/י על שדה החיפוש'),
        duration: Duration(seconds: 1),
      ));
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.keyH) {
      if (currentIdx < 0) return KeyEventResult.ignored;
      ref.read(categoriesV3ServiceProvider).toggleHide(list[currentIdx].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.keyP) {
      if (currentIdx < 0) return KeyEventResult.ignored;
      ref.read(categoriesV3ServiceProvider).togglePin(list[currentIdx].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.keyE) {
      // Edit dialog lands in Phase D — for now, expand the row.
      if (currentIdx < 0) return KeyEventResult.ignored;
      ctrl.toggleExpand(list[currentIdx].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.delete ||
        logicalKey == LogicalKeyboardKey.backspace) {
      if (currentIdx < 0) return KeyEventResult.ignored;
      _confirmDelete(list[currentIdx]);
      return KeyEventResult.handled;
    }
    if (isMod && logicalKey == LogicalKeyboardKey.keyK) {
      // ⌘K — palette is built in Phase D. Show a placeholder snackbar so
      // the binding is provably alive.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('פלטת הפקודות (⌘K) תצטרף ב-Phase D'),
        duration: Duration(seconds: 2),
      ));
      return KeyEventResult.handled;
    }
    if (isMod && logicalKey == LogicalKeyboardKey.keyZ) {
      _undoLast();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _undoLast() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final entry = await ref.read(activityLogServiceProvider).undoLast();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(entry == null
            ? 'אין פעולה לבטל'
            : 'בוטלה פעולה: ${entry.targetName}'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('בוטל לא הצליח: $e')),
      );
    }
  }

  Future<void> _confirmDelete(CategoryV3Model c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת קטגוריה'),
        content: Text(
            'בטוח שברצונך למחוק את "${c.name}"? פעולה זו ניתנת לביטול דרך יומן הפעולות.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              backgroundColor: const Color(0xFFFEF2F2),
            ),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(categoriesV3ServiceProvider).delete(c.id);
    }
  }

  // ── Bulk actions ──────────────────────────────────────────────────────────
  Future<void> _bulkHide() async {
    final selection = ref.read(selectionControllerProvider);
    final ids = selection.selectedIds;
    if (ids.isEmpty) return;
    await ref.read(categoriesV3ServiceProvider).bulkHide(ids, hide: true);
    selection.clear();
  }

  Future<void> _bulkPin() async {
    final selection = ref.read(selectionControllerProvider);
    final ids = selection.selectedIds;
    if (ids.isEmpty) return;
    await ref.read(categoriesV3ServiceProvider).bulkPin(ids, pin: true);
    selection.clear();
  }

  Future<void> _bulkDelete() async {
    final selection = ref.read(selectionControllerProvider);
    final ids = selection.selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקה גורפת'),
        content: Text('למחוק ${ids.length} קטגוריות? ניתן לבטל מיומן הפעולות.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              backgroundColor: const Color(0xFFFEF2F2),
            ),
            child: const Text('מחק הכל'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(categoriesV3ServiceProvider).bulkDelete(ids);
      selection.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncCategories = ref.watch(categoriesV3StreamProvider);
    final filtered = ref.watch(filteredCategoriesV3Provider);
    final kpis = ref.watch(categoriesKpisProvider);
    final state = ref.watch(categoriesV3ControllerProvider);
    final ctrl = ref.read(categoriesV3ControllerProvider.notifier);
    final selection = ref.watch(selectionControllerProvider);

    // Prune dangling selection ids whenever the list changes
    asyncCategories.whenData((list) {
      final validIds = list.map((c) => c.id).toSet();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) selection.prune(validIds);
      });
    });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F2),
        body: Focus(
          focusNode: _screenFocusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              SafeArea(
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      16, 16, 16, 80),
                  children: [
                    const _Header(),
                    const SizedBox(height: 16),
                    KpiMetricsRow(kpis: kpis),
                    const SizedBox(height: 16),
                    const ToolbarBar(),
                    const SizedBox(height: 12),
                    KeyboardShortcutsHint(
                      dismissed: state.shortcutsHintDismissed,
                      onDismiss: ctrl.dismissShortcutsHint,
                    ),
                    const _SectionLabel(text: 'באנרים מקודמים'),
                    const SizedBox(height: 8),
                    const _PromotedBannersSection(),
                    const SizedBox(height: 16),
                    const _SectionLabel(text: 'קטגוריות'),
                    const SizedBox(height: 8),
                    _CategoriesList(
                      asyncCategories: asyncCategories,
                      filtered: filtered,
                      expandedId: state.expandedCategoryId,
                      focusedId: _focusedId,
                      reorderable: state.viewMode == ViewMode.tree &&
                          state.searchQuery.isEmpty &&
                          state.sortBy == CategorySort.manualOrder,
                      onToggleExpand: ctrl.toggleExpand,
                      onReorderRoot: _scheduleReorderWrite,
                      onConfirmDelete: _confirmDelete,
                    ),
                  ],
                ),
              ),
              // Sticky bulk actions bar (bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: BulkActionsBar(
                    onBulkHide: _bulkHide,
                    onBulkPin: _bulkPin,
                    onBulkDelete: _bulkDelete,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.category_rounded,
              color: Color(0xFF6366F1), size: 20),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'קטגוריות',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 2),
            Text(
              'ניהול אזור-עבודה (Workspace) ברמה עולמית',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF6366F1),
              Color(0xFF8B5CF6),
            ]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'v3 PRO',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _PromotedBannersSection extends ConsumerWidget {
  const _PromotedBannersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mocks = <PromotedBanner>[
      PromotedBanner(
        id: 'mock-anytasks',
        type: BannerType.anytasks,
        title: 'AnyTasks',
        subtitle: 'מצא נותן שירות תוך דקות / משימות פתוחות',
        ctaLabel: 'מקודם בבית',
        icon: '🚀',
        gradientStart: '#6366F1',
        gradientEnd: '#8B5CF6',
        position: BannerPosition.afterCategories,
        displayOrder: 1,
        isActive: true,
        linkTarget: '/anytasks',
      ),
      PromotedBanner(
        id: 'mock-community',
        type: BannerType.community,
        title: 'נתינה מהלב',
        subtitle: 'כישרון אחד, לב אחד · קהילת מתנדבים',
        ctaLabel: 'מקודם בבית',
        icon: '❤️',
        gradientStart: '#EF4444',
        gradientEnd: '#EC4899',
        position: BannerPosition.afterCategories,
        displayOrder: 2,
        isActive: true,
        linkTarget: '/community',
      ),
    ];

    return Column(
      children: [for (final b in mocks) BannerRowCard(banner: b)],
    );
  }
}

class _CategoriesList extends ConsumerWidget {
  const _CategoriesList({
    required this.asyncCategories,
    required this.filtered,
    required this.expandedId,
    required this.focusedId,
    required this.reorderable,
    required this.onToggleExpand,
    required this.onReorderRoot,
    required this.onConfirmDelete,
  });

  final AsyncValue<List<CategoryV3Model>> asyncCategories;
  final List<CategoryV3Model> filtered;
  final String? expandedId;
  final String? focusedId;
  final bool reorderable;
  final void Function(String) onToggleExpand;
  final void Function(List<String>) onReorderRoot;
  final Future<void> Function(CategoryV3Model) onConfirmDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncCategories.when(
      loading: () => const _LoadingShimmer(),
      error: (e, _) => EmptyStateWidget(
        icon: Icons.error_outline_rounded,
        title: 'שגיאה בטעינת קטגוריות',
        subtitle: e.toString(),
        tone: EmptyTone.danger,
      ),
      data: (_) {
        final root = filtered.where((c) => c.isRoot).toList();
        if (root.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.category_outlined,
            title: 'אין קטגוריות תואמות',
            subtitle:
                'נקה את החיפוש או הסר פילטרים. אם אין קטגוריות בכלל, הרץ את ה-backfill.',
            tone: EmptyTone.neutral,
          );
        }

        if (reorderable) {
          return ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: root.length,
            onReorder: (oldIndex, newIndex) {
              final ids = root.map((c) => c.id).toList();
              if (newIndex > oldIndex) newIndex -= 1;
              final moved = ids.removeAt(oldIndex);
              ids.insert(newIndex, moved);
              onReorderRoot(ids);
            },
            itemBuilder: (context, index) =>
                _RootItem(
              key: ValueKey('cat-${root[index].id}'),
              category: root[index],
              filtered: filtered,
              index: index,
              expandedId: expandedId,
              focusedId: focusedId,
              dragEnabled: true,
              onToggleExpand: onToggleExpand,
              onConfirmDelete: onConfirmDelete,
            ),
          );
        }

        // Non-reorderable plain list (search active or non-manual sort)
        final children = <Widget>[];
        for (var i = 0; i < root.length; i++) {
          children.add(_RootItem(
            key: ValueKey('cat-${root[i].id}'),
            category: root[i],
            filtered: filtered,
            index: i,
            expandedId: expandedId,
            focusedId: focusedId,
            dragEnabled: false,
            onToggleExpand: onToggleExpand,
            onConfirmDelete: onConfirmDelete,
          ));
        }
        return Column(children: children);
      },
    );
  }
}

class _RootItem extends ConsumerWidget {
  const _RootItem({
    super.key,
    required this.category,
    required this.filtered,
    required this.index,
    required this.expandedId,
    required this.focusedId,
    required this.dragEnabled,
    required this.onToggleExpand,
    required this.onConfirmDelete,
  });

  final CategoryV3Model category;
  final List<CategoryV3Model> filtered;
  final int index;
  final String? expandedId;
  final String? focusedId;
  final bool dragEnabled;
  final void Function(String) onToggleExpand;
  final Future<void> Function(CategoryV3Model) onConfirmDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    final isExpanded = expandedId == category.id;
    final isFocused = focusedId == category.id;

    return AnimatedBuilder(
      animation: selection,
      builder: (context, _) {
        final isSelected = selection.contains(category.id);
        return Column(
          children: [
            CategoryRowCard(
              category: category,
              expanded: isExpanded,
              focused: isFocused,
              selected: isSelected,
              onToggleSelect: () => selection.toggle(category.id),
              onToggleExpand: () => onToggleExpand(category.id),
              dragEnabled: dragEnabled,
              dragHandle: dragEnabled
                  ? ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsetsDirectional.all(4),
                        child: Icon(Icons.drag_indicator_rounded,
                            size: 18, color: Color(0xFF9CA3AF)),
                      ),
                    )
                  : null,
              onEdit: () => onToggleExpand(category.id),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 8, end: 8, bottom: 12),
                child: SubcategoryGrid(
                  parentId: category.id,
                  subcategories: filtered
                      .where((s) => s.parentId == category.id)
                      .toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (_) => Container(
          height: 64,
          margin: const EdgeInsetsDirectional.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
        ),
      ),
    );
  }
}
