// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'dart:async';

import '../services/monetization_kpi_service.dart';
import '../services/monetization_provider_service.dart';
import '../services/monetization_service.dart';
import '../utils/web_utils.dart';
import '../widgets/monetization/activity_heatmap.dart';
import '../widgets/monetization/activity_timeline.dart';
import '../widgets/monetization/ai_insight_banner.dart';
import '../widgets/monetization/category_commission_grid.dart';
import '../widgets/monetization/commission_hierarchy_visual.dart';
import '../widgets/monetization/commission_simulator.dart';
import '../widgets/monetization/design_tokens.dart';
import '../widgets/monetization/escrow_transaction_card.dart';
import '../widgets/monetization/kpi_card.dart';
import '../widgets/monetization/provider_commission_table.dart';
import '../widgets/monetization/provider_edit_dialog.dart';
import '../widgets/monetization/revenue_chart.dart';
import '../widgets/monetization/smart_alert_card.dart';

/// The Monetization tab — v15.x premium layout (9 sections).
/// Stage 2: Scaffold wired up. Stages 3-6 enrich the placeholders with
/// real AI, simulations, and aggregations.
class AdminMonetizationTab extends StatefulWidget {
  const AdminMonetizationTab({super.key});

  @override
  State<AdminMonetizationTab> createState() => _AdminMonetizationTabState();
}

class _AdminMonetizationTabState extends State<AdminMonetizationTab> {
  // ── Global settings state (fed from a single snapshot subscription) ──────
  double _feePct = 10.0;          // 0-100 scale
  double _urgencyFeePct = 5.0;    // 0-100 scale
  double _loadedFeePct = 10.0;    // baseline for "unsaved" detection
  double _loadedUrgencyPct = 5.0;
  bool   _settingsLoaded = false;

  // Smart rules — reflect the persisted state from admin settings.
  bool _waiveFirstNEnabled = false;
  bool _tieredEnabled = false;
  bool _weekendBoostEnabled = false;
  // Toggles save in-flight — disables the Switch while waiting.
  final Set<String> _ruleSaving = <String>{};

  int _controlTabIndex = 0; // 0=global, 1=categories, 2=providers, 3=A/B
  ProviderFilter _providerFilter = ProviderFilter.all;

  DateTime? _lastSettingsUpdate;

  // ── KPI snapshot (refreshed every 60s via a Timer) ────────────────────
  MonetizationKpis? _kpis;
  bool _kpiLoading = true;
  Timer? _kpiRefreshTimer;

  // ── Provider table snapshot (refreshed with the KPIs) ─────────────────
  List<ProviderTableRow> _providers = const [];
  bool _providersLoading = true;

  bool get _hasUnsavedChanges =>
      (_feePct - _loadedFeePct).abs() > 0.01 ||
      (_urgencyFeePct - _loadedUrgencyPct).abs() > 0.01;

