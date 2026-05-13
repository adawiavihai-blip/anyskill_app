// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../../services/subcategory_banner_service.dart';
import '../../widgets/banners_admin/v3/design_tokens.dart';
import '../../widgets/banners_admin/v3/subcategory_widgets.dart';
import 'banner_edit_screen.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Banners Studio — Screen E (Subcategory Banners admin).
///
/// Per `docs/ui-specs/Baner/banners-mockup-v3.html` Screen E:
///   - Hero (blue/white): tag + title + 4 stats + 2 CTAs
///   - DefaultBannerCard (dashed) at the top
///   - Search box + filter pills
///   - CategoriesAccordion list — each root category expands to reveal
///     its subcategories with mini-thumbs + edit/add CTA
///
/// **Phase 4 surface (admin only — per blocker decision #3):**
///   - Configure pinned banners per subcategory (uses BannerEditScreen
///     with placement=subcategory).
///   - Configure the global default banner (single instance enforced
///     by the UI — admin can edit but cannot create a second).
///   - All data persists to `banners/{id}` with placement=subcategory.
///
/// **Customer-side rendering deferred** until a real subcategory drill-
/// down screen exists in the app. Per
/// [SubcategoryBannerService.getBannersForSubcategory] — its data
/// contract is ready; just waiting for a host UI to mount it.
/// ═══════════════════════════════════════════════════════════════════════════

class SubcategoryBannersScreen extends StatefulWidget {
  const SubcategoryBannersScreen({super.key});

  @override
  State<SubcategoryBannersScreen> createState() =>
      _SubcategoryBannersScreenState();
}

enum _Filter { all, withBanner, useDefault, highCtr }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'הכל',
        _Filter.withBanner => 'עם באנר ייעודי',
        _Filter.useDefault => 'בברירת מחדל',
        _Filter.highCtr => 'CTR גבוה',
      };
}

