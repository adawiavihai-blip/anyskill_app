import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/categories_v3_controller.dart';
import 'dialogs/add_category_dialog.dart';
import 'dialogs/confirm_destructive_dialog.dart';
import 'dialogs/edit_category_dialog.dart';
import 'dialogs/saved_view_dialog.dart';
import 'models/category_v3_model.dart';
import 'models/command_palette_action.dart';
import 'models/promoted_banner.dart';
import 'models/saved_view.dart';
import 'widgets/activity_log_panel.dart';
import 'widgets/banner_row_card.dart';
import 'widgets/bulk_actions_bar.dart';
import 'widgets/category_row_card.dart';
import 'widgets/command_palette_overlay.dart';
import 'widgets/diagnostic_panel.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/keyboard_shortcuts_hint.dart';
import 'widgets/kpi_metrics_row.dart';
import 'widgets/loading_shimmer.dart';
import 'widgets/power_tools_footer.dart';
import 'widgets/subcategory_grid.dart';
import 'widgets/toolbar_bar.dart';

/// v3 categories admin tab — Phase D wiring.
///
/// Layout:
///   1. Header strip (title + activity panel toggle + saved-views menu + add)
///   2. KPI strip (5 cards)
///   3. Toolbar (search + sort + view switcher)
///   4. Keyboard shortcuts hint (dismissable)
///   5. Promoted banners section (mock cards)
///   6. Categories list (ReorderableListView in tree view, expandable rows)
///   7. Power tools footer (refresh / export / import / reset)
///   8. Bulk actions bar (sticky bottom)
///   9. ActivityLogPanel overlay (slide-in)
///   10. CommandPaletteOverlay (⌘K modal)
///
/// All keyboard shortcuts now route to real handlers (no more snackbar
/// placeholders from Phase C).
class AdminCategoriesV3Tab extends ConsumerStatefulWidget {
  const AdminCategoriesV3Tab({super.key});

  @override
  ConsumerState<AdminCategoriesV3Tab> createState() =>
      _AdminCategoriesV3TabState();
}

