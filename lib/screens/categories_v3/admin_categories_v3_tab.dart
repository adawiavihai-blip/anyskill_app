import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/categories_v3_controller.dart';
import 'models/category_v3_model.dart';
import 'models/promoted_banner.dart';
import 'widgets/banner_row_card.dart';
import 'widgets/category_row_card.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/kpi_metrics_row.dart';
import 'widgets/subcategory_grid.dart';
import 'widgets/toolbar_bar.dart';

/// v3 categories admin tab — Phase B core UI.
///
/// Layout (top → bottom):
///   1. Header strip — title + manual refresh chip + "v3" pill
///   2. KPI strip (5 cards)
///   3. Toolbar (search + sort + view switcher)
///   4. Promoted banners section (mock data Phase B — promoted_banners empty)
///   5. Categories list (root only, expand to inline sub-grid)
///
/// What's intentionally missing in Phase B (arrives in Phase C):
///   - Sparkline + funnel + coverage chip + health bar
///   - Drag-and-drop reorder
///   - Bulk actions bar
///   - Keyboard shortcuts
///   - Activity log + Command palette + Edit dialog (Phase D)
class AdminCategoriesV3Tab extends ConsumerWidget {
  const AdminCategoriesV3Tab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCategories = ref.watch(categoriesV3StreamProvider);
    final filtered = ref.watch(filteredCategoriesV3Provider);
    final kpis = ref.watch(categoriesKpisProvider);
    final state = ref.watch(categoriesV3ControllerProvider);
    final ctrl = ref.read(categoriesV3ControllerProvider.notifier);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F2),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
            children: [
              const _Header(),
              const SizedBox(height: 16),

              // KPI strip
              KpiMetricsRow(kpis: kpis),
              const SizedBox(height: 16),

              // Toolbar
              const ToolbarBar(),
              const SizedBox(height: 12),

              // Promoted banners section (mirror per Q5-A)
              const _SectionLabel(text: 'באנרים מקודמים'),
              const SizedBox(height: 8),
              const _PromotedBannersSection(),
              const SizedBox(height: 16),

              // Categories
              const _SectionLabel(text: 'קטגוריות'),
              const SizedBox(height: 8),
              _CategoriesList(
                asyncCategories: asyncCategories,
                filtered: filtered,
                expandedId: state.expandedCategoryId,
                onToggleExpand: ctrl.toggleExpand,
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
    // Phase B: render hardcoded mocks that mirror live home_tab values
    // (CLAUDE.md §35: AnyTasks banner is hardcoded; community heart banner
    // also hardcoded). When `promoted_banners` collection has live docs the
    // widget will read from there instead — wired in Phase D.
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

class _CategoriesList extends StatelessWidget {
  const _CategoriesList({
    required this.asyncCategories,
    required this.filtered,
    required this.expandedId,
    required this.onToggleExpand,
  });

  final AsyncValue<List<CategoryV3Model>> asyncCategories;
  final List<CategoryV3Model> filtered;
  final String? expandedId;
  final void Function(String) onToggleExpand;

  @override
  Widget build(BuildContext context) {
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
                'נקה את החיפוש או הסרת הפילטרים. אם אין קטגוריות בכלל, הרץ את הסקריפט backfill.',
            tone: EmptyTone.neutral,
          );
        }
        // Build root + inline expanded sub-grid for each
        final children = <Widget>[];
        for (final c in root) {
          children.add(CategoryRowCard(
            category: c,
            expanded: expandedId == c.id,
            onToggleExpand: () => onToggleExpand(c.id),
          ));
          if (expandedId == c.id) {
            final subs =
                filtered.where((s) => s.parentId == c.id).toList();
            children.add(Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: 8, end: 8, bottom: 12),
              child: SubcategoryGrid(
                parentId: c.id,
                subcategories: subs,
              ),
            ));
          }
        }
        return Column(children: children);
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