class _SubcategoryBannersScreenState
    extends State<SubcategoryBannersScreen> {
  CategoryTree? _tree;
  bool _loadingTree = true;
  String? _treeError;

  String _query = '';
  _Filter _filter = _Filter.all;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTree() async {
    setState(() {
      _loadingTree = true;
      _treeError = null;
    });
    try {
      final tree =
          await SubcategoryBannerService.instance.loadCategoryTree();
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loadingTree = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _treeError = e.toString();
        _loadingTree = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioColors.bg,
      appBar: AppBar(
        backgroundColor: StudioColors.bgElevated,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: StudioColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('באנרי תת-קטגוריות',
            style: StudioText.h3(),
            textDirection: TextDirection.rtl),
      ),
      body: StreamBuilder<List<BannerModel>>(
        stream: SubcategoryBannerService.instance.watchAll(),
        builder: (context, bannerSnap) {
          if (bannerSnap.hasError) {
            return _ErrorState(error: bannerSnap.error.toString());
          }
          final banners = bannerSnap.data ?? const <BannerModel>[];
          return _buildBody(context, banners);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<BannerModel> banners) {
    // Split into pinned-by-subcategory + the default.
    final pinnedBySubcat = <String, List<BannerModel>>{};
    BannerModel? defaultBanner;
    for (final b in banners) {
      if (b.isDefaultGlobalSubcat) {
        defaultBanner = b;
      } else if ((b.subcategoryId ?? '').isNotEmpty) {
        (pinnedBySubcat[b.subcategoryId!] ??= <BannerModel>[]).add(b);
      }
    }
    for (final list in pinnedBySubcat.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }

    // Stats for hero
    final totalSubcats = _tree?.totalSubcategories ?? 0;
    final withDedicated = pinnedBySubcat.length;
    final usingDefault = totalSubcats - withDedicated;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: StudioSpacing.s7, vertical: StudioSpacing.s6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(
                totalSubcats: totalSubcats,
                withDedicated: withDedicated,
                usingDefault: usingDefault,
                onCreatePinned: () => _openEditFor(null,
                    forSubcategory: null,
                    isDefault: false),
                onConfigDefault: () => _openEditFor(defaultBanner,
                    forSubcategory: null, isDefault: true),
              ),
              const SizedBox(height: StudioSpacing.s5),

              // Default banner card
              StudioDefaultBannerCard(
                defaultBanner: defaultBanner,
                subcategoriesUsingDefault: usingDefault,
                onEdit: () => _openEditFor(defaultBanner,
                    forSubcategory: null, isDefault: true),
                onCreate: () => _openEditFor(null,
                    forSubcategory: null, isDefault: true),
              ),

              const SizedBox(height: StudioSpacing.s6),

              // Search + filter
              _SearchAndFilters(
                query: _query,
                ctrl: _searchCtrl,
                onQuery: (v) => setState(() => _query = v.toLowerCase()),
                filter: _filter,
                onFilter: (f) => setState(() => _filter = f),
              ),

              const SizedBox(height: StudioSpacing.s4),

              // Categories list
              if (_loadingTree)
                const Padding(
                  padding: EdgeInsets.all(StudioSpacing.s8),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_treeError != null)
                _ErrorState(error: _treeError!)
              else if ((_tree?.categories.isEmpty ?? true))
                _EmptyTreeState(onRetry: _loadTree)
              else
                _Accordions(
                  tree: _tree!,
                  pinnedBySubcat: pinnedBySubcat,
                  query: _query,
                  filter: _filter,
                  onTapSubcategory: (sub, list) {
                    if (list.isEmpty) {
                      _openEditFor(null,
                          forSubcategory: sub, isDefault: false);
                    } else {
                      // Multi-banner case: open the first for editing.
                      // (Phase 4 scope — Phase 6 can show a chooser.)
                      _openEditFor(list.first,
                          forSubcategory: sub, isDefault: false);
                    }
                  },
                ),

              const SizedBox(height: StudioSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }

  /// Open the BannerEditScreen pre-loaded to edit/create a subcategory
  /// banner. The screen itself handles all the saving via the existing
  /// [BannersService].
  Future<void> _openEditFor(
    BannerModel? existing, {
    required SubcategoryNode? forSubcategory,
    required bool isDefault,
  }) async {
    BannerModel draft;
    if (existing != null) {
      draft = existing;
    } else {
      // Synthesise a fresh draft pre-set to subcategory placement.
      draft = BannerModel(
        id: '',
        type: BannerType.subcategory,
        isActive: false,
        designStyle: 'gradient',
        subcategoryId: forSubcategory?.id,
        isDefaultGlobalSubcat: isDefault,
        title: isDefault
            ? 'נותני השירות הטובים בתת-הקטגוריה'
            : (forSubcategory != null
                ? 'המאמנים המובילים · ${forSubcategory.name}'
                : ''),
        subtitle: 'מצא את הספק המתאים לך',
        color1: isDefault ? '2C5BA8' : '4A7BCF',
        color2: isDefault ? '4A7BCF' : '6B9DDB',
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BannerEditScreen(banner: draft),
      ),
    );
  }
}

// ─── Hero ───────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.totalSubcats,
    required this.withDedicated,
    required this.usingDefault,
    required this.onCreatePinned,
    required this.onConfigDefault,
  });
  final int totalSubcats;
  final int withDedicated;
  final int usingDefault;
  final VoidCallback onCreatePinned;
  final VoidCallback onConfigDefault;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFFE9F0FB),
            Color(0xFFFAFBFE),
            Color(0xFFFFFFFF),
          ],
        ),
        borderRadius: BorderRadius.circular(StudioRadius.xl),
        border: Border.all(color: StudioColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: StudioColors.infoBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '📁 חדש · באנרי תת-קטגוריות',
                        style: StudioText.chip(color: StudioColors.info),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'באנר אישי לכל תת-קטגוריה',
                      style: StudioText.display().copyWith(fontSize: 28),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'הגדר באנר ייעודי לכל תת-קטגוריה (כושר, יופי, בית, חינוך…). תת-קטגוריות ללא באנר יציגו את ברירת המחדל הגלובלית.',
                      style: StudioText.body(color: StudioColors.ink3),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: StudioSpacing.s5),
              Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: onCreatePinned,
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('באנר תת-קטגוריה חדש'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioColors.ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(StudioRadius.sm)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onConfigDefault,
                    icon: const Icon(Icons.tune_rounded, size: 14),
                    label: const Text('הגדרות גלובליות'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StudioColors.ink2,
                      side: const BorderSide(color: StudioColors.line2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(StudioRadius.sm)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: StudioSpacing.s6),
          // Stats row
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: StudioSpacing.s5, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(StudioRadius.md),
              border: Border.all(color: StudioColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                    child: _Stat(
                        label: 'סה״כ תת-קטגוריות',
                        value: '$totalSubcats')),
                Container(
                    width: 1, height: 32, color: StudioColors.line),
                Expanded(
                    child: _Stat(
                        label: 'עם באנר ייעודי',
                        value: '$withDedicated',
                        accent: StudioColors.success)),
                Container(
                    width: 1, height: 32, color: StudioColors.line),
                Expanded(
                    child: _Stat(
                        label: 'בברירת מחדל',
                        value: '$usingDefault',
                        accent: StudioColors.info)),
                Container(
                    width: 1, height: 32, color: StudioColors.line),
                Expanded(
                    child: _Stat(
                        label: 'CTR ממוצע',
                        value: '—')), // Aggregation infra deferred to Phase 6
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.accent,
  });
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: StudioText.captionSm(),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: StudioText.metricMd(color: accent ?? StudioColors.ink)
              .copyWith(fontSize: 22),
        ),
      ],
    );
  }
}

