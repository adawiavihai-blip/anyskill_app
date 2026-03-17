import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/business_ai_service.dart';
import 'pending_categories_screen.dart';
import '../l10n/app_localizations.dart';

// ── Color tokens ──────────────────────────────────────────────────────────────
const _kPurple = Color(0xFF6366F1);
const _kGreen  = Color(0xFF10B981);
const _kRed    = Color(0xFFEF4444);
const _kAmber  = Color(0xFFF59E0B);
const _kBlue   = Color(0xFF3B82F6);
const _kSlate  = Color(0xFF0F172A);

// ── Screen ────────────────────────────────────────────────────────────────────

class BusinessAiScreen extends StatefulWidget {
  const BusinessAiScreen({super.key});

  @override
  State<BusinessAiScreen> createState() => _BusinessAiScreenState();
}

class _BusinessAiScreenState extends State<BusinessAiScreen> {
  late Future<BusinessAiData> _future;
  StreamSubscription<int>?    _pendingSub;
  int  _pendingCount    = 0;
  int  _alertThreshold  = 5;
  bool _thresholdSaving = false;
  List<MarketAlert> _recentAlerts = [];

  @override
  void initState() {
    super.initState();
    _future = BusinessAiService.loadAll();
    _pendingSub = BusinessAiService.pendingQueueStream().listen((c) {
      if (mounted) setState(() => _pendingCount = c);
    });
    _loadAlertConfig();
  }

  Future<void> _loadAlertConfig() async {
    final results = await Future.wait([
      BusinessAiAlerts.getAlertThreshold(),
      BusinessAiAlerts.getRecentAlerts(),
    ]);
    if (!mounted) return;
    setState(() {
      _alertThreshold = results[0] as int;
      _recentAlerts   = results[1] as List<MarketAlert>;
    });
  }

