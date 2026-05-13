// ignore_for_file: use_build_context_synchronously
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../../services/banners_service.dart';
import '../../widgets/banners_admin/v3/ai_insight_card.dart';
import '../../widgets/banners_admin/v3/banner_table_row.dart';
import '../../widgets/banners_admin/v3/design_tokens.dart';
import '../../widgets/banners_admin/v3/kpi_card.dart';
import '../../widgets/banners_admin/v3/placement_card.dart';
import 'banner_edit_screen.dart';
import 'subcategory_banners_screen.dart';
import 'vip_management_screen.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Banners Studio — Screen A (Dashboard).
///
/// The new admin "Studio ✨" tab. Lives alongside the legacy v1/v2/VIP
/// tabs during the Phase 1 rollout (CLAUDE.md §49 + Plan agent decision —
/// nothing gets deleted until Phase 5).
///
/// Layout matches `docs/ui-specs/Baner/banners-mockup-v3.html` Screen A:
///   - Page header (title + sub + 3 actions)
///   - KPI strip (4 cards)
///   - Section "4 מיקומים פעילים" → 4 Placement Cards (VIP featured)
///   - Section "כל הבאנרים" → tabs + filters + bulk-bar + table
///   - AI insight card (gold)
///
/// **Phase-1 button contract (per the user's spec — every button leads
/// somewhere):**
///   - Toggle on a row → real Firestore `isActive` flip.
///   - "באנר חדש" → snackbar "ייפתח עורך מלא בפאזה 2" (the wizard isn't
///     ready yet; Phase 2 builds it).
///   - Row click → same Phase-2 snackbar.
///   - Placement card → either filters the table (home/wallet) OR shows
///     a "בקרוב — פאזה N" snackbar (vip/subcat).
///   - Bulk actions → all real Firestore writes (toggle + delete +
///     duplicate). The action bar disappears when nothing is selected.
///   - Filter tabs → real client-side status filter.
///   - "ייצוא דוח", "תבניות" → snackbar "בקרוב".
/// ═══════════════════════════════════════════════════════════════════════════

class AdminBannersDashboardScreen extends StatefulWidget {
  const AdminBannersDashboardScreen({super.key});

  @override
  State<AdminBannersDashboardScreen> createState() =>
      _AdminBannersDashboardScreenState();
}

enum _StatusFilter { all, active, scheduled, draft }

extension on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => 'הכל',
        _StatusFilter.active => 'פעילים',
        _StatusFilter.scheduled => 'מתוזמנים',
        _StatusFilter.draft => 'טיוטות',
      };

  bool matches(BannerStatus s) => switch (this) {
        _StatusFilter.all => true,
        _StatusFilter.active => s == BannerStatus.active,
        _StatusFilter.scheduled => s == BannerStatus.scheduled,
        _StatusFilter.draft => s == BannerStatus.draft,
      };
}

