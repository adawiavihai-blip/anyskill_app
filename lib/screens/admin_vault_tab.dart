import 'dart:async';
import 'dart:math' show max;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/vault_service.dart';
import '../utils/safe_image_provider.dart';

class AdminVaultTab extends StatefulWidget {
  const AdminVaultTab({super.key});

  @override
  State<AdminVaultTab> createState() => _AdminVaultTabState();
}

class _AdminVaultTabState extends State<AdminVaultTab> {
  String _period = 'month';
  Timer? _clockTimer;
  String _clock = '';

  // ── Data state ─────────────────────────────────────────────────────────────
  Map<String, dynamic> _adminSettings = {};
  List<Map<String, dynamic>> _currentEarnings = [];
  List<Map<String, dynamic>> _prevEarnings = [];
  List<Map<String, dynamic>> _activeJobs = [];
  List<Map<String, dynamic>> _recentTx = [];
  List<Map<String, dynamic>> _activityFeed = [];
  List<Map<String, dynamic>> _topProviders = [];
  Map<String, int> _counts = {};

  bool _loaded = false;

  StreamSubscription? _settingsSub;
  StreamSubscription? _earningsSub;
  StreamSubscription? _activeJobsSub;
  StreamSubscription? _txSub;
  StreamSubscription? _feedSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _setupStreams();
    _loadOnce();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _settingsSub?.cancel();
    _earningsSub?.cancel();
    _activeJobsSub?.cancel();
    _txSub?.cancel();
    _feedSub?.cancel();
    super.dispose();
  }

  void _updateClock() {
    if (!mounted) return;
    setState(() => _clock = DateFormat('HH:mm:ss', 'he').format(DateTime.now()));
  }

  void _setupStreams() {
    _settingsSub?.cancel();
    _earningsSub?.cancel();
    _activeJobsSub?.cancel();
    _txSub?.cancel();
    _feedSub?.cancel();

    _settingsSub = VaultService.streamAdminSettings().listen((d) {
      if (mounted) setState(() => _adminSettings = d);
    });

    _earningsSub = VaultService.streamEarnings(_period).listen((d) {
      if (mounted) {
        setState(() {
          _currentEarnings = d;
          _loaded = true;
        });
      }
    });

    _activeJobsSub = VaultService.streamActiveJobs().listen((d) {
      if (mounted) setState(() => _activeJobs = d);
    });

    _txSub = VaultService.streamRecentTransactions(limit: 20).listen((d) {
      if (mounted) setState(() => _recentTx = d);
    });

    _feedSub = VaultService.streamActivityFeed(limit: 15).listen((d) {
      if (mounted) setState(() => _activityFeed = d);
    });

    _loadPreviousPeriod();
  }

  Future<void> _loadPreviousPeriod() async {
    try {
      final start = VaultService.previousPeriodStart(_period);
      final end = VaultService.periodStart(_period);
      final prev = await VaultService.getEarningsForRange(start, end);
      if (mounted) setState(() => _prevEarnings = prev);
    } catch (_) {}
  }

  Future<void> _loadOnce() async {
    try {
      final providers = await VaultService.getTopProviders(limit: 5);
      final counts = await VaultService.getCounts();
      if (mounted) {
        setState(() {
          _topProviders = providers;
          _counts = counts;
        });
      }
    } catch (_) {}
  }

  void _onPeriodChanged(String p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _loaded = false;
    });
    _setupStreams();
  }

  // ── Palette ────────────────────────────────────────────────────────────────

  static const _green     = Color(0xFF1D9E75);
  static const _greenBg   = Color(0xFFE1F5EE);
  static const _greenText = Color(0xFF085041);
  static const _blue      = Color(0xFF378ADD);
  static const _blueBg    = Color(0xFFE6F1FB);
  static const _blueText  = Color(0xFF0C447C);
  static const _amber     = Color(0xFFEF9F27);
  static const _amberBg   = Color(0xFFFAEEDA);
  static const _amberText = Color(0xFF633806);
  static const _purple    = Color(0xFF7F77DD);
  static const _purpleBg  = Color(0xFFEEEDFE);
  static const _purpleText= Color(0xFF3C3489);
  static const _red       = Color(0xFFE24B4A);
  static const _redBg     = Color(0xFFFCEBEB);
  static const _dark      = Color(0xFF1A1A2E);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  _setupStreams();
                  await _loadOnce();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildTicker(),
                    const SizedBox(height: 16),
                    _buildBalanceAndHealth(),
                    const SizedBox(height: 16),
                    _buildMetricsGrid(),
                    const SizedBox(height: 16),
                    _buildLiveMonitor(),
                    const SizedBox(height: 16),
                    _buildRevenueChart(),
                    const SizedBox(height: 16),
                    _buildCategoryAndWaterfall(),
                    const SizedBox(height: 16),
                    _buildPeakHours(),
                    const SizedBox(height: 16),
                    _buildTopProviders(),
                    const SizedBox(height: 16),
                    _buildRecentTransactions(),
                    const SizedBox(height: 16),
                    _buildActivityFeed(),
                    const SizedBox(height: 16),
                    _buildQuickActions(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. HEADER + PERIOD SELECTOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.lock_rounded, color: _purple, size: 22),
        const SizedBox(width: 8),
        const Text(
          'AnySkill Vault',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
        const SizedBox(width: 8),
        _pulseDot(),
        const Spacer(),
        Text(_clock,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600])),
        const SizedBox(width: 12),
        _periodSelector(),
      ],
    );
  }

  Widget _pulseDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      builder: (_, v, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _green.withValues(alpha: v),
        ),
      ),
      onEnd: () => setState(() {}),
    );
  }

  Widget _periodSelector() {
    const periods = ['day', 'week', 'month', 'year'];
    const labels = ['היום', 'שבוע', 'חודש', 'שנה'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) {
          final sel = _period == periods[i];
          return GestureDetector(
            onTap: () => _onPeriodChanged(periods[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? _purple : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : Colors.grey[600],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. LIVE TICKER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTicker() {
    final todayRevenue = VaultService.sumField(_currentEarnings, 'amount');
    final activeCount = _activeJobs.length;
    final pendingCommission = _activeJobs.fold<double>(
        0, (s, j) => s + ((j['commission'] as num?) ?? 0).toDouble());
    final completedCount = _currentEarnings.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF2D2B55)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tickerBadge('LIVE', _green),
          const SizedBox(width: 16),
          _tickerItem('הכנסות', '₪${todayRevenue.toStringAsFixed(0)}'),
          _tickerDivider(),
          _tickerItem('פעילות', '$activeCount'),
          _tickerDivider(),
          _tickerItem('בדרך', '₪${pendingCommission.toStringAsFixed(0)}'),
          _tickerDivider(),
          _tickerItem('הושלמו', '$completedCount'),
        ],
      ),
    );
  }

  Widget _tickerBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }

  Widget _tickerItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey[400])),
      ],
    );
  }

  Widget _tickerDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(width: 1, height: 24, color: Colors.white24),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. BALANCE + HEALTH SCORE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBalanceAndHealth() {
    final totalPlatformBal =
        (_adminSettings['totalPlatformBalance'] as num? ?? 0).toDouble();
    final feePct =
        (_adminSettings['feePercentage'] as num? ?? 0.1).toDouble();

    final currentRev = VaultService.sumField(_currentEarnings, 'amount');
    final prevRev = VaultService.sumField(_prevEarnings, 'amount');
    final growth = VaultService.changePercent(currentRev, prevRev);

    final completedCount =
        _activeJobs.where((j) => j['status'] == 'completed').length;
    final cancelledCount =
        _activeJobs.where((j) => j['status'] == 'cancelled').length;
    final providerCount = _counts['providers'] ?? 0;

    final health = VaultService.computeHealthScore(
      revenueGrowth: growth,
      completedJobs: max(completedCount, _currentEarnings.length),
      cancelledJobs: cancelledCount,
      activeProviders: providerCount,
      avgSettlementHours: 12,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Balance card
        Expanded(
          flex: 3,
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        color: _green, size: 20),
                    const SizedBox(width: 8),
                    const Text('יתרת הפלטפורמה',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _dark)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '₪${totalPlatformBal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniPill(
                        'עמלה: ${(feePct * 100).toStringAsFixed(0)}%', _blue),
                    const SizedBox(width: 8),
                    _miniPill(
                        'תקופה: ₪${currentRev.toStringAsFixed(0)}', _green),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Health score
        Expanded(
          flex: 2,
          child: _card(
            child: Column(
              children: [
                const Text('בריאות עסקית',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _dark)),
                const SizedBox(height: 12),
                SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          value: (health['total'] ?? 0) / 100,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            _healthColor(health['total'] ?? 0),
                          ),
                        ),
                      ),
                      Text(
                        '${(health['total'] ?? 0).toInt()}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: _healthColor(health['total'] ?? 0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _healthRow('צמיחה', health['growth'] ?? 0),
                _healthRow('שימור', health['retention'] ?? 0),
                _healthRow('סליקה', health['settlement'] ?? 0),
                _healthRow('גיוון', health['diversity'] ?? 0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _healthColor(double score) {
    if (score >= 75) return _green;
    if (score >= 50) return _amber;
    return _red;
  }

  Widget _healthRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
          Expanded(
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(_healthColor(value)),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
              width: 24,
              child: Text('${value.toInt()}',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. METRICS GRID (4 cards)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetricsGrid() {
    final revenue = VaultService.sumField(_currentEarnings, 'amount');
    final prevRevenue = VaultService.sumField(_prevEarnings, 'amount');
    final txCount = _currentEarnings.length;
    final prevTxCount = _prevEarnings.length;
    final avgCommission = txCount > 0 ? revenue / txCount : 0.0;
    final prevAvg =
        prevTxCount > 0 ? prevRevenue / prevTxCount : 0.0;
    final providerCount = _counts['providers'] ?? 0;

    return Row(
      children: [
        Expanded(
            child: _metricCard(
          'הכנסות',
          '₪${revenue.toStringAsFixed(0)}',
          VaultService.changePercent(revenue, prevRevenue),
          '₪${prevRevenue.toStringAsFixed(0)}',
          _green,
          _greenBg,
          _greenText,
          Icons.trending_up_rounded,
        )),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(
          'עסקאות',
          '$txCount',
          VaultService.changePercent(
              txCount.toDouble(), prevTxCount.toDouble()),
          '$prevTxCount',
          _blue,
          _blueBg,
          _blueText,
          Icons.receipt_long_rounded,
        )),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(
          'עמלה ממוצעת',
          '₪${avgCommission.toStringAsFixed(1)}',
          VaultService.changePercent(avgCommission, prevAvg),
          '₪${prevAvg.toStringAsFixed(1)}',
          _amber,
          _amberBg,
          _amberText,
          Icons.price_check_rounded,
        )),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(
          'ספקים',
          '$providerCount',
          0,
          '',
          _purple,
          _purpleBg,
          _purpleText,
          Icons.people_rounded,
        )),
      ],
    );
  }

  Widget _metricCard(
    String title,
    String value,
    double changePct,
    String prevValue,
    Color accent,
    Color bg,
    Color textColor,
    IconData icon,
  ) {
    final isPositive = changePct >= 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const Spacer(),
              if (changePct != 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? _greenBg
                        : _redBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${changePct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isPositive ? _greenText : _red,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textColor)),
          const SizedBox(height: 2),
          Text(title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (prevValue.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('שעבר: $prevValue',
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. LIVE TRANSACTIONS MONITOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveMonitor() {
    final pipeline = VaultService.pipelineCounts(_activeJobs);
    final totalCommission = _activeJobs.fold<double>(
        0, (s, j) => s + ((j['commission'] as num?) ?? 0).toDouble());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              _pulseDot(),
              const SizedBox(width: 8),
              const Text('עסקאות פעילות עכשיו',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _dark)),
              const Spacer(),
              Text(_clock,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 12),
          // Summary pills
          Row(
            children: [
              _summaryPill('${_activeJobs.length} פעילות', _blue, _blueBg),
              const SizedBox(width: 8),
              _summaryPill(
                  '₪${totalCommission.toStringAsFixed(0)} עמלות',
                  _green,
                  _greenBg),
            ],
          ),
          const SizedBox(height: 12),
          // Pipeline
          _buildPipeline(pipeline),
          const SizedBox(height: 12),
          // Active job rows
          if (_activeJobs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('אין עסקאות פעילות כרגע',
                    style: TextStyle(color: Colors.grey[400])),
              ),
            )
          else
            ...(_activeJobs.take(8).map(_buildActiveJobRow)),
        ],
      ),
    );
  }

  Widget _buildPipeline(Map<String, int> pipeline) {
    final stages = [
      ('באסקרו', pipeline['paid_escrow'] ?? 0, _blue),
      ('הושלם ע"י ספק', pipeline['expert_completed'] ?? 0, _amber),
      ('מחלוקת', pipeline['disputed'] ?? 0, _red),
    ];
    return Row(
      children: stages
          .expand((s) => [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: s.$3.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: s.$3.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Text('${s.$2}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: s.$3)),
                        Text(s.$1,
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ),
                if (s != stages.last)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.arrow_back_rounded,
                        size: 14, color: Colors.grey[400]),
                  ),
              ])
          .toList(),
    );
  }

  Widget _buildActiveJobRow(Map<String, dynamic> job) {
    final customerName =
        (job['customerName'] as String?) ?? (job['customerId'] as String? ?? '');
    final expertName =
        (job['expertName'] as String?) ?? (job['expertId'] as String? ?? '');
    final status = job['status'] as String? ?? '';
    final amount = ((job['totalAmount'] as num?) ?? 0).toDouble();
    final commission = ((job['commission'] as num?) ?? 0).toDouble();
    final category = (job['category'] as String?) ??
        (job['serviceType'] as String?) ??
        '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$customerName ← $expertName',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _dark),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (category.isNotEmpty)
                    Text(category,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[500])),
                ],
              ),
            ),
            _statusPill(status),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₪${amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
                Text('עמלה: ₪${commission.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    Color bg, text;
    String label;
    switch (status) {
      case 'paid_escrow':
        bg = _blueBg;
        text = _blueText;
        label = 'אסקרו';
      case 'expert_completed':
        bg = _amberBg;
        text = _amberText;
        label = 'ממתין לאישור';
      case 'disputed':
        bg = _redBg;
        text = _red;
        label = 'מחלוקת';
      case 'completed':
        bg = _greenBg;
        text = _greenText;
        label = 'הושלם';
      default:
        bg = Colors.grey.shade100;
        text = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: text)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. REVENUE CHART
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRevenueChart() {
    final daily = VaultService.dailyBreakdown(_currentEarnings);
    if (daily.isEmpty) {
      return _card(
        child: Column(
          children: [
            const Text('גרף הכנסות',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _dark)),
            const SizedBox(height: 40),
            Text('אין נתונים לתקופה זו',
                style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 40),
          ],
        ),
      );
    }

    final sorted = daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final spots = sorted
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
    final maxY = spots.map((s) => s.y).reduce(max) * 1.2;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('גרף הכנסות',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _dark)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY == 0 ? 100 : maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 25,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, _) => Text(
                        '₪${v.toInt()}',
                        style: TextStyle(
                            fontSize: 9, color: Colors.grey[500]),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: max(1, (sorted.length / 6).ceilToDouble()),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= sorted.length) return const SizedBox();
                        final parts = sorted[i].key.split('-');
                        return Text(
                          '${parts[2]}/${parts[1]}',
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey[500]),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: _purple,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: spots.length <= 14,
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: _purple,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _purple.withValues(alpha: 0.25),
                          _purple.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. CATEGORY PIE + WATERFALL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryAndWaterfall() {
    final catBreakdown = VaultService.categoryBreakdown(_currentEarnings);
    final total = catBreakdown.values.fold(0.0, (s, v) => s + v);

    final colors = [_green, _blue, _amber, _purple, _red, const Color(0xFF64748B)];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pie chart
        Expanded(
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('פילוח לפי קטגוריה',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
                const SizedBox(height: 16),
                if (catBreakdown.isEmpty)
                  Center(
                      child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Text('אין נתונים',
                        style: TextStyle(color: Colors.grey[400])),
                  ))
                else ...[
                  SizedBox(
                    height: 160,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: catBreakdown.entries
                            .toList()
                            .asMap()
                            .entries
                            .map((e) {
                          final pct =
                              total > 0 ? e.value.value / total * 100 : 0.0;
                          return PieChartSectionData(
                            value: e.value.value,
                            color: colors[e.key % colors.length],
                            radius: 50,
                            title: '${pct.toStringAsFixed(0)}%',
                            titleStyle: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...catBreakdown.entries
                      .toList()
                      .asMap()
                      .entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colors[e.key % colors.length],
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(e.value.key,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[700]))),
                                Text(
                                    '₪${e.value.value.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _dark)),
                              ],
                            ),
                          )),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Waterfall / type breakdown
        Expanded(
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('פילוח לפי סוג',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
                const SizedBox(height: 16),
                _waterfallRow('שירות', _countBySource('quote'), _green),
                _waterfallRow('AnyTasks', _countBySource('anytask'), _blue),
                _waterfallRow(
                    'any_tasks', _countBySource('any_tasks'), _amber),
                const Divider(height: 20),
                _waterfallRow('סה"כ נטו', total, _purple, isBold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _countBySource(String source) {
    return _currentEarnings
        .where((e) => (e['source'] as String? ?? '') == source)
        .fold<double>(0, (s, e) => s + ((e['amount'] as num?) ?? 0).toDouble());
  }

  Widget _waterfallRow(String label, double amount, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                      color: _dark))),
          Text('₪${amount.toStringAsFixed(0)}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isBold ? _purple : _dark)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. PEAK HOURS HEATMAP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPeakHours() {
    final hourly = VaultService.hourlyDistribution(_currentEarnings);
    final maxVal = hourly.reduce(max);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('שעות שיא',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _dark)),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (h) {
                final val = hourly[h];
                final ratio = maxVal > 0 ? val / maxVal : 0.0;
                final isPeak = val == maxVal && maxVal > 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isPeak)
                          Text('$val',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: _purple)),
                        Container(
                          height: max(4, 60 * ratio),
                          decoration: BoxDecoration(
                            color: Color.lerp(
                                Colors.grey.shade200, _purple, ratio),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (h % 4 == 0)
                          Text(h.toString().padLeft(2, '0'),
                              style: TextStyle(
                                  fontSize: 8, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. TOP PROVIDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopProviders() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: _amber, size: 18),
              const SizedBox(width: 6),
              const Text('נותני שירות מובילים',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _dark)),
            ],
          ),
          const SizedBox(height: 12),
          if (_topProviders.isEmpty)
            Center(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('טוען...', style: TextStyle(color: Colors.grey[400])),
            ))
          else
            ...(_topProviders.asMap().entries.map((e) {
              final p = e.value;
              final rank = e.key + 1;
              final name = (p['name'] as String?) ?? 'ספק';
              final cat = (p['serviceType'] as String?) ?? '';
              final orders = (p['orderCount'] as num?) ?? 0;
              final rating = ((p['rating'] as num?) ?? 0).toDouble();
              final img = p['profileImage'] as String?;
              final isVip = p['isPromoted'] == true;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: rank <= 3 ? _amber : Colors.grey[500],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _purpleBg,
                      backgroundImage: safeImageProvider(img),
                      child: safeImageProvider(img) == null
                          ? Text(
                              name.isNotEmpty ? name[0] : '?',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _purple),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _dark),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (isVip) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _amberBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('VIP',
                                      style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: _amberText)),
                                ),
                              ],
                            ],
                          ),
                          Text(cat,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$orders הזמנות',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _dark)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 12, color: _amber),
                            Text(rating.toStringAsFixed(1),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            })),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. RECENT TRANSACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRecentTransactions() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: _blue, size: 18),
              const SizedBox(width: 6),
              const Text('עסקאות אחרונות',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _dark)),
              const Spacer(),
              Text('${_recentTx.length}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentTx.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('אין עסקאות',
                    style: TextStyle(color: Colors.grey[400])),
              ),
            )
          else
            ...(_recentTx.take(10).map((tx) {
              final type = tx['type'] as String? ?? '';
              final amount = ((tx['amount'] as num?) ?? 0).toDouble();
              final sender = tx['senderName'] as String? ?? '';
              final receiver = tx['receiverName'] as String? ?? '';
              final ts = tx['timestamp'] as Timestamp?;
              final status = tx['payoutStatus'] as String? ?? '';
              final isIncome = amount > 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isIncome ? _greenBg : _redBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isIncome
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 16,
                          color: isIncome ? _green : _red,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$sender → $receiver',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _dark),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Text(_txTypeLabel(type),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[500])),
                                if (status.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  _statusPill(status),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isIncome ? '+' : ''}₪${amount.abs().toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isIncome ? _green : _red,
                            ),
                          ),
                          if (ts != null)
                            Text(_formatTime(ts),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[400])),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            })),
        ],
      ),
    );
  }

  String _txTypeLabel(String type) {
    switch (type) {
      case 'quote_payment':
        return 'תשלום הצעה';
      case 'anytask_escrow_lock':
        return 'נעילת אסקרו';
      case 'anytask_escrow_release':
        return 'שחרור תשלום';
      case 'anytask_refund':
        return 'החזר';
      case 'admin_credit_grant':
        return 'קרדיט מנהל';
      case 'refund':
        return 'החזר';
      default:
        return type;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 11. ACTIVITY FEED
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActivityFeed() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rss_feed_rounded, color: _green, size: 18),
              const SizedBox(width: 6),
              const Text('פיד פעילות חי',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _dark)),
              const Spacer(),
              _pulseDot(),
            ],
          ),
          const SizedBox(height: 12),
          if (_activityFeed.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('אין פעילות אחרונה',
                    style: TextStyle(color: Colors.grey[400])),
              ),
            )
          else
            ...(_activityFeed.take(8).map((item) {
              final title = item['title'] as String? ?? '';
              final msg = item['message'] as String? ?? '';
              final ts = item['timestamp'] as Timestamp?;
              final type = item['type'] as String? ?? 'activity';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _feedDotColor(type),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title.isNotEmpty ? title : msg,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _dark),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          if (title.isNotEmpty && msg.isNotEmpty)
                            Text(msg,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[500]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (ts != null)
                      Text(_formatTime(ts),
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ),
              );
            })),
        ],
      ),
    );
  }

  Color _feedDotColor(String type) {
    if (type.contains('payment') || type.contains('completed')) return _green;
    if (type.contains('cancel') || type.contains('error')) return _red;
    if (type.contains('request') || type.contains('broadcast')) return _amber;
    return _blue;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 12. QUICK ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickActions() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('פעולות מהירות',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _dark)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip('דוח חודשי', Icons.description_rounded, _purple,
                  () => _showSnack('דוח חודשי — בקרוב')),
              _actionChip('ייצוא CSV', Icons.file_download_rounded, _green,
                  _exportCsv),
              _actionChip('real-time', Icons.bolt_rounded, _amber, () {
                // Scroll to live monitor
                _showSnack('מוניטור פעיל');
              }),
              _actionChip('התראות', Icons.notifications_active_rounded, _red,
                  () => _showSnack('הגדרת התראות — בקרוב')),
              _actionChip('VIP', Icons.diamond_rounded, _amber,
                  () => _showSnack('ניהול VIP — בקרוב')),
              _actionChip('חריגות', Icons.warning_amber_rounded, _red,
                  () => _showSnack('זיהוי חריגות — בקרוב')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    _showSnack('מייצא נתונים...');
    // Reuse pattern from admin_monetization_tab.dart
    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();
      _showSnack('נמצאו ${snap.docs.length} עסקאות — ייצוא בקרוב');
    } catch (e) {
      _showSnack('שגיאה: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Widget _miniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _summaryPill(String text, Color accent, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
    );
  }

  String _formatTime(Timestamp ts) {
    final d = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes}ד׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours}ש׳';
    return DateFormat('dd/MM', 'he').format(d);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
