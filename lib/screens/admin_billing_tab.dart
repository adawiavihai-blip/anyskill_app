import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../providers/admin_billing_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Real-time Financial Health Dashboard — admin only.
///
/// Architecture:
///   AdminBillingRepository  (Firestore + Cloud Functions)
///       ↓
///   billingStatsProvider    (autoDispose Stream — GC'd when tab closes)
///   monthlyRevenueProvider  (autoDispose Future — one-shot)
///   BillingActions          (autoDispose Notifier — save/toggle)
///       ↓
///   AdminBillingTab         (ConsumerStatefulWidget — this file)
///
/// Every Firestore stream and cached state is released when the admin
/// navigates away from this tab.
// ─────────────────────────────────────────────────────────────────────────────

class AdminBillingTab extends ConsumerStatefulWidget {
  const AdminBillingTab({super.key});

  @override
  ConsumerState<AdminBillingTab> createState() => _AdminBillingTabState();
}

class _AdminBillingTabState extends ConsumerState<AdminBillingTab> {
  // Brand
  static const _kPurple = Color(0xFF6366F1);
  static const _kGreen = Color(0xFF059669);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kRed = Color(0xFFEF4444);
  static const _kSurface = Color(0xFFF8F7FF);

  final _budgetCtrl = TextEditingController();
  final _killLimitCtrl = TextEditingController();

  @override
  void dispose() {
    _budgetCtrl.dispose();
    _killLimitCtrl.dispose();
    super.dispose();
  }

  // ── Projection ─────────────────────────────────────────────────────────

  double _projectMonthEnd(double currentApiCost, double currentInfraCost) {
    final now = DateTime.now();
    final daysElapsed = now.day.toDouble();
    final daysInMonth =
        DateUtils.getDaysInMonth(now.year, now.month).toDouble();
    if (daysElapsed < 1) return currentApiCost + currentInfraCost;
    final dailyRate = (currentApiCost + currentInfraCost) / daysElapsed;
    return dailyRate * daysInMonth;
  }

  // ── Save handler ───────────────────────────────────────────────────────