class _AdminBannersDashboardScreenState
    extends State<AdminBannersDashboardScreen> {
  _StatusFilter _statusFilter = _StatusFilter.all;
  BannerType? _placementFilter;
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return Container(
      color: StudioColors.bg,
      // Local error boundary that catches DESCENDANT build errors inside
      // the dashboard subtree. Without this, a child widget's build()
      // failure (e.g. an unguarded `!` in a sub-widget) bubbles up to
      // Flutter's framework, increments the global ErrorBoundary's
      // counter (main.dart:644), and at 10+ throws the user lands on
      // the global "משהו השתבש" crash screen.
      //
      // This boundary keeps the crash CONTAINED inside the Banners tab —
      // the user sees a friendly retry UI, the rest of the admin shell
      // keeps working, and the actual exception lands in the console
      // (and Sentry/Crashlytics via the global FlutterError.onError).
      child: _BannersErrorBoundary(
        child: StreamBuilder<List<BannerModel>>(
          stream: BannersService.instance.watchAll(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorState(
                error: snap.error.toString(),
                onRetry: () => setState(() {}),
              );
            }
            final all = snap.data ?? const <BannerModel>[];
            if (snap.connectionState == ConnectionState.waiting &&
                snap.data == null) {
              return const _LoadingState();
            }
            try {
              final filtered = _applyFilters(all);
              final visibleIds = filtered.map((b) => b.id).toSet();
              final stale = _selectedIds.difference(visibleIds);
              if (stale.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _selectedIds.removeAll(stale));
                });
              }
              return _buildBody(context, all, filtered);
            } catch (e, st) {
              // ignore: avoid_print
              print('[BannersStudio] build crashed: $e\n$st');
              return _ErrorState(
                error: 'שגיאה בבניית המסך — נסה לרענן.\n$e',
                onRetry: () => setState(() {}),
              );
            }
          },
        ),
      ),
    );
  }

  List<BannerModel> _applyFilters(List<BannerModel> all) {
    return all.where((b) {
      if (!_statusFilter.matches(b.status)) return false;
      if (_placementFilter != null && b.type != _placementFilter) return false;
      return true;
    }).toList();
  }

  Widget _buildBody(BuildContext context, List<BannerModel> all,
      List<BannerModel> filtered) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: StudioSpacing.s8,
        vertical: StudioSpacing.s7,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(
                totalCount: all.length,
                activeCount:
                    all.where((b) => b.status == BannerStatus.active).length,
                onNewBanner: () => _openEditScreen(null),
                onExport: () => _comingSoon('ייצוא דוח'),
                onTemplates: () => _comingSoon('תבניות'),
              ),
              const SizedBox(height: StudioSpacing.s7),

              // ── KPI strip ───────────────────────────────────────
              _KpiStrip(banners: all),
              const SizedBox(height: StudioSpacing.s7),

              // ── Section: 4 placements ───────────────────────────
              _SectionHead(
                title: '4 מיקומים פעילים',
                sub: 'לחץ על כרטיס לעבור לניהול ייעודי',
              ),
              const SizedBox(height: StudioSpacing.s5),
              _PlacementsGrid(
                banners: all,
                onTapVip: _openVipScreen,
                onTapStandard: () => _filterByPlacement(BannerType.homeCarousel),
                onTapSubcategory: _openSubcategoryScreen,
                onTapWallet: () => _filterByPlacement(BannerType.wallet),
              ),

              const SizedBox(height: StudioSpacing.s9),

              // ── Section: all banners table ──────────────────────
              _SectionHead(
                title: 'כל הבאנרים',
                sub: '${all.length} באנרים · נטענו לעיצוב החדש',
              ),
              const SizedBox(height: StudioSpacing.s5),

              // Toolbar
              _Toolbar(
                statusFilter: _statusFilter,
                onStatusChange: (s) => setState(() => _statusFilter = s),
                placementFilter: _placementFilter,
                onPlacementChange: _onPlacementFilterChange,
                tabCounts: _tabCounts(all),
              ),
              const SizedBox(height: StudioSpacing.s4),

              // Bulk action bar (only when something is selected)
              if (_selectedIds.isNotEmpty) ...[
                _BulkBar(
                  count: _selectedIds.length,
                  onActivate: () => _bulkSetActive(true),
                  onDeactivate: () => _bulkSetActive(false),
                  onDelete: () => _bulkDelete(),
                  onCancel: () => setState(_selectedIds.clear),
                ),
                const SizedBox(height: StudioSpacing.s4),
              ],

              // Table
              _BannersTable(
                rows: filtered,
                selectedIds: _selectedIds,
                onToggleSelect: (id, sel) {
                  setState(() {
                    if (sel) {
                      _selectedIds.add(id);
                    } else {
                      _selectedIds.remove(id);
                    }
                  });
                },
                onToggleAll: (next) {
                  setState(() {
                    if (next) {
                      _selectedIds
                        ..clear()
                        ..addAll(filtered.map((b) => b.id));
                    } else {
                      _selectedIds.clear();
                    }
                  });
                },
                onTapRow: (b) => _openEditScreen(b),
                onToggleActive: _onToggleActive,
                onDuplicate: _onDuplicate,
                onMore: (b) => _phase2Snack('תפריט פעולות מורחב'),
              ),

              const SizedBox(height: StudioSpacing.s8),

              // ── AI insight ──────────────────────────────────────
              StreamBuilder<AiInsight?>(
                stream: BannersService.instance.watchAiInsight(),
                builder: (context, snap) {
                  return StudioAiInsightCard(
                    insight: snap.data,
                    onAction: _openVipScreen,
                  );
                },
              ),

              const SizedBox(height: StudioSpacing.s9),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Filter helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Push the BannerEditScreen for an existing banner (or null = new).
  /// On pop, the screen returns the saved [BannerModel] (or null if
  /// discarded) — the StreamBuilder picks up the change automatically
  /// from Firestore so we don't need the result here.
  Future<void> _openEditScreen(BannerModel? banner) async {
    await Navigator.of(context).push<BannerModel?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BannerEditScreen(banner: banner),
      ),
    );
  }

  void _filterByPlacement(BannerType type) {
    setState(() {
      _placementFilter = (_placementFilter == type) ? null : type;
    });
  }

  void _onPlacementFilterChange(BannerType? next) {
    setState(() => _placementFilter = next);
  }

  Map<_StatusFilter, int> _tabCounts(List<BannerModel> all) {
    final counts = <_StatusFilter, int>{};
    for (final s in _StatusFilter.values) {
      counts[s] = all.where((b) => s.matches(b.status)).length;
    }
    return counts;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mutation helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onToggleActive(BannerModel b, bool next) async {
    try {
      await BannersService.instance.setActive(b.id, next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('עדכון נכשל: $e')),
      );
    }
  }

  Future<void> _onDuplicate(BannerModel b) async {
    try {
      await BannersService.instance.duplicate(b);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${b.title}" שוכפל כטיוטה')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שכפול נכשל: $e')),
      );
    }
  }

  Future<void> _bulkSetActive(bool active) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    // Clear selection FIRST so the BulkBar dismisses immediately —
    // gives the admin instant visual feedback that the action started.
    setState(_selectedIds.clear);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BannersService.instance.bulkSetActive(ids, active);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              '${ids.length} באנרים ${active ? "הופעלו" : "הושבתו"}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('פעולה נכשלה: $e')),
      );
    }
  }

  Future<void> _bulkDelete() async {
    // ignore: avoid_print
    print('[BulkDelete] called, selected=${_selectedIds.length}');
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      // ignore: avoid_print
      print('[BulkDelete] empty selection — abort');
      return;
    }

    // Step 1 — confirm. `useRootNavigator: true` so the dialog hosts
    // on the app's top-level Navigator (not on any nested tab one).
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('מחיקת באנרים'),
        content: Text('למחוק ${ids.length} באנרים? פעולה בלתי הפיכה.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: StudioColors.danger),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    // ignore: avoid_print
    print('[BulkDelete] confirm dialog returned: $confirmed');

    if (confirmed != true) return;
    if (!mounted) {
      // ignore: avoid_print
      print('[BulkDelete] not mounted after confirm — abort');
      return;
    }

    // Step 2 — clear selection so BulkBar dismisses INSTANTLY.
    setState(_selectedIds.clear);

    // Step 3 — show a non-dismissible spinner while we delete. Auto-
    // closes when bulkDelete returns (success or fail). Same root
    // navigator so it doesn't get trapped under the dashboard tab.
    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );

    try {
      // ignore: avoid_print
      print('[BulkDelete] calling bulkDelete with ${ids.length} ids');
      await BannersService.instance.bulkDelete(ids);
      // ignore: avoid_print
      print('[BulkDelete] bulkDelete succeeded');
      if (rootNav.canPop()) rootNav.pop(); // dismiss spinner
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${ids.length} באנרים נמחקו')),
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('[BulkDelete] FAILED: $e\n$st');
      if (rootNav.canPop()) rootNav.pop();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: StudioColors.danger,
          content: Text('מחיקה נכשלה: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snackbars for not-yet-implemented-in-this-phase actions
  // ─────────────────────────────────────────────────────────────────────────

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$what" — בקרוב'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _phase2Snack(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$what — ייפתח בפאזה 2 (עורך באנרים)'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Push the VIP Management screen (Phase 3 — Screen C).
  Future<void> _openVipScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VipManagementScreen()),
    );
  }

  /// Push the Subcategory Banners admin screen (Phase 4 — Screen E).
  Future<void> _openSubcategoryScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SubcategoryBannersScreen(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.totalCount,
    required this.activeCount,
    required this.onNewBanner,
    required this.onExport,
    required this.onTemplates,
  });

  final int totalCount;
  final int activeCount;
  final VoidCallback onNewBanner;
  final VoidCallback onExport;
  final VoidCallback onTemplates;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: StudioSpacing.s6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: StudioColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Single Text widget instead of RichText / Row of Texts.
                // Text auto-merges with the ambient DefaultTextStyle
                // (Material's Theme), so the Assistant fontFamily is
                // resolved correctly. Avoiding Row+baseline removes any
                // risk of a missing-baseline null check on web.
                Text(
                  'באנרים · Studio',
                  style: StudioText.display(),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const _LiveDot(),
                    const SizedBox(width: 8),
                    Text(
                      '$totalCount באנרים',
                      style: StudioText.body()
                          .copyWith(fontWeight: FontWeight.w500),
                      textDirection: TextDirection.rtl,
                    ),
                    Text(
                      ' · $activeCount פעילים · ',
                      style: StudioText.body(color: StudioColors.ink3),
                      textDirection: TextDirection.rtl,
                    ),
                    Text(
                      'מסונכרן עם Firestore',
                      style: StudioText.body(color: StudioColors.ink3),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SecondaryButton(
            icon: Icons.file_download_outlined,
            label: 'ייצוא דוח',
            onPressed: onExport,
          ),
          const SizedBox(width: StudioSpacing.s2),
          _SecondaryButton(
            icon: Icons.description_outlined,
            label: 'תבניות',
            onPressed: onTemplates,
          ),
          const SizedBox(width: StudioSpacing.s2),
          _PrimaryButton(
            icon: Icons.add_rounded,
            label: 'באנר חדש',
            onPressed: onNewBanner,
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 14×14 box gives the pulsing halo (max scale ≈ 2x of 7px) room
    // to render. Both children are unpositioned — Stack alignment
    // centres them. Avoids the empty-Positioned anti-pattern that
    // failed in the prod build (renders crashed mid-build).
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          final scale = 1.0 + (t < 0.5 ? t : 1.0 - t) * 1.0;
          final opacity = t < 0.5 ? 0.3 : 0.0;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 7 * scale,
                height: 7 * scale,
                decoration: BoxDecoration(
                  color: StudioColors.success.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: StudioColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, textDirection: TextDirection.rtl),
      style: ElevatedButton.styleFrom(
        backgroundColor: StudioColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: StudioText.bodyMedium(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: StudioColors.ink2),
      label: Text(
        label,
        textDirection: TextDirection.rtl,
        style: StudioText.bodyMedium(color: StudioColors.ink2),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: StudioColors.bgElevated,
        side: const BorderSide(color: StudioColors.line2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KPI STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.banners});
  final List<BannerModel> banners;

  @override
  Widget build(BuildContext context) {
    final totalImpressions = banners.fold<int>(0, (a, b) => a + b.impressions);
    final totalClicks = banners.fold<int>(0, (a, b) => a + b.clicks);
    final ctr = totalImpressions == 0
        ? null
        : (totalClicks / totalImpressions) * 100;
    final vipRevenue = banners
        .where((b) => b.type == BannerType.providerCarousel)
        .fold<double>(0, (a, b) => a + b.attributedRevenue);

    String compact(int n) {
      if (n < 1000) return '$n';
      if (n < 1000000) {
        final k = n / 1000;
        return k >= 100
            ? '${k.toStringAsFixed(0)}K'
            : '${k.toStringAsFixed(k >= 10 ? 0 : 1)}K';
      }
      return '${(n / 1000000).toStringAsFixed(1)}M';
    }

    String compactMoney(double v) {
      if (v < 1000) return v.toStringAsFixed(0);
      if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}K';
      return '${(v / 1000000).toStringAsFixed(1)}M';
    }

    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: StudioSpacing.s4,
      crossAxisSpacing: StudioSpacing.s4,
      childAspectRatio: 2.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        StudioKpiCard(
          label: 'חשיפות (סה״כ)',
          valueText: totalImpressions == 0 ? '—' : compact(totalImpressions),
        ),
        StudioKpiCard(
          label: 'הקלקות (סה״כ)',
          valueText: totalClicks == 0 ? '—' : compact(totalClicks),
        ),
        StudioKpiCard(
          label: 'CTR ממוצע',
          valueText: ctr == null ? '—' : '${ctr.toStringAsFixed(2)}%',
        ),
        StudioKpiCard(
          label: 'הכנסה מ-VIP',
          valueText: vipRevenue == 0 ? '—' : '₪${compactMoney(vipRevenue)}',
          accent: true,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLACEMENTS GRID
// ═══════════════════════════════════════════════════════════════════════════

class _PlacementsGrid extends StatelessWidget {
  const _PlacementsGrid({
    required this.banners,
    required this.onTapVip,
    required this.onTapStandard,
    required this.onTapSubcategory,
    required this.onTapWallet,
  });

  final List<BannerModel> banners;
  final VoidCallback onTapVip;
  final VoidCallback onTapStandard;
  final VoidCallback onTapSubcategory;
  final VoidCallback onTapWallet;

  @override
  Widget build(BuildContext context) {
    final vip = banners
        .where((b) => b.type == BannerType.providerCarousel)
        .toList();
    final home = banners
        .where((b) => b.type == BannerType.homeCarousel)
        .toList();
    final wallet =
        banners.where((b) => b.type == BannerType.wallet).toList();

    final activeVip = vip.where((b) => b.isActive).length;
    final activeHome = home.where((b) => b.isActive).length;
    final activeWallet = wallet.where((b) => b.isActive).length;

    final vipProviderCount = vip
        .map((b) => b.providerCarousel?.providerIds.length ?? 0)
        .fold<int>(0, (a, n) => a + n);

    final vipCtr = _ctr(vip);
    final homeCtr = _ctr(home);
    final walletCtr = _ctr(wallet);

    final vipRevenue =
        vip.fold<double>(0, (a, b) => a + b.attributedRevenue);

    String compactMoney(double v) {
      if (v < 1000) return v.toStringAsFixed(0);
      if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}k';
      return '${(v / 1000000).toStringAsFixed(1)}M';
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Mockup: 1.4fr 1fr 1fr 1fr at desktop. Below ~1100px: 2-col.
        final isWide = c.maxWidth >= 1100;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 14,
                child: _vipCard(
                  activeVip: activeVip,
                  providerCount: vipProviderCount,
                  ctr: vipCtr,
                  revenue: vipRevenue,
                  compactMoney: compactMoney,
                ),
              ),
              const SizedBox(width: StudioSpacing.s3),
              Expanded(
                flex: 10,
                child: _standardCard(active: activeHome, ctr: homeCtr),
              ),
              const SizedBox(width: StudioSpacing.s3),
              Expanded(
                flex: 10,
                child: _subcategoryCard(),
              ),
              const SizedBox(width: StudioSpacing.s3),
              Expanded(
                flex: 10,
                child: _walletCard(active: activeWallet, ctr: walletCtr),
              ),
            ],
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: StudioSpacing.s3,
          crossAxisSpacing: StudioSpacing.s3,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _vipCard(
              activeVip: activeVip,
              providerCount: vipProviderCount,
              ctr: vipCtr,
              revenue: vipRevenue,
              compactMoney: compactMoney,
            ),
            _standardCard(active: activeHome, ctr: homeCtr),
            _subcategoryCard(),
            _walletCard(active: activeWallet, ctr: walletCtr),
          ],
        );
      },
    );
  }

  double? _ctr(List<BannerModel> set) {
    final imps = set.fold<int>(0, (a, b) => a + b.impressions);
    final clk = set.fold<int>(0, (a, b) => a + b.clicks);
    if (imps == 0) return null;
    return (clk / imps) * 100;
  }

  Widget _vipCard({
    required int activeVip,
    required int providerCount,
    required double? ctr,
    required double revenue,
    required String Function(double) compactMoney,
  }) {
    return StudioPlacementCard(
      featured: true,
      icon: Icons.star_rounded,
      tier: '⭐ Premium · VIP',
      name: 'קרוסלת ספקים',
      where: 'בראש לשונית בית · 99₪/חודש לספק',
      statusLabel: activeVip > 0 ? 'פועל' : 'כבוי',
      onTap: onTapVip,
      preview: const _VipPreview(),
      stats: [
        StudioPlacementStat(
          label: 'ספקים',
          value: '$providerCount/30',
        ),
        StudioPlacementStat(
          label: 'CTR',
          value: ctr == null ? '—' : '${ctr.toStringAsFixed(1)}%',
        ),
        StudioPlacementStat(
          label: 'הכנסה',
          value: revenue == 0 ? '—' : '₪${compactMoney(revenue)}',
        ),
      ],
    );
  }

  Widget _standardCard({required int active, required double? ctr}) {
    return StudioPlacementCard(
      icon: Icons.send_outlined,
      tier: 'Standard',
      name: 'באנרי קידום',
      where: 'בלשונית בית',
      statusLabel: '$active פעילים',
      onTap: onTapStandard,
      preview: const _PromoPreview(
        title: 'נותני שירות מהשורה הראשונה',
        subtitle: 'צפה בכל הקטגוריות →',
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1A6B5B), Color(0xFF2A8F77)],
        ),
      ),
      stats: [
        StudioPlacementStat(label: 'פעילים', value: '$active'),
        StudioPlacementStat(
          label: 'CTR',
          value: ctr == null ? '—' : '${ctr.toStringAsFixed(1)}%',
        ),
        const StudioPlacementStat(label: 'מיקום', value: 'בית'),
      ],
    );
  }

  Widget _subcategoryCard() {
    return StudioPlacementCard(
      icon: Icons.folder_open_rounded,
      tier: 'חדש · קטגוריות',
      name: 'תתי-קטגוריות',
      where: 'בראש מסך תת-קטגוריה',
      statusLabel: 'בקרוב — פאזה 4',
      onTap: onTapSubcategory,
      preview: const _PromoPreview(
        title: 'המאמנים הטובים',
        subtitle: 'בחר מאמן מומלץ',
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2C5BA8), Color(0xFF4A7BCF)],
        ),
      ),
      stats: const [
        StudioPlacementStat(label: 'תת-קטגוריות', value: '52'),
        StudioPlacementStat(label: 'עם באנר', value: '0'),
        StudioPlacementStat(label: 'CTR', value: '—'),
      ],
    );
  }

  Widget _walletCard({required int active, required double? ctr}) {
    return StudioPlacementCard(
      icon: Icons.account_balance_wallet_outlined,
      tier: 'Wallet',
      name: 'באנר ארנק',
      where: 'למעלה במסך הארנק',
      statusLabel: active > 0 ? 'פועל' : 'כבוי',
      onTap: onTapWallet,
      preview: const _PromoPreview(
        title: 'הזמן ושלם בקלות',
        subtitle: 'הוסף אמצעי תשלום',
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF4A2A6E), Color(0xFF6B3A8F)],
        ),
      ),
      stats: [
        StudioPlacementStat(label: 'פעילים', value: '$active'),
        StudioPlacementStat(
          label: 'CTR',
          value: ctr == null ? '—' : '${ctr.toStringAsFixed(1)}%',
        ),
        const StudioPlacementStat(label: 'מיקום', value: 'ארנק'),
      ],
    );
  }
}