class _AdminCategoriesV3TabState extends ConsumerState<AdminCategoriesV3Tab> {
  String? _focusedId;
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'CategoriesV3Screen');
  Timer? _reorderDebounce;
  List<String>? _pendingOrder;

  @override
  void initState() {
    super.initState();
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
    final list = ref
        .read(filteredCategoriesV3Provider)
        .where((c) => c.isRoot)
        .toList();
    if (list.isEmpty) return KeyEventResult.ignored;

    final logicalKey = event.logicalKey;
    final isMod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    final currentIdx = _focusedId == null
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
      if (ref.read(categoriesV3ControllerProvider).commandPaletteOpen) {
        ctrl.closeCommandPalette();
        return KeyEventResult.handled;
      }
      selection.clear();
      setState(() => _focusedId = null);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.slash) {
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
      if (currentIdx < 0) return KeyEventResult.ignored;
      EditCategoryDialog.show(context, list[currentIdx].id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.delete ||
        logicalKey == LogicalKeyboardKey.backspace) {
      if (currentIdx < 0) return KeyEventResult.ignored;
      _confirmDelete(list[currentIdx]);
      return KeyEventResult.handled;
    }
    if (isMod && logicalKey == LogicalKeyboardKey.keyK) {
      ctrl.openCommandPalette();
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
      messenger.showSnackBar(SnackBar(content: Text('בוטל לא הצליח: $e')));
    }
  }

  Future<void> _confirmDelete(CategoryV3Model c) async {
    final ok = await ConfirmDestructiveDialog.show(
      context,
      title: 'מחיקת קטגוריה',
      body:
          'הקטגוריה "${c.name}" תימחק לצמיתות. ניתן לבטל דרך יומן הפעולות בתוך 30 יום, אחר כך זה סופי.',
      requiredText: c.name,
      confirmLabel: 'מחק לצמיתות',
      warning: 'תתי-קטגוריות, ספקים, והפניות יישארו אך יאבדו את הקישור.',
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
    final ok = await ConfirmDestructiveDialog.show(
      context,
      title: 'מחיקה גורפת',
      body:
          'יימחקו ${ids.length} קטגוריות. ניתן לבטל מיומן הפעולות (כל מחיקה כרשומה נפרדת).',
      requiredText: 'מחק ${ids.length}',
      helperLabel: 'כתוב "מחק ${ids.length}" כדי לאשר',
      confirmLabel: 'מחק את כולן',
      warning: 'מחיקה גורפת היא פעולה אחת לא הפיכה ברמת המערכת.',
    );
    if (ok == true) {
      await ref.read(categoriesV3ServiceProvider).bulkDelete(ids);
      selection.clear();
    }
  }

  // ── Command palette dispatcher ────────────────────────────────────────────
  Future<void> _executePaletteAction(CommandPaletteAction action) async {
    final ctrl = ref.read(categoriesV3ControllerProvider.notifier);
    switch (action.kind) {
      case CommandKind.jumpToCategory:
      case CommandKind.jumpToSubcategory:
        if (action.targetId != null) ctrl.toggleExpand(action.targetId!);
      case CommandKind.createCategory:
        await AddCategoryDialog.show(context);
      case CommandKind.editCategory:
        if (action.targetId != null) {
          await EditCategoryDialog.show(context, action.targetId!);
        }
      case CommandKind.refreshAnalytics:
        try {
          await ref
              .read(categoriesV3ServiceProvider)
              .triggerAnalyticsRefresh();
        } catch (_) {/* silent — toast via PowerTools */}
      case CommandKind.openActivityLog:
        ctrl.toggleActivityPanel();
      case CommandKind.closeActivityLog:
        if (ref.read(categoriesV3ControllerProvider).activityPanelOpen) {
          ctrl.toggleActivityPanel();
        }
      case CommandKind.undoLast:
        await _undoLast();
      case CommandKind.switchView:
        if (action.targetId == 'tree') ctrl.setViewMode(ViewMode.tree);
        if (action.targetId == 'grid') ctrl.setViewMode(ViewMode.grid);
        if (action.targetId == 'analytics') {
          ctrl.setViewMode(ViewMode.analytics);
        }
      case CommandKind.exportJson:
      case CommandKind.importJson:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('השתמש בכפתורי "כלי-עוצמה" בתחתית העמוד'),
          duration: Duration(seconds: 2),
        ));
      case CommandKind.filterByTag:
      case CommandKind.togglePin:
      case CommandKind.toggleHide:
      case CommandKind.deleteCategory:
      case CommandKind.reorderCategory:
        // Phase E refinements — show a hint for now.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('הפעולה הזו מתווספת ב-Phase E'),
            duration: Duration(seconds: 1),
          ));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Top-level try/catch so a widget-build failure anywhere inside the tab
    // becomes a RED banner with the exception text instead of a grey block
    // or crash screen. Per user request after the 3-bug ternary fix session.
    try {
      return _buildInner(context);
    } catch (e, s) {
      // ignore: avoid_print
      print('╔═══ CATEGORIES TAB BUILD FAILURE ═══');
      // ignore: avoid_print
      print('║ error: $e');
      // ignore: avoid_print
      print('║ stack: $s');
      // ignore: avoid_print
      print('╚════════════════════════════════════');
      return Container(
        color: const Color(0xFFFEE2E2),
        padding: const EdgeInsets.all(16.0),
        alignment: Alignment.topRight,
        child: SelectableText(
          'Tab build failed:\n$e\n\n$s',
          style: const TextStyle(
            fontSize: 11.0,
            fontFamily: 'monospace',
            color: Color(0xFF991B1B),
          ),
          textDirection: TextDirection.ltr,
        ),
      );
    }
  }

  Widget _buildInner(BuildContext context) {
    final asyncCategories = ref.watch(categoriesV3StreamProvider);
    final filtered = ref.watch(filteredCategoriesV3Provider);
    final kpis = ref.watch(categoriesKpisProvider);
    final state = ref.watch(categoriesV3ControllerProvider);
    final ctrl = ref.read(categoriesV3ControllerProvider.notifier);
    final selection = ref.watch(selectionControllerProvider);

    // Selection sync — wrapped in BOTH a post-frame callback AND a microtask
    // so the eventual `selection.prune()` (which fires notifyListeners) cannot
    // mutate the SelectionController during a parent build cycle. The previous
    // postFrameCallback alone could still race with active AnimatedBuilder
    // listeners and produce uncaught "setState() during build" errors that
    // ErrorBoundary then surfaced as a grey placeholder.
    asyncCategories.whenData((list) {
      final validIds = list.map((c) => c.id).toSet();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future<void>.microtask(() {
          if (!mounted) return;
          try {
            selection.prune(validIds);
          } catch (e) {
            // Defensive — must never fail rendering.
            // ignore: avoid_print
            print('[CategoriesV3] selection.prune failed: $e');
          }
        });
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
                    _Header(
                      onToggleActivity: ctrl.toggleActivityPanel,
                      onSavedView: () => SavedViewDialog.show(context),
                      onAdd: () => AddCategoryDialog.show(context),
                    ),
                    const SizedBox(height: 16),
                    const DiagnosticPanel(),
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
                      onEdit: (c) =>
                          EditCategoryDialog.show(context, c.id),
                    ),
                    const PowerToolsFooter(),
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
              // Activity log slide-in
              ActivityLogPanel(
                open: state.activityPanelOpen,
                onClose: ctrl.toggleActivityPanel,
              ),
              // Command palette overlay
              CommandPaletteOverlay(
                open: state.commandPaletteOpen,
                onClose: ctrl.closeCommandPalette,
                onActionSelected: _executePaletteAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onToggleActivity,
    required this.onSavedView,
    required this.onAdd,
  });
  final VoidCallback onToggleActivity;
  final VoidCallback onSavedView;
  final VoidCallback onAdd;

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
        IconButton(
          tooltip: 'יומן פעולות',
          onPressed: onToggleActivity,
          icon: const Icon(Icons.history_rounded,
              color: Color(0xFF6B7280), size: 20),
        ),
        IconButton(
          tooltip: 'שמור תצוגה',
          onPressed: onSavedView,
          icon: const Icon(Icons.bookmark_add_outlined,
              color: Color(0xFF6B7280), size: 20),
        ),
        IconButton(
          tooltip: 'הוסף קטגוריה',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline_rounded,
              color: Color(0xFF10B981), size: 22),
        ),
        const SizedBox(width: 6),
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
    required this.onEdit,
  });

  final AsyncValue<List<CategoryV3Model>> asyncCategories;
  final List<CategoryV3Model> filtered;
  final String? expandedId;
  final String? focusedId;
  final bool reorderable;
  final void Function(String) onToggleExpand;
  final void Function(List<String>) onReorderRoot;
  final Future<void> Function(CategoryV3Model) onConfirmDelete;
  final void Function(CategoryV3Model) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Phase E-fix: PRIORITIZE `filtered` DATA OVER AsyncValue STATE ────
    // Previously this method wrapped everything in `asyncCategories.when(
    // loading: ..., data: ...)`. If the AsyncValue briefly flipped back to
    // `loading` after a notifyListeners cascade (e.g. from selection.prune),
    // we'd render a shimmer even when the `filtered` list already had items.
    // On Flutter Web that combined with a ShaderMask bug in LoadingShimmer
    // to produce a permanent solid-grey block.
    //
    // New rule: always prefer rendering `filtered` if it has any root items.
    // The shimmer is ONLY for the genuine "no data yet + still loading" path.
    final root = filtered.where((c) => c.isRoot).toList();

    if (root.isEmpty && asyncCategories.hasError) {
      return EmptyStateWidget(
        icon: Icons.error_outline_rounded,
        title: 'שגיאה בטעינת קטגוריות',
        subtitle: asyncCategories.error.toString(),
        tone: EmptyTone.danger,
      );
    }

    if (root.isEmpty && asyncCategories.isLoading) {
      return const CategoryListShimmer();
    }

    if (root.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.category_outlined,
        title: 'אין קטגוריות תואמות',
        subtitle:
            'נקה את החיפוש או הסר פילטרים. אם אין קטגוריות בכלל, הרץ את ה-backfill.',
        tone: EmptyTone.neutral,
      );
    }

    // ── Phase E-fix: ALWAYS use a Column for the list ────────────────────
    // `ReorderableListView.builder` with `shrinkWrap: true` + `NeverScrollable`
    // inside a scrollable parent ListView is fragile on Flutter Web — the
    // constraints race can leave the list with 0 height. We drop it and use
    // a plain Column; drag-reorder is deferred to Phase F until we can
    // migrate the whole main tab to `CustomScrollView + SliverReorderableList`.
    // The drag handle icon is kept for visual parity; it just doesn't trigger
    // reorder for now. Users can still rely on the "sort by" dropdown in the
    // toolbar for non-manual ordering.
    final children = <Widget>[];
    for (var i = 0; i < root.length; i++) {
      children.add(_RootItem(
        key: ValueKey('cat-${root[i].id}'),
        category: root[i],
        filtered: filtered,
        index: i,
        expandedId: expandedId,
        focusedId: focusedId,
        dragEnabled: false, // reorder temporarily disabled — see note above
        onToggleExpand: onToggleExpand,
        onConfirmDelete: onConfirmDelete,
        onEdit: onEdit,
      ));
    }
    return Column(children: children);
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
    required this.onEdit,
  });

  final CategoryV3Model category;
  final List<CategoryV3Model> filtered;
  final int index;
  final String? expandedId;
  final String? focusedId;
  final bool dragEnabled;
  final void Function(String) onToggleExpand;
  final Future<void> Function(CategoryV3Model) onConfirmDelete;
  final void Function(CategoryV3Model) onEdit;

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
              onEdit: () => onEdit(category),
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
                  onTapSub: (s) => onEdit(s),
                  onEditSub: (s) => onEdit(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