  Future<void> _save() async {
    final newBudget = double.tryParse(_budgetCtrl.text.trim());
    final newKillLimit = double.tryParse(_killLimitCtrl.text.trim());
    if (newBudget == null && newKillLimit == null) return;

    final ok = await ref.read(billingActionsProvider.notifier).saveBudgetSettings(
          budgetLimit: newBudget,
          killSwitchLimit: newKillLimit,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'הגדרות נשמרו ✓' : 'שגיאה בשמירה'),
      backgroundColor: ok ? _kGreen : _kRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // ── Watch the billing stats stream (autoDispose) ─────────────────
    final statsAsync = ref.watch(billingStatsProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (data) => _buildContent(data),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final apiCost =
        (data['current_month_api_cost'] as num? ?? 0).toDouble();
    final infraCost =
        (data['current_month_infra_cost'] as num? ?? 0).toDouble();
    final totalCost = apiCost + infraCost;
    final projected = _projectMonthEnd(apiCost, infraCost);
    final budget =
        (data['budget_limit'] as num? ?? 50).toDouble();
    final killLimit =
        (data['kill_switch_limit'] as num? ?? 100).toDouble();
    final killActive =
        data['ai_kill_switch_active'] as bool? ?? false;
    final inputTok =
        (data['total_input_tokens'] as num? ?? 0).toInt();
    final outputTok =
        (data['total_output_tokens'] as num? ?? 0).toInt();
    final callCount =
        (data['api_call_count'] as num? ?? 0).toInt();

    // Pre-fill only when empty
    if (_budgetCtrl.text.isEmpty && budget > 0) {
      _budgetCtrl.text = budget.toStringAsFixed(0);
    }
    if (_killLimitCtrl.text.isEmpty && killLimit > 0) {
      _killLimitCtrl.text = killLimit.toStringAsFixed(0);
    }

    final budgetPct =
        budget > 0 ? (totalCost / budget).clamp(0.0, 1.0) : 0.0;

    final snapshots =
        (data['daily_snapshots'] as Map<String, dynamic>?) ?? {};
    final chartData = _buildChartData(snapshots);

    // ── Watch isSaving from BillingActions (select for precision) ────
    final isSaving = ref.watch(billingActionsProvider);

    // ── Monthly revenue (one-shot, autoDispose) ─────────────────────
    final revenueAsync = ref.watch(monthlyRevenueProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (killActive) _buildKillSwitchBanner(),

        _buildSectionTitle('סיכום חודשי'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildKpiCard(
              label: 'הוצאה נוכחית',
              value: '\$${totalCost.toStringAsFixed(3)}',
              subtitle: 'API + תשתית',
              icon: Icons.payments_rounded,
              color: totalCost > budget * 0.8 ? _kRed : _kPurple,
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _buildKpiCard(
              label: 'תחזית חודש',
              value: '\$${projected.toStringAsFixed(2)}',
              subtitle: 'לינארית לפי burn rate',
              icon: Icons.trending_up_rounded,
              color: projected > killLimit ? _kRed : _kAmber,
            )),
            const SizedBox(width: 10),
            Expanded(
              child: revenueAsync.when(
                loading: () => _buildKpiCard(
                  label: 'הכנסות',
                  value: '...',
                  subtitle: 'טוען...',
                  icon: Icons.account_balance_wallet_rounded,
                  color: _kGreen,
                ),
                error: (_, __) => _buildKpiCard(
                  label: 'הכנסות',
                  value: '—',
                  subtitle: 'שגיאה',
                  icon: Icons.account_balance_wallet_rounded,
                  color: _kRed,
                ),
                data: (revenue) => _buildKpiCard(
                  label: 'הכנסות',
                  value: '₪${NumberFormat('#,###').format(revenue)}',
                  subtitle: 'עמלות החודש',
                  icon: Icons.account_balance_wallet_rounded,
                  color: _kGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildBudgetBar(totalCost, budget, budgetPct),
        const SizedBox(height: 20),
        if (chartData.isNotEmpty) ...[
          _buildSectionTitle('הוצאה יומית (30 יום אחרונים)'),
          const SizedBox(height: 12),
          _buildDailyChart(chartData),
          const SizedBox(height: 20),
        ],
        _buildSectionTitle('פירוט שימוש ב-API'),
        const SizedBox(height: 12),
        _buildTokenBreakdown(apiCost, inputTok, outputTok, callCount),
        const SizedBox(height: 20),
        _buildSectionTitle('הגדרות תקציב'),
        const SizedBox(height: 12),
        _buildBudgetControls(killActive, isSaving),
      ],
    );
  }

  // ── Widget builders (unchanged UI — same pixel output) ─────────────────

  Widget _buildKillSwitchBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kRed.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _kRed, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kill-Switch פעיל — כל סוכני ה-AI עברו למצב בסיסי.\nהגעת למגבלת ה-API החודשית.',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: _kRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
                color: _kPurple,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B4B))),
      ],
    );
  }

  Widget _buildKpiCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E1B4B))),
          Text(subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildBudgetBar(double spend, double budget, double pct) {
    final overBudget = spend > budget;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ניצול תקציב חודשי',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              Text(
                  '\$${spend.toStringAsFixed(3)} / \$${budget.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: overBudget ? _kRed : Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(
                  pct > 0.9
                      ? _kRed
                      : pct > 0.7
                          ? _kAmber
                          : _kGreen),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(pct * 100).toStringAsFixed(1)}% מהתקציב',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildTokenBreakdown(
      double apiCost, int inputTok, int outputTok, int callCount) {
    final fmt = NumberFormat('#,###');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          _tokenRow('קריאות ל-Claude', '$callCount',
              Icons.hub_rounded, _kPurple),
          const Divider(height: 16),
          _tokenRow('טוקנים קלט', fmt.format(inputTok),
              Icons.input_rounded, _kAmber),
          const Divider(height: 16),
          _tokenRow('טוקנים פלט', fmt.format(outputTok),
              Icons.output_rounded, const Color(0xFF8B5CF6)),
          const Divider(height: 16),
          _tokenRow('עלות API החודש', '\$${apiCost.toStringAsFixed(4)}',
              Icons.attach_money_rounded, _kGreen),
        ],
      ),
    );
  }

  Widget _tokenRow(
      String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13))),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color)),
      ],
    );
  }

  Widget _buildDailyChart(List<FlSpot> spots) {
    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10)
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '\$${s.y.toStringAsFixed(4)}',
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _kPurple,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: _kPurple.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetControls(bool killActive, bool isSaving) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSettingField(
            ctrl: _budgetCtrl,
            label: 'מגבלת תקציב חודשית (\$)',
            hint: 'לדוגמה: 50',
            icon: Icons.notifications_active_rounded,
            color: _kAmber,
          ),
          const SizedBox(height: 12),
          _buildSettingField(
            ctrl: _killLimitCtrl,
            label: 'מגבלת Kill-Switch (\$)',
            hint: 'לדוגמה: 100',
            icon: Icons.power_settings_new_rounded,
            color: _kRed,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('שמור הגדרות',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const Divider(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Kill-Switch ידני',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: killActive
                            ? _kRed
                            : const Color(0xFF1E1B4B)),
                  ),
                  Text(
                    killActive
                        ? 'כל ה-AI agents במצב בסיסי'
                        : 'כל ה-AI agents פעילים',
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            killActive ? _kRed : Colors.grey[500]),
                  ),
                ],
              ),
              Switch(
                value: killActive,
                onChanged: (v) => ref
                    .read(billingActionsProvider.notifier)
                    .toggleKillSwitch(v),
                activeColor: _kRed,
                inactiveThumbColor: _kGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: color, size: 20),
        filled: true,
        fillColor: _kSurface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: color.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: 1.5),
        ),
      ),
    );
  }

  List<FlSpot> _buildChartData(Map<String, dynamic> snapshots) {
    if (snapshots.isEmpty) return [];
    final sorted = snapshots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final recent =
        sorted.length > 30 ? sorted.sublist(sorted.length - 30) : sorted;
    return recent.asMap().entries.map((e) {
      final d = e.value.value as Map<String, dynamic>? ?? {};
      final cost = (d['infra_cost'] as num? ?? 0).toDouble();
      return FlSpot(e.key.toDouble(), cost);
    }).toList();
  }
}