// ─── Mini-previews used inside Placement Cards ────────────────────────────

class _VipPreview extends StatelessWidget {
  const _VipPreview();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          for (int i = 0; i < 4; i++) ...[
            Expanded(
              flex: i == 1 ? 2 : 1,
              child: _vipMini(active: i == 1),
            ),
            if (i < 3) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _vipMini({required bool active}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2C2519), Color(0xFF1A1A1A)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? StudioColors.gold
              : StudioColors.gold.withValues(alpha: 0.2),
          width: active ? 1.5 : 1,
        ),
        boxShadow: active
            ? [
                const BoxShadow(
                  color: Color(0x4DB89855),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: active
          ? Stack(
              children: [
                PositionedDirectional(
                  bottom: 6,
                  end: 6,
                  child: Row(
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: StudioColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (i < 2) const SizedBox(width: 2),
                      ],
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _PromoPreview extends StatelessWidget {
  const _PromoPreview({
    required this.title,
    required this.subtitle,
    required this.gradient,
  });
  final String title;
  final String subtitle;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 0),
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xD9FFFFFF),
                fontSize: 10,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION HEAD + TOOLBAR
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.sub});
  final String title;
  final String sub;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: StudioText.h2(), textDirection: TextDirection.rtl),
        const SizedBox(height: 4),
        Text(sub, style: StudioText.body(color: StudioColors.ink3),
            textDirection: TextDirection.rtl),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.statusFilter,
    required this.onStatusChange,
    required this.placementFilter,
    required this.onPlacementChange,
    required this.tabCounts,
  });
  final _StatusFilter statusFilter;
  final ValueChanged<_StatusFilter> onStatusChange;
  final BannerType? placementFilter;
  final ValueChanged<BannerType?> onPlacementChange;
  final Map<_StatusFilter, int> tabCounts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: StudioSpacing.s3,
      runSpacing: StudioSpacing.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Status tabs
        Container(
          decoration: BoxDecoration(
            color: StudioColors.bgElevated,
            borderRadius: BorderRadius.circular(StudioRadius.sm),
            border: Border.all(color: StudioColors.line),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in _StatusFilter.values)
                _Tab(
                  label: s.label,
                  count: tabCounts[s] ?? 0,
                  active: s == statusFilter,
                  onTap: () => onStatusChange(s),
                ),
            ],
          ),
        ),
        // Placement filter pill
        _FilterPill(
          icon: Icons.filter_list_rounded,
          label: placementFilter == null
              ? 'מיקום: הכל'
              : 'מיקום: ${placementFilter!.hebrewLabel}',
          onPressed: () => _showPlacementMenu(context),
        ),
      ],
    );
  }

  void _showPlacementMenu(BuildContext context) async {
    final selected = await showMenu<BannerType?>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
      items: [
        const PopupMenuItem(value: null, child: Text('הכל')),
        for (final t in BannerType.values)
          PopupMenuItem(value: t, child: Text(t.hebrewLabel)),
      ],
    );
    onPlacementChange(selected);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? StudioColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active ? StudioShadows.sh1 : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: StudioText.bodyMedium(
                color: active ? Colors.white : StudioColors.ink3,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.18)
                    : StudioColors.bgSubtle,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: StudioText.chip(
                  color: active ? Colors.white : StudioColors.ink3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.sm),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: StudioColors.bgElevated,
          border: Border.all(color: StudioColors.line2),
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: StudioColors.ink3),
            const SizedBox(width: 6),
            Text(label,
                style: StudioText.bodyMedium(),
                textDirection: TextDirection.rtl),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BULK BAR