  Future<void> _saveThreshold(int value) async {
    final msg = AppLocalizations.of(context).bizAiThresholdUpdated(value);
    setState(() => _thresholdSaving = true);
    await BusinessAiAlerts.setAlertThreshold(value);
    if (!mounted) return;
    setState(() {
      _alertThreshold  = value;
      _thresholdSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _kGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() => _future = BusinessAiService.loadAll());
    _loadAlertConfig();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: FutureBuilder<BusinessAiData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _kPurple),
                  const SizedBox(height: 16),
                  Text(l10n.bizAiLoading, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: _kRed, size: 48),
                  const SizedBox(height: 12),
                  Text(l10n.bizAiError('${snap.error}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _kRed)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retryButton),
                  ),
                ],
              ),
            );
          }

          final data = snap.data!;
          return RefreshIndicator(
            color: _kPurple,
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                // ── CEO Hero Stats ─────────────────────────────────────────────
                _HeroStatsGrid(
                  stats:            data.aiStats,
                  zeroResultsCount: data.zeroResults.length,
                  projectedWeekly:  data.projectedWeekly,
                ),
                const SizedBox(height: 20),
                _AiOpsSection(stats: data.aiStats, pendingCount: _pendingCount),
                const SizedBox(height: 20),
                _MarketSection(
                    trending: data.trending, zeroResults: data.zeroResults),
                const SizedBox(height: 20),
                _FinancialSection(
                  weeklyEarnings:      data.weeklyEarnings,
                  projectedWeekly:     data.projectedWeekly,
                  highValueCategories: data.highValueCategories,
                  dailyEarnings:       data.dailyEarnings,
                ),
                const SizedBox(height: 20),
                _AlertsSection(
                  threshold:     _alertThreshold,
                  saving:        _thresholdSaving,
                  recentAlerts:  _recentAlerts,
                  onSave:        _saveThreshold,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: Text(l10n.bizAiRefreshData, style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _kPurple.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.bizAiTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                Text(
                  l10n.bizAiSubtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13),
                ),
              ],
            ),
          ),
          if (_pendingCount > 0)
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const PendingCategoriesScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _kAmber,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(l10n.bizAiPending(_pendingCount),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Section 1: AI Operations Center ──────────────────────────────────────────

class _AiOpsSection extends StatelessWidget {
  const _AiOpsSection({required this.stats, required this.pendingCount});

  final AiStats stats;
  final int     pendingCount;

  @override
  Widget build(BuildContext context) {
    final total    = stats.approvedTotal + stats.rejectedTotal + stats.pendingTotal;
    final pctLabel = total == 0
        ? '—'
        : '${(stats.approvalRate * 100).round()}%';

    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: l10n.bizAiSectionAiOps, icon: Icons.psychology_rounded, color: _kPurple),
        const SizedBox(height: 12),

        // ── 3 metric cards ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label:    l10n.bizAiActivityToday,
                value:    stats.todayCount.toString(),
                icon:     Icons.bolt_rounded,
                color:    _kPurple,
                subtitle: l10n.bizAiNewCategories,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const PendingCategoriesScreen())),
                child: _MetricCard(
                  label:    l10n.bizAiApprovalQueue,
                  value:    pendingCount.toString(),
                  icon:     Icons.pending_actions_rounded,
                  color:    pendingCount > 0 ? _kAmber : _kGreen,
                  subtitle: l10n.bizAiTapToReview,
                  isHighlight: pendingCount > 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label:    l10n.bizAiModelAccuracy,
                value:    pctLabel,
                icon:     Icons.verified_rounded,
                color:    stats.approvalRate >= 0.7 ? _kGreen : _kAmber,
                subtitle: l10n.bizAiApprovedTotal,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Precision pie chart ───────────────────────────────────────────────
        if (total > 0)
          _CardWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(l10n.bizAiModelAccuracyDetail,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _kSlate)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: Row(
                    children: [
                      Expanded(
                        child: PieChart(
                          PieChartData(
                            sections: [
                              if (stats.approvedTotal > 0)
                                PieChartSectionData(
                                  value:     stats.approvedTotal.toDouble(),
                                  color:     _kGreen,
                                  title:     '${stats.approvedTotal}',
                                  radius:    70,
                                  titleStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                              if (stats.rejectedTotal > 0)
                                PieChartSectionData(
                                  value:     stats.rejectedTotal.toDouble(),
                                  color:     _kRed,
                                  title:     '${stats.rejectedTotal}',
                                  radius:    70,
                                  titleStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                              if (stats.pendingTotal > 0)
                                PieChartSectionData(
                                  value:     stats.pendingTotal.toDouble(),
                                  color:     _kAmber,
                                  title:     '${stats.pendingTotal}',
                                  radius:    70,
                                  titleStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                            ],
                            centerSpaceRadius: 36,
                            sectionsSpace:     3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PieLegend(color: _kGreen,  label: l10n.bizAiApproved, count: stats.approvedTotal),
                          const SizedBox(height: 10),
                          _PieLegend(color: _kRed,    label: l10n.bizAiRejected,  count: stats.rejectedTotal),
                          const SizedBox(height: 10),
                          _PieLegend(color: _kAmber,  label: l10n.bizAiPendingLabel, count: stats.pendingTotal),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (total == 0)
          _EmptyCard(
            icon:    Icons.smart_toy_outlined,
            message: l10n.bizAiNoData,
          ),
      ],
    );
  }
}

// ── Section 2: Market Demand ──────────────────────────────────────────────────

class _MarketSection extends StatelessWidget {
  const _MarketSection({required this.trending, required this.zeroResults});

  final List<TrendingSearch> trending;
  final List<TrendingSearch> zeroResults;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: l10n.bizAiSectionMarket, icon: Icons.trending_up_rounded, color: _kBlue),
        const SizedBox(height: 12),

        // Trending searches
        _CardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${trending.length}',
                        style: const TextStyle(
                            color: _kBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  Text(l10n.bizAiPopularSearches,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _kSlate)),
                ],
              ),
              const SizedBox(height: 12),
              if (trending.isEmpty)
                _InlineEmpty(message: l10n.bizAiNoSearchData)
              else
                ...trending.asMap().entries.map((e) => _TrendingRow(
                      rank:  e.key + 1,
                      item:  e.value,
                      maxCount: trending.first.count,
                    )),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Zero-results opportunities
        _CardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  if (zeroResults.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${zeroResults.length} ניש',
                          style: const TextStyle(
                              color: _kRed,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  const Spacer(),
                  Text(l10n.bizAiMarketOpportunities,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _kSlate)),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.bizAiZeroResultsHint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              if (zeroResults.isEmpty)
                _InlineEmpty(message: l10n.bizAiNoOpportunities)
              else
                ...zeroResults.map((item) => _ZeroResultRow(item: item)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section 3: Financial Insights ────────────────────────────────────────────

class _FinancialSection extends StatelessWidget {
  const _FinancialSection({
    required this.weeklyEarnings,
    required this.projectedWeekly,
    required this.highValueCategories,
    required this.dailyEarnings,
  });

  final double weeklyEarnings;
  final double projectedWeekly;
  final List<CategoryRevenue> highValueCategories;
  final List<double> dailyEarnings;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'he_IL');

    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
            label: l10n.bizAiSectionFinancial, icon: Icons.attach_money_rounded, color: _kGreen),
        const SizedBox(height: 12),

        // Commission forecast card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF059669), Color(0xFF10B981)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: _kGreen.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.rocket_launch_rounded,
                      color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Text(l10n.bizAiWeeklyForecast,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(l10n.bizAiSevenDays,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ForecastTile(
                      label:  l10n.bizAiActualToDate,
                      amount: '₪${fmt.format(weeklyEarnings)}',
                      icon:   Icons.check_circle_outline,
                    ),
                  ),
                  Container(width: 1, height: 50, color: Colors.white.withValues(alpha: 0.3)),
                  Expanded(
                    child: _ForecastTile(
                      label:  l10n.bizAiWeeklyProjection,
                      amount: '₪${fmt.format(projectedWeekly)}',
                      icon:   Icons.trending_up_rounded,
                      isProjected: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Daily earnings line chart ──────────────────────────────────────
        _CardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(l10n.bizAiLast7Days,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kSlate)),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.bizAiDailyCommission,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              _EarningsLineChart(daily: dailyEarnings),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // High-value categories bar chart
        _CardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(l10n.bizAiHighValueCategories,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kSlate)),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.bizAiHighValueHint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              if (highValueCategories.isEmpty)
                _InlineEmpty(message: l10n.bizAiNoOrderData)
              else
                SizedBox(
                  height: 220,
                  child: _HighValueBarChart(categories: highValueCategories),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Bar chart ─────────────────────────────────────────────────────────────────

class _HighValueBarChart extends StatelessWidget {
  const _HighValueBarChart({required this.categories});

  final List<CategoryRevenue> categories;

  @override
  Widget build(BuildContext context) {
    final maxY = categories.isEmpty
        ? 1.0
        : (categories.first.estimatedRevenue * 1.2).ceilToDouble();

    final barGroups = categories.asMap().entries.map((e) {
      final colors = [_kPurple, _kBlue, _kGreen, _kAmber, _kRed,
                      Color(0xFF8B5CF6), Color(0xFF06B6D4), Color(0xFFF97316)];
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY:          e.value.estimatedRevenue,
            color:        colors[e.key % colors.length],
            width:        22,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show:  true,
              toY:   maxY,
              color: Colors.grey.shade100,
            ),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        maxY: maxY,
        barGroups: barGroups,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 52,
              getTitlesWidget: (v, meta) => Text(
                '₪${NumberFormat.compact().format(v)}',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= categories.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    categories[i].name,
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final cat = categories[group.x];
              final l10n = AppLocalizations.of(context);
              return BarTooltipItem(
                '${cat.name}\n₪${NumberFormat('#,##0').format(rod.toY)}\n${l10n.bizAiProviders(cat.providerCount)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Reusable small widgets ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.icon, required this.color});

  final String  label;
  final IconData icon;
  final Color   color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _kSlate)),
        ],
      );
}

class _CardWrapper extends StatelessWidget {
  const _CardWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: child,
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
    this.isHighlight = false,
  });

  final String  label;
  final String  value;
  final IconData icon;
  final Color   color;
  final String  subtitle;
  final bool    isHighlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isHighlight ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isHighlight ? Border.all(color: color.withValues(alpha: 0.3)) : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 18),
                Text(value,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kSlate)),
            Text(subtitle,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ),
      );
}

class _PieLegend extends StatelessWidget {
  const _PieLegend({required this.color, required this.label, required this.count});

  final Color  color;
  final String label;
  final int    count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('$count',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: _kSlate)),
          const SizedBox(width: 6),
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ],
      );
}