// ─── Search + filters ───────────────────────────────────────────────────────

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.query,
    required this.ctrl,
    required this.onQuery,
    required this.filter,
    required this.onFilter,
  });
  final String query;
  final TextEditingController ctrl;
  final ValueChanged<String> onQuery;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: StudioSpacing.s3,
      runSpacing: StudioSpacing.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search
        SizedBox(
          width: 320,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: StudioColors.bgElevated,
              border: Border.all(color: StudioColors.line2),
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 16, color: StudioColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    onChanged: onQuery,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'חפש תת-קטגוריה...',
                    ),
                    style: StudioText.body(color: StudioColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Filter pills
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: StudioColors.bgElevated,
            border: Border.all(color: StudioColors.line),
            borderRadius: BorderRadius.circular(StudioRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in _Filter.values)
                _Pill(
                  label: f.label,
                  active: f == filter,
                  onTap: () => onFilter(f),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? StudioColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active ? StudioShadows.sh1 : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : StudioColors.ink3,
          ),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

// ─── Accordions list (filtered) ─────────────────────────────────────────────

class _Accordions extends StatelessWidget {
  const _Accordions({
    required this.tree,
    required this.pinnedBySubcat,
    required this.query,
    required this.filter,
    required this.onTapSubcategory,
  });
  final CategoryTree tree;
  final Map<String, List<BannerModel>> pinnedBySubcat;
  final String query;
  final _Filter filter;
  final void Function(SubcategoryNode, List<BannerModel>)
      onTapSubcategory;

  @override
  Widget build(BuildContext context) {
    final categories = tree.categories
        .map((c) {
          final filteredSubs = c.subcategories.where((s) {
            // Query filter
            if (query.isNotEmpty &&
                !s.name.toLowerCase().contains(query)) {
              return false;
            }
            // Type filter
            switch (filter) {
              case _Filter.all:
                return true;
              case _Filter.withBanner:
                return (pinnedBySubcat[s.id] ?? const []).isNotEmpty;
              case _Filter.useDefault:
                return (pinnedBySubcat[s.id] ?? const []).isEmpty;
              case _Filter.highCtr:
                // Aggregation infra deferred — show all under this filter
                // with a soft "אין נתוני CTR עדיין" hint at the screen
                // level. For now we treat it like "all".
                return true;
            }
          }).toList();
          return CategoryNode(
            id: c.id,
            name: c.name,
            emoji: c.emoji,
            subcategories: filteredSubs,
          );
        })
        .where((c) => c.subcategories.isNotEmpty)
        .toList();

    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(StudioSpacing.s7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 32, color: StudioColors.ink4),
              const SizedBox(height: 12),
              Text(
                query.isEmpty
                    ? 'אין תת-קטגוריות התואמות לסינון'
                    : 'לא נמצאו תוצאות עבור "$query"',
                style: StudioText.body(color: StudioColors.ink3),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < categories.length; i++) ...[
          if (i > 0) const SizedBox(height: StudioSpacing.s3),
          StudioCategoryAccordion(
            category: categories[i],
            subcategoryBanners: pinnedBySubcat,
            initiallyOpen: i == 0, // Open the first one by default
            onTapSubcategory: onTapSubcategory,
          ),
        ],
      ],
    );
  }
}

class _EmptyTreeState extends StatelessWidget {
  const _EmptyTreeState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s7),
      decoration: studioCard(radius: StudioRadius.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_off_outlined,
              size: 36, color: StudioColors.ink4),
          const SizedBox(height: 12),
          Text(
            'לא נמצאו קטגוריות',
            style: StudioText.h3(),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 4),
          Text(
            'נראה שאין עדיין קטגוריות במערכת. הוסף קטגוריות בלשונית "קטגוריות" ואז חזור לכאן.',
            textAlign: TextAlign.center,
            style: StudioText.captionSm(),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudioSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 32, color: StudioColors.ink4),
            const SizedBox(height: StudioSpacing.s3),
            Text('שגיאה בטעינה', style: StudioText.h3()),
            const SizedBox(height: 4),
            Text(error, style: StudioText.captionSm()),
          ],
        ),
      ),
    );
  }
}