// ═══════════════════════════════════════════════════════════════════════════

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.onActivate,
    required this.onDeactivate,
    required this.onDelete,
    required this.onCancel,
  });
  final int count;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: StudioColors.ink,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        boxShadow: StudioShadows.sh3,
      ),
      child: Row(
        children: [
          Text(
            '$count נבחרו',
            style: StudioText.bodyMedium(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(width: StudioSpacing.s4),
          _BulkBtn(label: '▶ הפעל', onPressed: onActivate),
          const SizedBox(width: StudioSpacing.s2),
          _BulkBtn(label: '⏸ השבת', onPressed: onDeactivate),
          const Spacer(),
          _BulkBtn(label: '🗑 מחק', onPressed: onDelete, danger: true),
          const SizedBox(width: StudioSpacing.s2),
          _BulkBtn(label: 'בטל', onPressed: onCancel),
        ],
      ),
    );
  }
}

class _BulkBtn extends StatelessWidget {
  const _BulkBtn({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.xs),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: danger
              ? StudioColors.danger.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: danger ? Colors.white : Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TABLE
// ═══════════════════════════════════════════════════════════════════════════

class _BannersTable extends StatelessWidget {
  const _BannersTable({
    required this.rows,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onToggleAll,
    required this.onTapRow,
    required this.onToggleActive,
    required this.onDuplicate,
    required this.onMore,
  });
  final List<BannerModel> rows;
  final Set<String> selectedIds;
  final void Function(String, bool) onToggleSelect;
  final ValueChanged<bool> onToggleAll;
  final ValueChanged<BannerModel> onTapRow;
  final void Function(BannerModel, bool) onToggleActive;
  final ValueChanged<BannerModel> onDuplicate;
  final ValueChanged<BannerModel> onMore;

  @override
  Widget build(BuildContext context) {
    final allSelected =
        rows.isNotEmpty && rows.every((b) => selectedIds.contains(b.id));
    final someSelected =
        rows.any((b) => selectedIds.contains(b.id));

    return ClipRRect(
      borderRadius: BorderRadius.circular(StudioRadius.lg),
      child: Container(
        decoration: studioCard(radius: StudioRadius.lg),
        child: Column(
          children: [
            StudioBannerTableHeader(
              allSelected: allSelected,
              someSelected: someSelected,
              onToggleAll: onToggleAll,
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(StudioSpacing.s8),
                child: Center(
                  child: Text(
                    'אין באנרים בסינון הנוכחי',
                    style: StudioText.body(color: StudioColors.ink3),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            for (final b in rows)
              StudioBannerTableRow(
                key: ValueKey(b.id),
                banner: b,
                selected: selectedIds.contains(b.id),
                onToggleSelect: (sel) => onToggleSelect(b.id, sel),
                onTap: () => onTapRow(b),
                onToggleActive: (next) => onToggleActive(b, next),
                onDuplicate: () => onDuplicate(b),
                onMore: () => onMore(b),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOADING / ERROR
// ═══════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(StudioSpacing.s8),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
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
            Text('שגיאה בטעינת הבאנרים', style: StudioText.h3()),
            const SizedBox(height: 4),
            Text(error, style: StudioText.captionSm()),
            const SizedBox(height: StudioSpacing.s4),
            FilledButton(onPressed: onRetry, child: const Text('נסה שוב')),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOCAL ERROR BOUNDARY
// ═══════════════════════════════════════════════════════════════════════════
//
// Mirrors the global `_ErrorBoundary` in main.dart but scoped to the
// Banners dashboard subtree. Hooks into `FlutterError.onError` so that
// any descendant widget's build-time exception (e.g. a Null check
// operator on a null) is captured here, the dashboard re-renders as a
// friendly retry UI, AND the original handler still fires (so Sentry /
// Crashlytics / the console still see the error).
//
// Without this, a descendant build failure bubbles up to the global
// boundary's counter — at 10 errors it shows the full-screen "משהו השתבש"
// crash UI which the user is seeing today. With this boundary, the user
// sees a localized error inside the Banners tab and the rest of the
// admin shell keeps working.

class _BannersErrorBoundary extends StatefulWidget {
  const _BannersErrorBoundary({required this.child});
  final Widget child;

  @override
  State<_BannersErrorBoundary> createState() => _BannersErrorBoundaryState();
}

class _BannersErrorBoundaryState extends State<_BannersErrorBoundary> {
  String? _error;
  String? _stack;
  FlutterExceptionHandler? _previousHandler;

  // Synchronous flag — flips to true the moment we identify a banner-
  // tab build error. Subsequent matching errors (same frame OR following
  // frames) are SWALLOWED instead of forwarded. This is the critical
  // piece that stops the global `_ErrorBoundary` (main.dart:644) from
  // counting past 10 and tripping the full-screen "משהו השתבש" crash.
  // Once true, it stays true until the user taps "נסה שוב" or leaves
  // the tab.
  bool _suppressFurther = false;

  bool _isLikelyOurBuildError(FlutterErrorDetails details) {
    final libStr = (details.library ?? '').toLowerCase();
    final msg = details.exception.toString().toLowerCase();
    // Permissive match — when in doubt, claim it. False positives just
    // show our local retry UI; false negatives let the global crash
    // counter tick.
    return libStr.contains('widget') ||
        libStr.contains('rendering') ||
        msg.contains('null check') ||
        msg.contains("reading 'tostring'") ||
        msg.contains('layouterror') ||
        msg.contains('renderbox');
  }

  @override
  void initState() {
    super.initState();
    _previousHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final ours = _isLikelyOurBuildError(details);

      // ── Suppression path ───────────────────────────────────────
      // After we've captured one matching error, swallow further
      // matching errors so the global counter doesn't tick. We do
      // print to console so the developer can still see them.
      if (ours && _suppressFurther) {
        // ignore: avoid_print
        print(
            '[BannersErrorBoundary] suppressed (already captured): ${details.exception}');
        return;
      }

      // ── Forward path ───────────────────────────────────────────
      // Either it's not our error, or it's the FIRST one we'll
      // capture. Forward to the original handler so Sentry /
      // Crashlytics / console all see it. The global boundary will
      // count this one — but since we suppress everything after,
      // the counter never reaches 10.
      _previousHandler?.call(details);

      // ── Capture path ──────────────────────────────────────────
      if (mounted && _error == null && ours) {
        _suppressFurther = true;
        final exception = details.exception;
        final fullStack = details.stack?.toString() ?? '';

        // Dump the FULL stack to console so the developer can read the
        // actual source frames in DevTools (the local UI only shows
        // the first 8 to keep the retry view scannable).
        // ignore: avoid_print
        print(
            '[BannersErrorBoundary] CAPTURED build error:\n  exception: $exception\n  library: ${details.library}\n  context: ${details.context}\n  stack:\n$fullStack');

        // Defer the setState to avoid setState-during-build crashes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _error = '${exception.runtimeType}: $exception';
            final lines = fullStack.split('\n');
            _stack = lines.take(8).join('\n');
          });
        });
      }
    };
  }

  @override
  void dispose() {
    // Restore the previous handler so we don't leak into other screens.
    if (FlutterError.onError != _previousHandler) {
      FlutterError.onError = _previousHandler;
    }
    super.dispose();
  }

  void _retry() {
    setState(() {
      _error = null;
      _stack = null;
      _suppressFurther = false; // re-arm the boundary for the next attempt
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(StudioSpacing.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 40, color: StudioColors.warn),
              const SizedBox(height: StudioSpacing.s3),
              Text('שגיאה בטעינת מסך הבאנרים',
                  style: StudioText.h3(),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  _error!,
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                ),
              ),
              if (_stack != null && _stack!.isNotEmpty) ...[
                const SizedBox(height: StudioSpacing.s2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SelectableText(
                    _stack!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: StudioColors.ink4,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
              const SizedBox(height: StudioSpacing.s4),
              FilledButton(
                onPressed: _retry,
                child: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}