class _TrendingRow extends StatelessWidget {
  const _TrendingRow({required this.rank, required this.item, required this.maxCount});

  final int           rank;
  final TrendingSearch item;
  final int           maxCount;

  @override
  Widget build(BuildContext context) {
    final pct = maxCount == 0 ? 0.0 : item.count / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Text('${item.count}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('#$rank ${item.query}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kSlate)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:            pct,
              backgroundColor:  Colors.grey.shade100,
              color:            _kBlue.withValues(alpha: 0.7),
              minHeight:        4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZeroResultRow extends StatelessWidget {
  const _ZeroResultRow({required this.item});

  final TrendingSearch item;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kRed.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            ElevatedButton(
              onPressed: () {
                final l10n = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l10n.bizAiRecruitForQuery(item.query)),
                  backgroundColor: _kPurple,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Builder(builder: (ctx) => Text(AppLocalizations.of(ctx).bizAiRecruitNow)),
            ),
            const Spacer(),
            Text('"${item.query}"',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: _kSlate)),
            const SizedBox(width: 8),
            const Icon(Icons.warning_amber_rounded, color: _kRed, size: 16),
          ],
        ),
      );
}

class _ForecastTile extends StatelessWidget {
  const _ForecastTile({
    required this.label,
    required this.amount,
    required this.icon,
    this.isProjected = false,
  });

