import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../widgets/banner_carousel.dart';
import 'withdrawal_modal.dart';
import '../l10n/app_localizations.dart';
import '../widgets/hint_icon.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kCardStart = Color(0xFF1A0E3C);
const _kCardMid   = Color(0xFF3D1F8B);
const _kCardEnd   = Color(0xFF6D28D9);
const _kChartLine = Color(0xFF6366F1);

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  // ── Count-up animation (provider only) ───────────────────────────────────
  late AnimationController _countCtrl;
  late Animation<double>   _countAnim;
  bool   _animStarted = false;
  double _animTarget   = 0;

  // ── 7-day earnings chart (provider only) ─────────────────────────────────
  List<double> _dailyEarnings = List.filled(7, 0);
  bool     _chartLoaded    = false;
  double   _pendingWeekly  = 0;
  double   _finalizedTotal = 0;
  DateTime? _nextPayoutDate;

  @override
  void initState() {
    super.initState();
    _countCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _countAnim = const AlwaysStoppedAnimation(0);
    _loadChartData();
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    super.dispose();
  }

  // ── Provider: count-up ────────────────────────────────────────────────────
  void _startCountUp(double balance) {
    if (_animStarted && balance == _animTarget) return;
    _animStarted = true;
    _animTarget  = balance;
    _countCtrl.reset();
    _countAnim = Tween<double>(begin: 0, end: balance).animate(
      CurvedAnimation(parent: _countCtrl, curve: Curves.easeOutCubic),
    );
    _countCtrl.forward();
    // Sound removed: this fires on screen init, NOT on actual payment.
    // Real payment sounds are triggered by playEvent(onPaymentSuccess) in chat_screen.
  }

  // ── Provider: 7-day chart data ────────────────────────────────────────────
  Future<void> _loadChartData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('receiverId', isEqualTo: uid)
          .limit(200)
          .get();

      final earnings = List<double>.filled(7, 0);
      final now      = DateTime.now();
      for (final doc in snap.docs) {
        final d      = doc.data();
        final ts     = d['timestamp'] as Timestamp?;
        final amt    = (d['amount'] as num?)?.toDouble() ?? 0;
        if (ts == null || amt <= 0) continue;
        final daysAgo = now.difference(ts.toDate()).inDays;
        if (daysAgo >= 0 && daysAgo < 7) earnings[6 - daysAgo] += amt;
      }

      double pendingW  = 0;
      double finalized = 0;
      for (final doc in snap.docs) {
        final d          = doc.data();
        final ts         = d['timestamp']    as Timestamp?;
        final amt        = (d['amount'] as num?)?.toDouble() ?? 0;
        final paidStatus = d['payoutStatus']?.toString() ?? '';
        if (ts == null || amt <= 0) continue;
        final daysAgo = now.difference(ts.toDate()).inDays;
        if (daysAgo < 7) {
          pendingW += amt;
        } else if (paidStatus != 'paid') {
          finalized += amt;
        }
      }

      final today          = DateTime.now();
      final daysUntilMon   = (DateTime.monday - today.weekday + 7) % 7;
      final nextMonday     = daysUntilMon == 0
          ? today.add(const Duration(days: 7))
          : today.add(Duration(days: daysUntilMon));

      if (mounted) {
        setState(() {
          _dailyEarnings  = earnings;
          _pendingWeekly  = pendingW;
          _finalizedTotal = finalized;
          _nextPayoutDate = nextMonday;
          _chartLoaded    = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _chartLoaded = true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final uid  = FirebaseAuth.instance.currentUser?.uid ?? '';
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Text(l10n.financeTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'רענן',
            onPressed: () async {
              final uid2 = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid2.isEmpty) return;
              try {
                final snap = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid2)
                    .get(const GetOptions(source: Source.server));
                final d = snap.data() ?? {};
                debugPrint('[Wallet refresh] '
                    'balance type=${d['balance']?.runtimeType} val=${d['balance']} | '
                    'pendingBalance type=${d['pendingBalance']?.runtimeType} val=${d['pendingBalance']}');
                // Reset animation so the count-up re-runs with the fresh value
                if (mounted) setState(() { _animStarted = false; });
              } catch (e) {
                debugPrint('[Wallet refresh] error: $e');
              }
            },
          ),
          const HintIcon(screenKey: 'wallet'),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, userSnap) {
          final userData =
              userSnap.data?.data() as Map<String, dynamic>? ?? {};
          // Robust cast: handles int, double, NaN, Infinity, and String values.
          // `as num?` throws if Firestore stored the value as a String.
          // `?? 0` does NOT catch NaN (NaN is not null) — isFinite is required.
          double safeDouble(String field, dynamic raw) {
            if (raw == null) return 0.0;
            if (raw is! num) {
              debugPrint('[Wallet] $field unexpected type '
                  '${raw.runtimeType} value="$raw" — parsing as string');
            }
            final d = (raw is num)
                ? raw.toDouble()
                : double.tryParse(raw.toString()) ?? 0.0;
            if (!d.isFinite) {
              debugPrint('[Wallet] $field non-finite ($d) clamped to 0');
            }
            return d.isFinite ? d : 0.0;
          }
          final balance = safeDouble('balance',        userData['balance']);
          final pending = safeDouble('pendingBalance', userData['pendingBalance']);
          final isProvider = userData['isProvider'] == true;

          // Kick off balance count-up for providers
          if (isProvider &&
              userSnap.connectionState != ConnectionState.waiting) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _startCountUp(balance));
          }

          return CustomScrollView(
            slivers: [
              if (userSnap.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[

                // ═══════════════════ PROVIDER VIEW ══════════════════════
                if (isProvider) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _buildProviderBalanceCard(
                          context, uid, balance, pending),
                    ),
                  ),
                  if (_chartLoaded) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _buildPayoutCycleCard(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                        child: _buildEarningsChart(context),
                      ),
                    ),
                  ],
                ],

                // ═══════════════════ CLIENT VIEW ════════════════════════
                if (!isProvider) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _buildPaymentMethodsPlaceholder(),
                    ),
                  ),
                  // ── Internal wallet balance summary ──────────────────
                  if (balance > 0 || balance < 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_rounded,
                                  size: 20, color: Color(0xFF6366F1)),
                              const SizedBox(width: 10),
                              Text('יתרת ארנק פנימי: ₪${balance.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],

                // ── Promo banners (both roles) ─────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: BannerCarousel(),
                  ),
                ),

                // ── Recent activity header (both roles) ────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        l10n.financeRecentActivity,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

                _buildTransactionSliver(uid),

                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROVIDER — glass balance card
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProviderBalanceCard(BuildContext context, String uid,
      double balance, double pending) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardMid, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _kCardEnd.withValues(alpha: 0.50),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // Glass orbs
            Positioned(
              top: -50, right: -40,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: -60, left: -30,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFA78BFA).withValues(alpha: 0.25),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_rounded,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 5),
                            Text(
                              l10n.financeTrustBadge,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.80),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildChipIcon(),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    l10n.financeAvailableBalance,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedBuilder(
                    animation: _countCtrl,
                    builder: (_, __) => Text(
                      '₪${_countAnim.value.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 46,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_top_rounded,
                                size: 11,
                                color: Colors.white.withValues(alpha: 0.65)),
                            const SizedBox(width: 4),
                            Text(
                              '₪${pending.toStringAsFixed(0)} ${l10n.financePending}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.financeMinWithdraw,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.38),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.50),
                            width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.10),
                      ),
                      icon: const Icon(Icons.savings_rounded, size: 17),
                      label: Text(l10n.financeWithdrawButton,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () =>
                          showWithdrawalModal(context, uid, balance),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }





  // ═══════════════════════════════════════════════════════════════════════════
  // CLIENT — Payment methods placeholder (Phase 2 — Israeli payment provider)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Stripe Connect was removed from the codebase. Saved-card management and
  // direct card payments will return when the new Israeli payment provider
  // is integrated. In the meantime, the internal-credits ledger continues to
  // power booking escrow via EscrowService.payQuote().
  Widget _buildPaymentMethodsPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardMid, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _kCardEnd.withValues(alpha: 0.40),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
              ),
            ),
            child: const Icon(
              Icons.construction_rounded,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'אמצעי תשלום בקרוב',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'אנו עוברים לספק תשלומים ישראלי. בינתיים, התשלום מתבצע מהארנק הפנימי שלך.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED — EMV chip icon
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChipIcon() {
    return Container(
      width: 42,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.45), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  width: 10,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  )),
              const SizedBox(width: 3),
              Container(
                  width: 10,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  )),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROVIDER — payout cycle mini-card
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPayoutCycleCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _payoutCycleItem(
              emoji: '🟡',
              label: 'מחזור השבוע',
              value: '₪${_pendingWeekly.toStringAsFixed(0)}',
              valueColor: const Color(0xFFFCD34D),
            ),
          ),
          Container(
              width: 1,
              height: 44,
              color: Colors.white.withValues(alpha: 0.15)),
          Expanded(
            child: _payoutCycleItem(
              emoji: '🟢',
              label: 'העברה הבאה',
              value: '₪${_finalizedTotal.toStringAsFixed(0)}',
              valueColor: const Color(0xFF6EE7B7),
            ),
          ),
          Container(
              width: 1,
              height: 44,
              color: Colors.white.withValues(alpha: 0.15)),
          Expanded(
            child: _payoutCycleItem(
              emoji: '📅',
              label: 'תאריך העברה',
              value: _nextPayoutDate != null
                  ? DateFormat('dd/MM', 'he').format(_nextPayoutDate!)
                  : '—',
              valueColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payoutCycleItem({
    required String emoji,
    required String label,
    required String value,
    required Color  valueColor,
  }) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.60),
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROVIDER — 7-day earnings chart
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEarningsChart(BuildContext context) {
    final maxY        = _dailyEarnings.isEmpty ? 0.0 : _dailyEarnings.reduce((a, b) => a > b ? a : b);
    final effectiveMax = maxY > 0 ? maxY * 1.25 : 100.0;
    final total       = _dailyEarnings.fold(0.0, (a, b) => a + b);
    final spots       = List.generate(
        7, (i) => FlSpot(i.toDouble(), _dailyEarnings[i]));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '₪${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _kChartLine,
                  ),
                ),
              ),
              const Text(
                'הכנסות 7 ימים אחרונים',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0, maxX: 6,
                minY: 0, maxY: effectiveMax,
                titlesData: FlTitlesData(
                  leftTitles:   const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles:  const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles:    const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final daysAgo = 6 - value.toInt();
                        final date = DateTime.now()
                            .subtract(Duration(days: daysAgo));
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('E', 'he').format(date).substring(0, 2),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: _kChartLine,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) =>
                          FlDotCirclePainter(
                        radius: spot.y > 0 ? 4 : 2.5,
                        color: spot.y > 0
                            ? _kChartLine
                            : const Color(0xFFE2E8F0),
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _kChartLine.withValues(alpha: 0.18),
                          _kChartLine.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A1A2E),
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '₪${s.y.toStringAsFixed(0)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED — transactions sliver (both roles)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTransactionSliver(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where(Filter.or(
            Filter('senderId',   isEqualTo: uid),
            Filter('receiverId', isEqualTo: uid),
            Filter('userId',     isEqualTo: uid),
          ))
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        final l10n = AppLocalizations.of(context);

        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: Center(
                child: Text(l10n.financeError(snap.error.toString()))),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = [...?snap.data?.docs];
        if (docs.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                  child: Text(l10n.financeNoTransactions,
                      style: const TextStyle(color: Colors.grey))),
            ),
          );
        }

        docs.sort((a, b) {
          final tA =
              (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final tB =
              (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (tA == null || tB == null) return 0;
          return tB.compareTo(tA);
        });

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildTransactionTile(context, docs[index], uid),
              childCount: docs.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionTile(
      BuildContext context, QueryDocumentSnapshot doc, String uid) {
    final l10n     = AppLocalizations.of(context);
    final tx       = doc.data() as Map<String, dynamic>;
    final isIncome = tx['receiverId'] == uid;
    final date     = (tx['timestamp'] as Timestamp?)?.toDate();
    final amount   = (tx['amount'] as num?)?.toDouble() ?? 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isIncome
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFFEF2F2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isIncome
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            size: 20,
            color: isIncome
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
          ),
        ),
        title: Text(
          isIncome
              ? l10n.financeReceivedFrom(tx['senderName'] ?? '')
              : l10n.financePaidTo(tx['receiverName'] ?? ''),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          date != null
              ? DateFormat('dd/MM/yyyy HH:mm', 'he').format(date)
              : l10n.financeProcessing,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        trailing: Text(
          '${isIncome ? '+' : '-'} ₪${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isIncome
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }
}