  @override
  void initState() {
    super.initState();
    _subscribeGlobalSettings();
    _loadKpis();
    _kpiRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadKpis(),
    );
  }

  @override
  void dispose() {
    _kpiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadKpis() async {
    // Load both snapshots in parallel — they share some reads in effect
    // (custom commissions, escrow jobs) but Firebase's Firestore SDK
    // dedupes document reads via its in-memory cache.
    final kpiFuture = MonetizationKpiService.load();
    final providerFuture = MonetizationProviderService.load(
      globalPct: _loadedFeePct,
    );

    try {
      final kpi = await kpiFuture;
      if (!mounted) return;
      setState(() {
        _kpis = kpi;
        _kpiLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _kpiLoading = false);
    }

    try {
      final providers = await providerFuture;
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _providersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _providersLoading = false);
    }
  }

  void _subscribeGlobalSettings() {
    MonetizationService.streamGlobalSettings().listen((data) {
      if (!mounted) return;
      final feeFraction = (data['feePercentage'] as num?)?.toDouble() ?? 0.10;
      final urgencyFraction =
          (data['urgencyFeePercentage'] as num?)?.toDouble() ?? 0.05;

      // Smart rules
      final waiveN =
          (data['waiveFeeFirstNJobs'] as num?)?.toInt() ?? 0;
      final tieredMap = data['tieredCommission'];
      final tieredOn =
          tieredMap is Map && tieredMap['enabled'] == true;
      final boostMap = data['weekendBoost'];
      final boostOn = boostMap is Map && boostMap['enabled'] == true;

      setState(() {
        _loadedFeePct = feeFraction * 100;
        _loadedUrgencyPct = urgencyFraction * 100;
        if (!_hasUnsavedChanges) {
          _feePct = _loadedFeePct;
          _urgencyFeePct = _loadedUrgencyPct;
        }
        _waiveFirstNEnabled = waiveN > 0;
        _tieredEnabled = tieredOn;
        _weekendBoostEnabled = boostOn;
        _settingsLoaded = true;
        _lastSettingsUpdate = DateTime.now();
      });
    });
  }

  Future<void> _toggleWaiveFirstN(bool on) async {
    setState(() {
      _ruleSaving.add('waive');
      _waiveFirstNEnabled = on;
    });
    try {
      await MonetizationService.updateSmartRules(
        waiveFeeFirstNJobs: on ? 3 : 0,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _waiveFirstNEnabled = !on);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'),
              backgroundColor: MonetizationTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _ruleSaving.remove('waive'));
    }
  }

  Future<void> _toggleTiered(bool on) async {
    setState(() {
      _ruleSaving.add('tiered');
      _tieredEnabled = on;
    });
    try {
      await MonetizationService.updateSmartRules(
        tieredCommission: {
          'enabled': on,
          'tiers': [
            {'minGMV': 5000, 'discount': 2.0},
            {'minGMV': 10000, 'discount': 4.0},
          ],
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _tieredEnabled = !on);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'),
              backgroundColor: MonetizationTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _ruleSaving.remove('tiered'));
    }
  }

  Future<void> _toggleWeekendBoost(bool on) async {
    setState(() {
      _ruleSaving.add('boost');
      _weekendBoostEnabled = on;
    });
    try {
      await MonetizationService.updateSmartRules(
        weekendBoost: {
          'enabled': on,
          'daysOfWeek': [5, 6], // 5=Friday, 6=Saturday (0=Sun..6=Sat)
          'extraPercentage': 2.0,
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _weekendBoostEnabled = !on);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'),
              backgroundColor: MonetizationTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _ruleSaving.remove('boost'));
    }
  }

  Future<void> _saveGlobalSettings() async {
    try {
      await MonetizationService.updateGlobalCommission(
        feePct: _feePct,
        urgencyPct: _urgencyFeePct,
        oldFeePct: _loadedFeePct,
        oldUrgencyPct: _loadedUrgencyPct,
      );
      if (!mounted) return;
      setState(() {
        _loadedFeePct = _feePct;
        _loadedUrgencyPct = _urgencyFeePct;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ההגדרות נשמרו ✓'),
          backgroundColor: MonetizationTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה: $e'),
          backgroundColor: MonetizationTokens.danger,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  // ── Responsive breakpoints ────────────────────────────────────────────
  // Spec HTML is designed for ~1440px. Breakpoints:
  //   < 720   : phone      — everything single column, 2-col KPI grid
  //   720-1024: tablet     — side-by-side still possible, KPIs 2 cols
  //   > 1024  : desktop    — original 4-col KPI + 2/3+1/3 + 3/5+2/5 layout
  bool _isPhone(double w) => w < 720;
  bool _isTablet(double w) => w < 1024;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonetizationTokens.scaffold,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isPhone = _isPhone(constraints.maxWidth);
          final isTablet = _isTablet(constraints.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.all(isPhone ? 10 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(isPhone: isPhone),
                SizedBox(height: isPhone ? 14 : 20),
                _buildInsightBanner(),
                SizedBox(height: isPhone ? 14 : 20),
                _buildKpiGrid(isPhone: isPhone, isTablet: isTablet),
                SizedBox(height: isPhone ? 14 : 20),
                _buildAlertsStrip(isPhone: isPhone),
                SizedBox(height: isPhone ? 14 : 20),
                _buildCommissionControlSection(isTablet: isTablet),
                SizedBox(height: isPhone ? 14 : 20),
                _buildChartsSection(isTablet: isTablet),
                SizedBox(height: isPhone ? 14 : 20),
                _buildProviderTableSection(),
                SizedBox(height: isPhone ? 14 : 20),
                _buildBottomRow(isTablet: isTablet),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 1 — Top Bar
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTopBar({required bool isPhone}) {
    // Icon + title block is shared; on phone, the search/save stack below
    // the title. On wider screens everything stays on one row.
    final titleBlock = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: MonetizationTokens.textPrimary,
            borderRadius: BorderRadius.circular(MonetizationTokens.radiusLg),
          ),
          child: const Icon(Icons.attach_money_rounded,
              color: MonetizationTokens.warningVivid, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text('מוניטיזציה',
                        style: MonetizationTokens.h1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  MonetizationPill(
                    label: 'LIVE',
                    background: MonetizationTokens.successLight,
                    foreground: MonetizationTokens.successText,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _liveStatusLabel(),
                style: MonetizationTokens.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    final searchField = TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: 'שאל כל שאלה על הנתונים… (⌘K)',
        hintStyle: MonetizationTokens.caption,
        prefixIcon: const Icon(Icons.search, size: 16),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(MonetizationTokens.radiusMd),
          borderSide: const BorderSide(
              color: MonetizationTokens.borderSoft, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(MonetizationTokens.radiusMd),
          borderSide: const BorderSide(
              color: MonetizationTokens.borderSoft, width: 0.5),
        ),
      ),
    );

    final saveButton = ElevatedButton(
      onPressed: _hasUnsavedChanges ? _saveGlobalSettings : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: MonetizationTokens.textPrimary,
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            MonetizationTokens.textPrimary.withValues(alpha: 0.3),
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(MonetizationTokens.radiusMd)),
        textStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: const Text('שמור שינויים'),
    );

    if (isPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              saveButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        titleBlock,
        SizedBox(width: 320, child: searchField),
        const SizedBox(width: 8),
        saveButton,
      ],
    );
  }

  String _liveStatusLabel() {
    if (!_settingsLoaded) return 'טוען הגדרות…';
    final ts = _lastSettingsUpdate;
    if (ts == null) return 'מוכן';
    final diff = DateTime.now().difference(ts);
    final rel = diff.inSeconds < 5
        ? 'לפני שניות בודדות'
        : diff.inMinutes < 1
            ? 'לפני ${diff.inSeconds} שניות'
            : 'לפני ${diff.inMinutes} דק׳';
    return 'עודכן $rel · ${DateFormat('MMMM yyyy', 'he').format(DateTime.now())}';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 2 — AI Insight Banner
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildInsightBanner() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: MonetizationService.streamLatestInsight(),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData || snap.data == null) {
          return const AiInsightBanner();
        }
        final data = snap.data!;
        final actionType = (data['actionType'] ?? 'none').toString();
        final actionable = actionType != 'none' &&
            data['recommendation'] != null &&
            data['applied'] != true;

        final impact = (data['expectedImpact'] ?? '').toString();
        final recommendation =
            (data['recommendation'] ?? '').toString();
        final body = impact.isEmpty
            ? recommendation
            : '$recommendation · צפי השפעה: $impact';

        return AiInsightBanner(
          title: (data['title'] ?? 'תובנת AI CEO').toString(),
          body: body.isEmpty
              ? 'אין תובנה חדשה כרגע. ה-AI מנתח את הנתונים בכל 6 שעות.'
              : body,
          model: (data['model'] ?? 'Gemini 2.5').toString(),
          actionEnabled: actionable,
          onApply: actionable ? () => _applyInsight(data) : null,
          onDismiss: () async {
            await MonetizationService.dismissInsight();
          },
        );
      },
    );
  }

  /// Dispatches a Gemini-generated recommendation to the right
  /// MonetizationService write. Always shows a confirmation dialog first
  /// so the admin can reject or tweak.
  Future<void> _applyInsight(Map<String, dynamic> insight) async {
    final actionType = (insight['actionType'] ?? '').toString();
    final params = (insight['actionParams'] is Map)
        ? Map<String, dynamic>.from(insight['actionParams'] as Map)
        : <String, dynamic>{};
    final recommendation = (insight['recommendation'] ?? '').toString();
    final impact = (insight['expectedImpact'] ?? '').toString();

    // Build a human-readable preview for the confirm dialog.
    String preview;
    switch (actionType) {
      case 'adjust_category_commission':
        final name = (params['categoryName'] ?? '').toString();
        final pct = (params['newPct'] as num?)?.toDouble();
        if (name.isEmpty || pct == null) {
          _snack('פרמטרים חסרים ב-actionParams', MonetizationTokens.danger);
          return;
        }
        preview = 'עמלת הקטגוריה "$name" → ${pct.toStringAsFixed(1)}%';
        break;
      case 'reduce_provider_commission':
        final uid = (params['userId'] ?? '').toString();
        final pct = (params['newPct'] as num?)?.toDouble();
        if (uid.isEmpty || pct == null) {
          _snack('פרמטרים חסרים ב-actionParams', MonetizationTokens.danger);
          return;
        }
        preview =
            'עמלה פרטנית לספק $uid → ${pct.toStringAsFixed(1)}%';
        break;
      case 'promote_provider':
        final uid = (params['userId'] ?? '').toString();
        if (uid.isEmpty) {
          _snack('חסר userId ב-actionParams', MonetizationTokens.danger);
          return;
        }
        preview = 'ספק $uid יועלה לסטטוס Promoted';
        break;
      default:
        _snack('סוג פעולה לא מוכר: $actionType',
            MonetizationTokens.warning);
        return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MonetizationTokens.radiusXl)),
        title: const Text('הפעלת המלצת AI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(recommendation, style: MonetizationTokens.body),
            if (impact.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('השפעה צפויה: $impact',
                  style: MonetizationTokens.caption),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MonetizationTokens.primaryLight,
                borderRadius:
                    BorderRadius.circular(MonetizationTokens.radiusSm),
              ),
              child: Text('הפעולה שתתבצע: $preview',
                  style: const TextStyle(
                      fontSize: 12,
                      color: MonetizationTokens.primaryDark)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: MonetizationTokens.primaryDark,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('בצע'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      switch (actionType) {
        case 'adjust_category_commission':
          final name = (params['categoryName'] ?? '').toString();
          final pct = (params['newPct'] as num).toDouble();
          await MonetizationService.setCategoryCommission(
            categoryId: name,
            categoryName: name,
            percentage: pct,
            reason: 'AI insight',
          );
          break;
        case 'reduce_provider_commission':
          final uid = (params['userId'] ?? '').toString();
          final pct = (params['newPct'] as num).toDouble();
          final reason =
              (params['reason'] ?? 'AI insight').toString();
          final userDoc =
              await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final userName =
              (userDoc.data()?['name'] ?? uid).toString();
          await MonetizationService.setUserCommission(
            userId: uid,
            userName: userName,
            percentage: pct,
            reason: reason,
            notes: 'הופעל ע"י המלצת Gemini',
          );
          break;
        case 'promote_provider':
          final uid = (params['userId'] ?? '').toString();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({'isPromoted': true});
          break;
      }

      // Mark the insight as applied so it doesn't re-prompt until Gemini
      // generates a new one (the CF clears `applied` on next run).
      await FirebaseFirestore.instance
          .collection('ai_insights')
          .doc('monetization')
          .set({
        'applied': true,
        'appliedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        'appliedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _snack('התובנה הופעלה בהצלחה', MonetizationTokens.success);
      unawaited(_loadKpis());
    } catch (e) {
      if (!mounted) return;
      _snack('שגיאה בהפעלה: $e', MonetizationTokens.danger);
    }
  }

  void _snack(String message, Color background) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: background),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 3 — KPI Grid
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildKpiGrid({required bool isPhone, required bool isTablet}) {
    final k = _kpis ?? MonetizationKpis.empty();
    final loading = _kpiLoading && _kpis == null;

    // Formatters + helper labels --------------------------------------
    String nis(double v) => '₪${v.toStringAsFixed(0)}';
    String deltaLabel(double pct) =>
        pct == 0 ? '—' : '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}%';

    // Escrow wait pill label: "ממתין Xש׳"
    String waitPill() {
      final h = k.avgEscrowWait.inHours;
      if (k.escrowCount == 0) return '—';
      return h < 1 ? '<שעה' : '$hש׳';
    }

    // Fee-target footnote: gap to target in ₪/month (monthGmv * |target-current|/100)
    String feeGapFootnote() {
      if (k.monthEarnings == 0 || _loadedFeePct == 0) return '—';
      final gmv = k.weightedFeePct > 0
          ? k.monthEarnings / (k.weightedFeePct / 100)
          : 0.0;
      final gap =
          (gmv * (_loadedFeePct - k.weightedFeePct).abs() / 100);
      return 'פער ליעד: ${nis(gap)}/חודש';
    }

    // Responsive: 4 cols on desktop, 2 cols on tablet, 2 cols on phone
    // (phone row shrinks to fit but stays 2-across so the hero numbers
    // are always comparable side-by-side).
    final cols = isPhone ? 2 : (isTablet ? 2 : 4);
    final ratio = isPhone ? 1.4 : (isTablet ? 1.8 : 1.7);
    return GridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: ratio,
      children: [
        // ── KPI 1: Month earnings ─────────────────────────────────────
        KpiCard(
          label: 'עמלות החודש',
          value: loading ? '…' : nis(k.monthEarnings),
          suffix: loading ? null : '/ ${nis(k.prevMonthEarnings)}',
          pill: loading ? null : deltaLabel(k.monthDeltaPct),
          pillBackground: k.monthDeltaPct >= 0
              ? MonetizationTokens.successLight
              : MonetizationTokens.dangerLight,
          pillForeground: k.monthDeltaPct >= 0
              ? MonetizationTokens.successText
              : MonetizationTokens.dangerText,
          visual: k.dailyEarningsSparkline.isEmpty
              ? null
              : Sparkline(
                  values: k.dailyEarningsSparkline,
                  color: k.monthDeltaPct >= 0
                      ? MonetizationTokens.success
                      : MonetizationTokens.danger,
                ),
          footnote: loading
              ? 'טוען…'
              : 'צפי סוף חודש: ${nis(k.projectedEndOfMonth)}',
        ),
        // ── KPI 2: Escrow pending ─────────────────────────────────────
        KpiCard(
          label: 'בנאמנות כרגע',
          value: loading ? '…' : nis(k.escrowTotal),
          suffix: loading
              ? null
              : (k.escrowCount == 0 ? 'אין עסקאות' : 'ממתין ${waitPill()}'),
          pill: loading
              ? null
              : '${k.escrowCount} ${k.escrowCount == 1 ? 'פעילה' : 'פעילות'}',
          pillBackground: MonetizationTokens.warningLight,
          pillForeground: MonetizationTokens.warningText,
          visual: EscrowWaitBars(waits: k.escrowWaitTimes),
          footnote: loading
              ? null
              : k.avgEscrowWait == Duration.zero
                  ? 'אין עסקאות פעילות'
                  : 'ממוצע המתנה: ${k.avgEscrowWait.inHours} שעות',
        ),
        // ── KPI 3: Weighted fee % ─────────────────────────────────────
        KpiCard(
          label: 'עמלה משוקללת',
          value: loading ? '…' : k.weightedFeePct.toStringAsFixed(1),
          suffix: '%',
          pill: 'יעד ${_loadedFeePct.toStringAsFixed(0)}%',
          pillBackground: MonetizationTokens.primaryLight,
          pillForeground: MonetizationTokens.primaryDark,
          deltaText: loading
              ? null
              : '${(k.weightedFeePct - _loadedFeePct) >= 0 ? '+' : ''}${(k.weightedFeePct - _loadedFeePct).toStringAsFixed(1)}pt',
          deltaColor: (k.weightedFeePct - _loadedFeePct) >= 0
              ? MonetizationTokens.success
              : MonetizationTokens.dangerDown,
          visual: FeeTargetBar(
            current: k.weightedFeePct,
            target: _loadedFeePct,
            max: 20,
          ),
          footnote: loading ? null : feeGapFootnote(),
        ),
        // ── KPI 4: Custom commissions ─────────────────────────────────
        KpiCard(
          label: 'עמלות מותאמות',
          value: loading
              ? '…'
              : k.customCommissionCount.toString(),
          suffix: 'ספקים',
          pill:
              '${(k.customCommissionRevenueShare * 100).toStringAsFixed(0)}% מההכנסה',
          pillBackground: MonetizationTokens.churnLight,
          pillForeground: MonetizationTokens.churnText,
          visual: CustomProviderBars(values: k.topCustomProviderRevenues),
          footnote: loading
              ? null
              : k.customCommissionCount == 0
                  ? 'עדיין אין ספקים עם override'
                  : 'Top ${k.topCustomProviderRevenues.length} מניבים יחד',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 4 — Smart Alerts Strip
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAlertsStrip({required bool isPhone}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: MonetizationService.streamOpenAlerts(limit: 3),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        // Render up to 3 alerts. If Firestore has none (stage 2 — no CF yet),
        // show placeholder cards so the admin sees the layout.
        final placeholders = [
          SmartAlertCard(
            type: MonetizationAlertType.anomaly,
            title: 'Anomaly זוהה',
            message: 'CF detectMonetizationAnomalies לא פעיל — ממתין לשלב 3',
            actionLabel: 'בדוק',
            onAction: () {},
          ),
          SmartAlertCard(
            type: MonetizationAlertType.churn,
            title: 'Churn Risk',
            message: 'אלוגריתם churn ישודר יחד עם ה-CF בשלב 3',
            actionLabel: 'צפה',
            onAction: () {},
          ),
          SmartAlertCard(
            type: MonetizationAlertType.growth,
            title: 'הזדמנות צמיחה',
            message: 'זוהה לאחר שה-CF יופעל (Phase 2)',
            actionLabel: 'פעל',
            onAction: () {},
          ),
        ];
        final children = docs.isEmpty
            ? placeholders
            : docs.take(3).map((d) {
                final data = d.data();
                final type = _alertTypeFromString(
                    (data['type'] ?? 'anomaly').toString());
                return SmartAlertCard(
                  type: type,
                  title: _alertTitleFor(type),
                  message: (data['message'] ?? '').toString(),
                  actionLabel: 'בדוק',
                  onAction: () => MonetizationService.resolveAlert(d.id),
                );
              }).toList();

        // Phone: stack the 3 alerts vertically. Wider: side-by-side row.
        if (isPhone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }

  MonetizationAlertType _alertTypeFromString(String t) {
    if (t.contains('churn')) return MonetizationAlertType.churn;
    if (t.contains('growth')) return MonetizationAlertType.growth;
    return MonetizationAlertType.anomaly;
  }

  String _alertTitleFor(MonetizationAlertType t) => switch (t) {
        MonetizationAlertType.anomaly => 'Anomaly זוהה',
        MonetizationAlertType.churn   => 'Churn Risk',
        MonetizationAlertType.growth  => 'הזדמנות צמיחה',
      };

  // ═══════════════════════════════════════════════════════════════════════
  // Section 5 — Commission Control Center + Live Simulator
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCommissionControlSection({required bool isTablet}) {
    // Tablet + phone: simulator drops below the control center so the
    // sliders have room. Desktop keeps the 2/3 + 1/3 split from the mockup.
    if (isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControlCenter(),
          const SizedBox(height: 12),
          _buildSimulator(),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _buildControlCenter()),
          const SizedBox(width: 12),
          Expanded(flex: 1, child: _buildSimulator()),
        ],
      ),
    );
  }

  Widget _buildControlCenter() {
    return MonetizationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מרכז שליטה בעמלות', style: MonetizationTokens.h2),
          const SizedBox(height: 4),
          Text(
            'היררכיה: גלובלי → קטגוריה → ספק (הספציפי דורס)',
            style: MonetizationTokens.caption,
          ),
          const SizedBox(height: 16),

          // Hierarchy breadcrumb
          StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: MonetizationService.streamCategoryCommissions(),
            builder: (context, categorySnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: MonetizationService.streamCustomCommissionUsers(),
                builder: (context, userSnap) {
                  return CommissionHierarchyVisual(
                    globalPct: _loadedFeePct,
                    customCategoryCount: categorySnap.data?.length ?? 0,
                    customProviderCount: userSnap.data?.docs.length ?? 0,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 18),

          // Inner tabs
          _buildInnerTabs(),
          const SizedBox(height: 16),

          // Active tab content
          if (_controlTabIndex == 0) _buildGlobalSliders(),
          if (_controlTabIndex == 1) _buildCategoriesTab(),
          if (_controlTabIndex == 2) _buildProvidersTabShortcut(),
          if (_controlTabIndex == 3) _buildAbTestsPlaceholder(),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: MonetizationTokens.borderSoft, width: 0.5),
              ),
            ),
            child: _buildSmartRules(),
          ),
        ],
      ),
    );
  }

  Widget _buildInnerTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: MonetizationTokens.borderSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _innerTab(0, 'גלובלי'),
          _innerTab(1, 'קטגוריות'),
          _innerTab(2, 'ספקים'),
          _innerTab(3, 'A/B בדיקות'),
        ],
      ),
    );
  }

  Widget _innerTab(int index, String label) {
    final selected = _controlTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _controlTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? MonetizationTokens.textPrimary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected
                ? MonetizationTokens.textPrimary
                : MonetizationTokens.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalSliders() {
    if (!_settingsLoaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _sliderBlock(
            title: 'עמלה גלובלית',
            value: _feePct,
            max: 30,
            color: MonetizationTokens.primary,
            onChanged: (v) => setState(() => _feePct = v),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _sliderBlock(
            title: 'תוספת דחיפות',
            value: _urgencyFeePct,
            max: 20,
            prefix: '+',
            color: MonetizationTokens.warning,
            onChanged: (v) => setState(() => _urgencyFeePct = v),
          ),
        ),
      ],
    );
  }

  Widget _sliderBlock({
    required String title,
    required double value,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
    String? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: MonetizationTokens.h3),
            Row(
              children: [
                if (prefix != null)
                  Text(prefix, style: MonetizationTokens.caption),
                SizedBox(
                  width: 48,
                  child: TextFormField(
                    key: ValueKey('slider_${title}_${value.toStringAsFixed(1)}'),
                    initialValue: value.toStringAsFixed(0),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onFieldSubmitted: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null && parsed >= 0 && parsed <= max) {
                        onChanged(parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                const Text('%', style: MonetizationTokens.caption),
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: MonetizationTokens.surfaceAlt,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            divisions: max.toInt(),
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0%', style: MonetizationTokens.micro),
            Text('${(max / 2).toStringAsFixed(0)}%',
                style: MonetizationTokens.micro),
            Text('${max.toStringAsFixed(0)}%',
                style: MonetizationTokens.micro),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoriesTab() {
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: MonetizationService.streamCategoryCommissions(),
      builder: (context, snap) {
        final overrides = snap.data ?? const <String, Map<String, dynamic>>{};
        return CategoryCommissionGrid(
          globalPct: _loadedFeePct,
          overrides: overrides,
        );
      },
    );
  }

  Widget _buildProvidersTabShortcut() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MonetizationTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: const Text(
        'הטבלה המלאה של הספקים מופיעה בסקציה 7 למטה.',
        style: TextStyle(
            fontSize: 12, color: MonetizationTokens.textSecondary),
      ),
    );
  }

  Widget _buildAbTestsPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MonetizationTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined,
                  size: 16, color: MonetizationTokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                'A/B בדיקות · Phase 2',
                style: MonetizationTokens.h3,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'טסטים על אחוזי עמלה יופעלו לאחר שנאסוף נתוני בסיס מייצגים.',
            style: TextStyle(
                fontSize: 12, color: MonetizationTokens.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartRules() {
    if (!_settingsLoaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('כללים חכמים',
            style: MonetizationTokens.caption.copyWith(
              fontWeight: FontWeight.w500,
            )),
        const SizedBox(height: 10),
        _smartRuleRow(
          title: 'פטור מעמלה ל-3 העסקאות הראשונות',
          subtitle: 'מעודד onboarding של ספקים חדשים',
          value: _waiveFirstNEnabled,
          saving: _ruleSaving.contains('waive'),
          onChanged: _toggleWaiveFirstN,
        ),
        const SizedBox(height: 8),
        _smartRuleRow(
          title: 'עמלה מדורגת לפי volume',
          subtitle: 'מעל ₪5,000/חודש → -2% · מעל ₪10,000 → -4%',
          value: _tieredEnabled,
          saving: _ruleSaving.contains('tiered'),
          onChanged: _toggleTiered,
        ),
        const SizedBox(height: 8),
        _smartRuleRow(
          title: 'בוסט סוף שבוע',
          subtitle: '+2% בשישי-שבת (ביקוש גבוה)',
          value: _weekendBoostEnabled,
          saving: _ruleSaving.contains('boost'),
          onChanged: _toggleWeekendBoost,
        ),
      ],
    );
  }

  Widget _smartRuleRow({
    required String title,
    required String subtitle,
    required bool value,
    required bool saving,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MonetizationTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                Text(subtitle, style: MonetizationTokens.captionTertiary),
              ],
            ),
          ),
          if (saving)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          else
            Switch(
              value: value,
              activeColor: MonetizationTokens.success,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }

  Widget _buildSimulator() {
    return CommissionSimulator(
      newFeePct: _feePct,
      result: _computeSimulation(),
    );
  }

  /// Client-side heuristic. Returns zeroed-out placeholder when we don't
  /// have real KPI data yet. Math (all in NIS / percentage-points):
  ///
  ///   feeDelta       = newFee − loadedFee     (+ = raising fees)
  ///   baseMonthlyGmv = monthEarnings ÷ (weightedFeePct/100)
  ///   projectedGmv   = baseMonthlyGmv × acceptanceRate
  ///   acceptanceRate = 1 − max(0, feeDelta × 0.03)       // 1pt ≈ 3% drop
  ///   newRevenue     = projectedGmv × (newFee/100)
  ///   churnProviders = totalProviders × max(0, feeDelta × 0.02)
  ///
  /// The heuristic is intentionally simple — a full simulation via
  /// `simulateCommissionChange` CF is Phase 2.
  SimulationResult _computeSimulation() {
    final k = _kpis;
    final totalProviders = _providers.length;

    if (k == null || k.monthEarnings == 0 || k.weightedFeePct == 0) {
      return const SimulationResult(
        projectedRevenue: 0,
        revenueDelta: 0,
        providersAtChurnRisk: 0,
        totalProviders: 0,
        acceptanceRate: 1.0,
        projectedGmv: 0,
        aiOpinion:
            'ממתין לנתוני בסיס — הסימולטור יחושב ברגע שייטענו הנתונים של החודש.',
      );
    }

    // Normalise to a full month (projection) so numbers are comparable to
    // the "Revenue this month" KPI.
    final now = DateTime.now();
    final daysInMonth =
        DateTime(now.year, now.month + 1, 0).day.toDouble();
    final daysPassed = now.day.toDouble().clamp(1, daysInMonth);

    // Current state — gross up partial-month numbers to a full month.
    final currentMonthlyRevenue =
        k.monthEarnings / daysPassed * daysInMonth;
    final baseMonthlyGmv = k.monthEarnings /
        (k.weightedFeePct / 100) /
        daysPassed *
        daysInMonth;

    // Proposed state.
    final feeDelta = _feePct - _loadedFeePct;
    final acceptance =
        (1 - (feeDelta > 0 ? feeDelta * 0.03 : 0)).clamp(0.3, 1.0);
    final projectedGmv = baseMonthlyGmv * acceptance;
    final projectedRevenue = projectedGmv * (_feePct / 100);
    final revenueDelta = projectedRevenue - currentMonthlyRevenue;

    final churnFrac = (feeDelta > 0 ? feeDelta * 0.02 : 0).clamp(0.0, 0.30);
    final churnProviders =
        (totalProviders * churnFrac).round();

    return SimulationResult(
      projectedRevenue: projectedRevenue,
      revenueDelta: revenueDelta,
      providersAtChurnRisk: churnProviders,
      totalProviders: totalProviders,
      acceptanceRate: acceptance.toDouble(),
      projectedGmv: projectedGmv,
      aiOpinion: _simulatorOpinion(
        feeDelta: feeDelta,
        revenueDelta: revenueDelta,
        churnProviders: churnProviders,
      ),
    );
  }

  String _simulatorOpinion({
    required double feeDelta,
    required double revenueDelta,
    required int churnProviders,
  }) {
    if (feeDelta.abs() < 0.5) {
      return 'שינוי קטן מדי כדי להשפיע על ההתנהגות. בטוח.';
    }
    if (feeDelta < 0) {
      return 'הורדת עמלה — צפויה עלייה בנפח עסקאות אבל פחות הכנסה בטווח הקצר. '
          'מתאים כבונוס לספקי Top או כקמפיין זמני.';
    }
    // feeDelta > 0
    if (churnProviders >= 10) {
      return 'סיכון גבוה — צפי churn של $churnProviders ספקים. מומלץ לבדוק על קטגוריה אחת לפני rollout.';
    }
    if (revenueDelta < 0) {
      return 'העלאה גבוהה מדי — ירידת נפח תבטל את התוספת. מומלץ לצמצם ל-1pt או להגביל לקטגוריה ספציפית.';
    }
    return 'סיכון נמוך — ההפרש לתחרות קטן (±1%). מומלץ לבדוק על קטגוריה אחת לפני rollout.';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 6 — Revenue Chart + Heatmap
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildChartsSection({required bool isTablet}) {
    final k = _kpis;
    final hasData = k != null &&
        (k.currentMonthDaily.isNotEmpty ||
            k.prevMonthDaily.isNotEmpty);

    final chartCard = MonetizationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('הכנסות ומגמות', style: MonetizationTokens.h2),
          const SizedBox(height: 4),
          Text('חודש נוכחי מול חודש קודם + תחזית',
              style: MonetizationTokens.caption),
          const SizedBox(height: 16),
          if (!hasData)
            _emptyCardBody('טוען נתוני עמלות…')
          else
            RevenueChart(
              series: _buildRevenueSeries(k),
              peakLabel: k.peakDayOfMonth > 0
                  ? 'שיא עד כה: יום ${k.peakDayOfMonth} '
                      '(₪${k.peakDayValue.toStringAsFixed(0)})'
                  : null,
            ),
          if (hasData) ...[
            const SizedBox(height: 16),
            _chartStats(k),
          ],
        ],
      ),
    );

    final heatmapCard = MonetizationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מפת חום — יום × שעה',
              style: MonetizationTokens.h2),
          const SizedBox(height: 4),
          Text('אינטנסיביות עסקאות (30 ימים אחרונים)',
              style: MonetizationTokens.caption),
          const SizedBox(height: 16),
          if (k == null || k.heatmap.isEmpty)
            _emptyCardBody('טוען נתוני פעילות…')
          else
            ActivityHeatmap(
              values: k.heatmap,
              insight: k.heatmapInsight ??
                  'אין מספיק נתונים לתובנה (דורש עסקאות ב-30 ימים אחרונים).',
            ),
        ],
      ),
    );

    // Tablet/phone stack the heatmap below the chart.
    if (isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chartCard,
          const SizedBox(height: 12),
          heatmapCard,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: chartCard),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: heatmapCard),
        ],
      ),
    );
  }

  Widget _emptyCardBody(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: MonetizationTokens.textTertiary)),
        ),
      );

  List<RevenueSeries> _buildRevenueSeries(MonetizationKpis k) {
    final now = DateTime.now();
    final currentToToday =
        k.currentMonthDaily.take(now.day).toList(growable: false);

    // Only show the projection tail (the part past today). Prepend zeros
    // for the days already charted so the series aligns on the x-axis.
    final projTail = <double>[];
    for (int i = 0; i < k.projectionDaily.length; i++) {
      projTail.add(i >= now.day - 1 ? k.projectionDaily[i] : 0);
    }

    return [
      RevenueSeries(
        label: 'חודש נוכחי',
        points: currentToToday,
        color: MonetizationTokens.primary,
        fillAlpha: 0.1,
      ),
      if (k.prevMonthDaily.isNotEmpty)
        RevenueSeries(
          label: 'חודש קודם',
          points: k.prevMonthDaily,
          color: MonetizationTokens.textTertiary,
          dashed: true,
        ),
      if (k.projectionDaily.length > now.day)
        RevenueSeries(
          label: 'תחזית',
          points: projTail,
          color: MonetizationTokens.success,
          dashed: true,
          isProjection: true,
        ),
    ];
  }

  Widget _chartStats(MonetizationKpis k) {
    // Bottom row of 4 quick stats under the chart (per spec).
    final now = DateTime.now();
    final daysPassed = now.day.clamp(1, k.currentMonthDaily.length);
    final dailyAvg = daysPassed > 0 ? k.monthEarnings / daysPassed : 0.0;
    final mom = k.prevMonthEarnings > 0
        ? (k.monthEarnings - k.prevMonthEarnings) /
            k.prevMonthEarnings *
            100
        : 0.0;

    String nis(double v) => '₪${v.toStringAsFixed(0)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MonetizationTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: Row(
        children: [
          _statCol('ממוצע יומי', nis(dailyAvg)),
          _statCol('שיא', nis(k.peakDayValue)),
          _statCol('צפי סוף חודש', nis(k.projectedEndOfMonth)),
          _statCol('MoM',
              '${mom >= 0 ? '+' : ''}${mom.toStringAsFixed(1)}%',
              valueColor: mom >= 0
                  ? MonetizationTokens.success
                  : MonetizationTokens.danger),
        ],
      ),
    );
  }

  Widget _statCol(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: MonetizationTokens.captionTertiary),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? MonetizationTokens.textPrimary,
              )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 7 — Provider Commission Table
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildProviderTableSection() {
    final filtered = _applyProviderFilter(_providers, _providerFilter);
    return MonetizationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('ספקים — שליטה ובריאות',
                    style: MonetizationTokens.h2),
              ),
              if (_providersLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ניהול עמלה פרטנית, VIP, ו-churn risk. לחץ "ערוך" לכל שורה.',
            style: MonetizationTokens.caption,
          ),
          const SizedBox(height: 14),
          ProviderCommissionTable(
            rows: filtered,
            filter: _providerFilter,
            onFilterChanged: (f) =>
                setState(() => _providerFilter = f),
            onEditProvider: (row) => _openProviderEdit(row),
          ),
        ],
      ),
    );
  }

  /// Applies the active filter chip to the loaded provider list.
  List<ProviderTableRow> _applyProviderFilter(
    List<ProviderTableRow> all,
    ProviderFilter filter,
  ) {
    switch (filter) {
      case ProviderFilter.all:
        return all;
      case ProviderFilter.customOnly:
        return all.where((r) => r.commissionSource == 'custom').toList();
      case ProviderFilter.vipOnly:
        return all.where((r) => r.isVip).toList();
      case ProviderFilter.topEarners:
        return all.where((r) => r.isTopPerformer).toList();
      case ProviderFilter.churnRisk:
        return all.where((r) => r.isChurnRisk).toList();
      case ProviderFilter.inactive:
        // Inactive == 0 completed jobs in the last 30 days.
        return all.where((r) => r.gmv30d == 0).toList();
    }
  }

  Future<void> _openProviderEdit(ProviderTableRow row) async {
    // Look up the category override so the "קטגוריה" preset chip in the
    // dialog reflects reality.
    final catPct =
        await MonetizationService.getCategoryPercentage(row.category);

    if (!mounted) return;
    final changed = await showProviderEditDialog(
      context,
      userId: row.uid,
      userName: row.name,
      currentPct:
          row.commissionSource == 'custom' ? row.effectivePct : null,
      globalPct: _loadedFeePct,
      categoryPct: catPct,
    );

    // If the admin saved a change, refresh the provider snapshot so the
    // row updates immediately without waiting for the 60-second timer.
    if (changed == true) {
      unawaited(_loadKpis());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Section 8 — Escrow + Activity Timeline
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBottomRow({required bool isTablet}) {
    if (isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEscrowCard(),
          const SizedBox(height: 12),
          _buildActivityCard(),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildEscrowCard()),
          const SizedBox(width: 12),
          Expanded(child: _buildActivityCard()),
        ],
      ),
    );
  }

  Widget _buildEscrowCard() {
    return MonetizationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('נאמנות (Escrow)', style: MonetizationTokens.h2),
              ),
              TextButton.icon(
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('CSV'),
                onPressed: _exportTransactionsCsv,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('עסקאות ממתינות עם התקדמות, שחרור והחזר',
              style: MonetizationTokens.caption),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: MonetizationService.streamEscrowJobs(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('אין עסקאות בנאמנות כרגע',
                        style: MonetizationTokens.caption),
                  ),
                );
              }
              return Column(
                children: docs.take(6).map((d) {
                  final data = d.data();
                  return EscrowTransactionCard(
                    jobId: d.id,
                    data: data,
                    onRelease: () => _confirmReleaseEscrow(
                        jobId: d.id, data: data),
                    onRefund: () => _confirmRefund(
                        jobId: d.id, data: data),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    return MonetizationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('יומן פעילות', style: MonetizationTokens.h2),
          const SizedBox(height: 4),
          Text('השינויים האחרונים בטאב המוניטיזציה',
              style: MonetizationTokens.caption),
          const SizedBox(height: 14),
          ActivityTimeline(
            stream: MonetizationService.streamActivityFeed(limit: 6),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Escrow actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmReleaseEscrow({
    required String jobId,
    required Map<String, dynamic> data,
  }) async {
    final amount = ((data['totalAmount'] ?? 0) as num).toDouble();
    final commission = ((data['commission'] ?? 0) as num).toDouble();
    final netToProvider =
        ((data['netAmountForExpert'] ?? (amount - commission)) as num)
            .toDouble();
    final expertName = (data['expertName'] ?? '—').toString();

    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MonetizationTokens.radiusXl)),
        title: const Text('שחרור תשלום לספק'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'שחרור ידני של $jobId — ל-$expertName',
              style: MonetizationTokens.body,
            ),
            const SizedBox(height: 10),
            _ReleaseRow(
                label: 'סכום עסקה',
                value: '₪${amount.toStringAsFixed(0)}'),
            _ReleaseRow(
                label: 'עמלת פלטפורמה',
                value: '₪${commission.toStringAsFixed(0)}'),
            _ReleaseRow(
                label: 'יתרה לספק',
                value: '₪${netToProvider.toStringAsFixed(0)}',
                emphasize: true),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'הערת אדמין (אופציונלי)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MonetizationTokens.warningLight,
                borderRadius:
                    BorderRadius.circular(MonetizationTokens.radiusSm),
              ),
              child: const Text(
                'פעולה זו סופית. הספק יקבל את הכסף מיד ולא ניתן לחזור מכך ללא dispute.',
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 11, color: MonetizationTokens.warningText),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: MonetizationTokens.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('שחרר'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      noteCtrl.dispose();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('משחרר escrow…'),
      duration: Duration(seconds: 2),
    ));

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminReleaseEscrow',
        options: HttpsCallableOptions(
            timeout: const Duration(seconds: 30)),
      );
      await callable.call({
        'jobId': jobId,
        'note': noteCtrl.text.trim(),
      });
      noteCtrl.dispose();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
            'שוחררו ₪${netToProvider.toStringAsFixed(0)} ל-$expertName'),
        backgroundColor: MonetizationTokens.success,
      ));
      // Refresh the snapshot so the escrow row disappears + KPIs update.
      unawaited(_loadKpis());
    } on FirebaseFunctionsException catch (e) {
      noteCtrl.dispose();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('שגיאה: ${e.message ?? e.code}'),
        backgroundColor: MonetizationTokens.danger,
      ));
    } catch (e) {
      noteCtrl.dispose();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('שגיאה: $e'),
        backgroundColor: MonetizationTokens.danger,
      ));
    }
  }

  Future<void> _confirmRefund({
    required String jobId,
    required Map<String, dynamic> data,
  }) async {
    // Reuses the same admin refund pattern that existed in the legacy tab.
    final amount = ((data['totalAmount'] ?? 0) as num).toDouble();
    final customerName = (data['customerName'] ?? '—').toString();
    final customerId = (data['customerId'] ?? '').toString();
    final expertName = (data['expertName'] ?? '—').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MonetizationTokens.radiusXl)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: MonetizationTokens.danger, size: 22),
            const SizedBox(width: 8),
            const Text('החזר כספי'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'להחזיר ₪${amount.toStringAsFixed(0)} ל-$customerName?',
              style: MonetizationTokens.body,
            ),
            const SizedBox(height: 8),
            Text('ספק: $expertName', style: MonetizationTokens.caption),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MonetizationTokens.dangerLight,
                borderRadius:
                    BorderRadius.circular(MonetizationTokens.radiusSm),
              ),
              child: const Text(
                'פעולה זו אינה הפיכה. הכספים יוחזרו ליתרת הלקוח והעבודה תבוטל.',
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 11, color: MonetizationTokens.dangerText),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: MonetizationTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.undo_rounded,
                size: 14, color: Colors.white),
            label: const Text('אשר החזר',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('jobs').doc(jobId), {
        'status': 'refunded',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': 'admin',
        'resolution': 'refund',
      });
      if (customerId.isNotEmpty) {
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(customerId),
          {'balance': FieldValue.increment(amount)},
        );
      }
      batch.set(FirebaseFirestore.instance.collection('transactions').doc(), {
        'senderId': 'platform',
        'receiverId': customerId,
        'amount': amount,
        'type': 'refund',
        'jobId': jobId,
        'timestamp': FieldValue.serverTimestamp(),
        'payoutStatus': 'completed',
      });
      await batch.commit();

      // Activity log
      try {
        await FirebaseFirestore.instance.collection('activity_log').add({
          'action': 'admin_refund',
          'category': 'monetization',
          'type': 'monetization_admin_refund',
          'title': 'החזר כספי ע"י אדמין',
          'detail':
              '₪${amount.toStringAsFixed(0)} → $customerName (job: $jobId)',
          'userId': customerId,
          'priority': 'high',
          'timestamp': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'expireAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 30))),
        });
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הוחזרו ₪${amount.toStringAsFixed(0)} ל-$customerName'),
          backgroundColor: MonetizationTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בהחזר: $e'),
          backgroundColor: MonetizationTokens.danger,
        ),
      );
    }
  }

  Future<void> _exportTransactionsCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('מכין קובץ CSV…')));
    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();

      final buf = StringBuffer();
      buf.write('\uFEFF');
      buf.writeln('מזהה,משתמש,כותרת,סכום,סוג,תאריך');
      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        final dateStr =
            ts != null ? DateFormat('dd/MM/yyyy HH:mm').format(ts) : '';
        final amount = (d['amount'] as num? ?? 0).toStringAsFixed(2);
        String esc(dynamic v) =>
            '"${(v ?? '').toString().replaceAll('"', '""')}"';
        buf.writeln([
          esc(doc.id),
          esc(d['userId']),
          esc(d['title']),
          esc(amount),
          esc(d['type']),
          esc(dateStr),
        ].join(','));
      }
      final name =
          'anyskill_transactions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      triggerCsvDownload(buf.toString(), name);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${snap.size} רשומות יוצאו ל-$name'),
          backgroundColor: MonetizationTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: MonetizationTokens.danger,
        ),
      );
    }
  }
}

/// Small key/value row used inside the release-escrow confirm dialog.
class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 14 : 12,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
              color: emphasize
                  ? MonetizationTokens.success
                  : MonetizationTokens.textPrimary,
            ),
          ),
          Text(label, style: MonetizationTokens.caption),
        ],
      ),
    );
  }
}