  final String  label;
  final String  amount;
  final IconData icon;
  final bool    isProjected;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
          const SizedBox(height: 6),
          Text(amount,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isProjected ? 18 : 16,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11)),
          if (isProjected)
            Builder(builder: (ctx) {
              final l10n = AppLocalizations.of(ctx);
              return Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(l10n.bizAiForecastBadge,
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              );
            }),
        ],
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String   message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.grey.shade300, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ],
        ),
      );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ),
      );
}

// ── Section 4: Alert Configuration & History ─────────────────────────────────

class _AlertsSection extends StatefulWidget {
  const _AlertsSection({
    required this.threshold,
    required this.saving,
    required this.recentAlerts,
    required this.onSave,
  });

  final int               threshold;
  final bool              saving;
  final List<MarketAlert> recentAlerts;
  final ValueChanged<int> onSave;

  @override
  State<_AlertsSection> createState() => _AlertsSectionState();
}

class _AlertsSectionState extends State<_AlertsSection> {
  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.threshold.toDouble();
  }

  @override
  void didUpdateWidget(_AlertsSection old) {
    super.didUpdateWidget(old);
    if (old.threshold != widget.threshold) {
      _sliderValue = widget.threshold.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
            label: l10n.bizAiSectionAlerts,
            icon:  Icons.notifications_active_rounded,
            color: _kRed),
        const SizedBox(height: 12),

        // ── Threshold config card ─────────────────────────────────────────────
        _CardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  if (widget.saving)
                    const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kPurple))
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        l10n.bizAiSearches(_sliderValue.round()),
                        style: const TextStyle(
                            color: _kPurple,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  const Spacer(),
                  Text(l10n.bizAiAlertThreshold,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _kSlate)),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.bizAiAlertThresholdHint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('20',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor:   _kPurple,
                        inactiveTrackColor: _kPurple.withValues(alpha: 0.15),
                        thumbColor:         _kPurple,
                        overlayColor:       _kPurple.withValues(alpha: 0.12),
                        trackHeight:        4,
                      ),
                      child: Slider(
                        value:     _sliderValue,
                        min:       2,
                        max:       20,
                        divisions: 18,
                        label:     _sliderValue.round().toString(),
                        onChanged: (v) => setState(() => _sliderValue = v),
                      ),
                    ),
                  ),
                  const Text('2',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _sliderValue = 5),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text(l10n.bizAiReset,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: widget.saving
                          ? null
                          : () => widget.onSave(_sliderValue.round()),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text(l10n.bizAiSaveThreshold,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Recent alerts history ─────────────────────────────────────────────
        _CardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${widget.recentAlerts.length}',
                        style: const TextStyle(
                            color: _kRed,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  Text(l10n.bizAiAlertHistory,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _kSlate)),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.recentAlerts.isEmpty)
                _InlineEmpty(message: l10n.bizAiNoAlerts)
              else
                ...widget.recentAlerts.map((a) => _AlertHistoryRow(alert: a)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertHistoryRow extends StatelessWidget {
  const _AlertHistoryRow({required this.alert});

  final MarketAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timeAgo = alert.lastAlertedAt == null
        ? '—'
        : _formatTimeAgo(l10n, alert.lastAlertedAt!);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timeAgo,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade400)),
              const SizedBox(height: 2),
              Text(l10n.bizAiAlertCount(alert.totalAlerts),
                  style: TextStyle(
                      fontSize: 10,
                      color: _kRed.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _kAmber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(l10n.bizAiSearchCount(alert.searchCount),
                style: const TextStyle(
                    fontSize: 10,
                    color: _kAmber,
                    fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('"${alert.keyword}"',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kSlate)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.notifications_rounded, color: _kRed, size: 16),
        ],
      ),
    );
  }

  String _formatTimeAgo(AppLocalizations l10n, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return l10n.bizAiMinutesAgo(diff.inMinutes);
    if (diff.inHours   < 24) return l10n.bizAiHoursAgo(diff.inHours);
    return l10n.bizAiDaysAgo(diff.inDays);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLASSMORPHISM CEO HERO SECTION
// Three large gradient cards: AI Accuracy · Missed Opportunities · Revenue
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroStatsGrid extends StatelessWidget {
  const _HeroStatsGrid({
    required this.stats,
    required this.zeroResultsCount,
    required this.projectedWeekly,
  });

  final AiStats stats;
  final int     zeroResultsCount;
  final double  projectedWeekly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fmt = NumberFormat('#,##0', 'he_IL');
    final reviewed = stats.approvedTotal + stats.rejectedTotal;
    final pctLabel = reviewed == 0
        ? '—'
        : '${(stats.approvalRate * 100).round()}%';
    final revenueLabel = projectedWeekly >= 10000
        ? '₪${NumberFormat.compact().format(projectedWeekly)}'
        : '₪${fmt.format(projectedWeekly)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bar_chart_rounded, color: _kPurple, size: 14),
            ),
            const SizedBox(width: 7),
            Text(l10n.bizAiExecSummary,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _kSlate)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _GlassStatCard(
                icon: Icons.verified_rounded,
                label: l10n.bizAiAccuracy,
                value: pctLabel,
                subtitle: l10n.bizAiCategoriesApproved,
                gradientColors: const [Color(0xFF4F46E5), Color(0xFF818CF8)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassStatCard(
                icon: Icons.crisis_alert_rounded,
                label: l10n.bizAiMarketOppsCard,
                value: '$zeroResultsCount',
                subtitle: l10n.bizAiNichesNoProviders,
                gradientColors: const [Color(0xFFDC2626), Color(0xFFF87171)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassStatCard(
                icon: Icons.rocket_launch_rounded,
                label: l10n.bizAiExpectedRevenue,
                value: revenueLabel,
                subtitle: l10n.bizAiWeeklyProjection,
                gradientColors: const [Color(0xFF059669), Color(0xFF34D399)],
                smallValue: projectedWeekly >= 10000,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Single glassmorphism stat card ────────────────────────────────────────────

class _GlassStatCard extends StatelessWidget {
  const _GlassStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.gradientColors,
    this.smallValue = false,
  });

  final IconData    icon;
  final String      label;
  final String      value;
  final String      subtitle;
  final List<Color> gradientColors;
  final bool        smallValue;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 1),
              boxShadow: [
                BoxShadow(
                  color: gradientColors.last.withValues(alpha: 0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    color: Colors.white.withValues(alpha: 0.9), size: 20),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: smallValue ? 17 : 24,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 10)),
              ],
            ),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// EARNINGS LINE CHART — 7-day daily commission trend
// ═══════════════════════════════════════════════════════════════════════════════

class _EarningsLineChart extends StatelessWidget {
  const _EarningsLineChart({required this.daily});

  /// 7 entries, index 0 = 6 days ago, index 6 = today.
  final List<double> daily;

  @override
  Widget build(BuildContext context) {
    final hasData = daily.any((v) => v > 0);
    if (!hasData) {
      return Builder(builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return _InlineEmpty(message: l10n.bizAiNoChartData);
      });
    }

    final rawMax = daily.reduce((a, b) => a > b ? a : b);
    final maxY   = rawMax == 0 ? 1.0 : rawMax * 1.35;

    final spots = daily
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    // Short day labels: day/month
    final now = DateTime.now();
    final dayLabels = List.generate(
      7,
      (i) {
        final d = now.subtract(Duration(days: 6 - i));
        return '${d.day}/${d.month}';
      },
    );

    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey.shade100, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 52,
                getTitlesWidget: (v, _) => Text(
                  '₪${NumberFormat.compact().format(v)}',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= dayLabels.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(dayLabels[i],
                        style: const TextStyle(
                            fontSize: 9, color: Colors.grey)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots:    spots,
              isCurved: true,
              color:    _kPurple,
              barWidth: 3,
              dotData: FlDotData(
                getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                  radius:      4,
                  color:       Colors.white,
                  strokeWidth: 2.5,
                  strokeColor: _kPurple,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _kPurple.withValues(alpha: 0.22),
                    _kPurple.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots
                  .map((s) => LineTooltipItem(
                        '₪${NumberFormat('#,##0').format(s.y)}',
                        const TextStyle(
                            color:      Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize:   12),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
