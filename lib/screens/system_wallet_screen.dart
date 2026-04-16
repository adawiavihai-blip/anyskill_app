import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../constants.dart' show APP_CATEGORIES;
import '../utils/web_utils.dart';
import '../l10n/app_localizations.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF07070F);   // near-black canvas
const _kSurface   = Color(0xFF12121E);   // card surface
const _kSurface2  = Color(0xFF1C1C2E);   // elevated surface
const _kGold      = Color(0xFFFFD700);   // primary accent
const _kGreen     = Color(0xFF00E5A0);   // positive metric
const _kRed       = Color(0xFFFF4D6D);   // negative / alert
const _kBlue      = Color(0xFF4D9FFF);   // info

// ── Metrics snapshot (loaded once per session) ────────────────────────────────
class _Metrics {
  final double monthlyEarnings;
  final double prevWeekEarnings;
  final double thisWeekEarnings;
  final String topCategory;
  final double successRate;
  final int    completedCount;

  const _Metrics({
    required this.monthlyEarnings,
    required this.prevWeekEarnings,
    required this.thisWeekEarnings,
    required this.topCategory,
    required this.successRate,
    required this.completedCount,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
class SystemWalletScreen extends StatefulWidget {
  const SystemWalletScreen({super.key});

  @override
  State<SystemWalletScreen> createState() => _SystemWalletScreenState();
}

class _SystemWalletScreenState extends State<SystemWalletScreen> {
  final _feeCtrl    = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late final Future<_Metrics> _metricsFuture;

  static const double _kMonthlyGoal = 10000; // ₪ target — could be Firestore-driven

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
  }

  @override
  void dispose() {
    _feeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Metrics loader (parallel fetches) ────────────────────────────────────
  Future<_Metrics> _loadMetrics() async {
    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final weekAgo    = now.subtract(const Duration(days: 7));
    final twoWeeksAgo= now.subtract(const Duration(days: 14));

    // Parallel: monthly earnings, completed count, cancelled count
    final results = await Future.wait([
      db.collection('platform_earnings')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(monthStart))
          .limit(500).get(),
      db.collection('platform_earnings')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(weekAgo))
          .limit(200).get(),
      db.collection('platform_earnings')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(twoWeeksAgo))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .limit(200).get(),
      db.collection('jobs').where('status', isEqualTo: 'completed').count().get(),
      db.collection('jobs').where('status', isEqualTo: 'cancelled').count().get(),
    ]);

    final monthSnap   = results[0] as QuerySnapshot;
    final thisWkSnap  = results[1] as QuerySnapshot;
    final prevWkSnap  = results[2] as QuerySnapshot;
    final completedQ  = results[3] as AggregateQuerySnapshot;
    final cancelledQ  = results[4] as AggregateQuerySnapshot;

    double monthlyTotal  = 0;
    double thisWeekTotal = 0;
    double prevWeekTotal = 0;
    final catMap = <String, double>{};

    for (final doc in monthSnap.docs) {
      final d   = doc.data() as Map<String, dynamic>;
      final amt = (d['amount'] as num? ?? 0).toDouble();
      monthlyTotal += amt;
      final cat = (d['category'] ?? d['serviceType'] ?? '') as String;
      if (cat.isNotEmpty) catMap[cat] = (catMap[cat] ?? 0) + amt;
    }
    for (final doc in thisWkSnap.docs) {
      thisWeekTotal += ((doc.data() as Map<String, dynamic>)['amount'] as num? ?? 0).toDouble();
    }
    for (final doc in prevWkSnap.docs) {
      prevWeekTotal += ((doc.data() as Map<String, dynamic>)['amount'] as num? ?? 0).toDouble();
    }

    final topCat = catMap.isEmpty
        ? ''
        : (catMap.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    final completed = completedQ.count ?? 0;
    final cancelled  = cancelledQ.count ?? 0;
    final total      = completed + cancelled;

    return _Metrics(
      monthlyEarnings:  monthlyTotal,
      thisWeekEarnings: thisWeekTotal,
      prevWeekEarnings: prevWeekTotal,
      topCategory:      topCat,
      successRate:      total > 0 ? completed / total : 1.0,
      completedCount:   completed,
    );
  }

  // ── AI Briefing generator ─────────────────────────────────────────────────
  String _briefing(_Metrics m, double balance) {
    final lines = <String>[];

    final weekChange = m.prevWeekEarnings > 0
        ? ((m.thisWeekEarnings - m.prevWeekEarnings) / m.prevWeekEarnings * 100).round()
        : 0;
    if (weekChange > 0) {
      lines.add('הכנסות עלו $weekChange% השבוע 📈');
    } else if (weekChange < 0) {
      lines.add('ירידה של ${weekChange.abs()} % לעומת שבוע שעבר — בדוק שיווק 📉');
    }

    if (m.topCategory.isNotEmpty) {
      lines.add('ביקוש גבוה ב${m.topCategory} — שקול פרומו מהיר 🔥');
    }

    if (m.successRate >= 0.9) {
      lines.add('שיעור הצלחה ${(m.successRate * 100).round()}% — מעולה ✅');
    } else if (m.successRate < 0.7) {
      lines.add('שיעור ביטולים גבוה — בדוק עסקאות ⚠️');
    }

    if (balance >= 5000 && lines.isEmpty) {
      lines.add('יתרה בריאה · ${m.completedCount} עסקאות הושלמו בהצלחה 💰');
    }

    return lines.isEmpty
        ? 'ממתין לנתונים · הפלטפורמה עובדת כרגיל 🟢'
        : lines.join('  ·  ');
  }

  // ── Fee update ────────────────────────────────────────────────────────────
  void _updateFee() {
    final l10n = AppLocalizations.of(context);
    if (_feeCtrl.text.isEmpty) {
      _snack(l10n.systemWalletEnterNumber, _kRed);
      return;
    }
    try {
      final feeValue   = double.parse(_feeCtrl.text);
      final feePercent = feeValue / 100;
      FirebaseFirestore.instance
          .collection('admin').doc('admin')
          .collection('settings').doc('settings')
          .set({'feePercentage': feePercent, 'lastUpdated': FieldValue.serverTimestamp()},
               SetOptions(merge: true));
      _snack('עמלה עודכנה ל-${feeValue.toStringAsFixed(1)}%', _kGold);
      _feeCtrl.clear();
      FocusScope.of(context).unfocus();
      HapticFeedback.mediumImpact();
    } catch (_) {
      _snack(AppLocalizations.of(context).systemWalletInvalidNumber, _kRed);
    }
  }

  // ── CSV export ────────────────────────────────────────────────────────────
  Future<void> _exportReport() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('platform_earnings')
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();

      final fmt      = DateFormat('dd/MM/yyyy HH:mm', 'he');
      final now      = DateFormat('dd/MM/yyyy HH:mm', 'he').format(DateTime.now());
      final sb       = StringBuffer();
      sb.write('\uFEFF');  // UTF-8 BOM for Excel Hebrew
      sb.writeln('AnySkill — Financial Intelligence Report');
      sb.writeln('Generated: $now');
      sb.writeln('Total records: ${snapshot.docs.length}');
      sb.writeln('');
      sb.writeln('תאריך,תיאור,קטגוריה,עמלה (₪),מזהה עסקה');

      double grandTotal = 0;
      for (final doc in snapshot.docs) {
        final tx   = doc.data();
        final date = (tx['timestamp'] as Timestamp?)?.toDate();
        final dateStr = date != null ? fmt.format(date) : '';
        final desc = (tx['description'] ?? 'עסקה: ${tx['jobId'] ?? ''}')
            .toString().replaceAll(',', ' ');
        final cat  = (tx['category'] ?? tx['serviceType'] ?? '').toString();
        final amt  = (tx['amount'] as num? ?? 0).toDouble();
        grandTotal += amt;
        sb.writeln('$dateStr,$desc,$cat,${amt.toStringAsFixed(2)},${doc.id.substring(0, 8)}');
      }

      sb.writeln('');
      sb.writeln('סה"כ,,,"${grandTotal.toStringAsFixed(2)}"');

      triggerCsvDownload(
        sb.toString(),
        'anyskill_intelligence_${DateFormat('yyyyMMdd', 'he').format(DateTime.now())}.csv',
      );

      if (mounted) _snack('דוח יוצא — ${snapshot.docs.length} רשומות', _kGreen);
    } catch (e) {
      if (mounted) _snack('שגיאת ייצוא: $e', _kRed);
    }
  }

  // ── Smart Withdraw sheet ──────────────────────────────────────────────────
  void _showWithdrawSheet(double available) {
    final amtCtrl  = TextEditingController();
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _GlassCard(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24,
                      borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),
              const Text('משיכה חכמה', textAlign: TextAlign.center,
                  style: TextStyle(color: _kGold, fontSize: 20,
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text('זמין למשיכה: ₪${NumberFormat('#,###.##').format(available)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 24),
              _darkField(ctrl: amtCtrl, label: 'סכום למשיכה (₪)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 12),
              _darkField(ctrl: noteCtrl, label: 'הערה (אופציונלי)'),
              const SizedBox(height: 24),
              _GoldButton(
                label: 'אשר משיכה',
                icon: Icons.arrow_upward_rounded,
                onTap: () async {
                  final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
                  if (amt <= 0 || amt > available) {
                    _snack('סכום לא תקני', _kRed);
                    return;
                  }
                  await FirebaseFirestore.instance.collection('withdrawals').add({
                    'type':        'admin_withdrawal',
                    'amount':      amt,
                    'note':        noteCtrl.text.trim(),
                    'status':      'pending',
                    'requestedAt': FieldValue.serverTimestamp(),
                  });
                  HapticFeedback.heavyImpact();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('בקשת משיכה נשלחה ✓', _kGold);
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() { amtCtrl.dispose(); noteCtrl.dispose(); });
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.black,
          fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          // All live data hangs off a single settings StreamBuilder at the top
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('admin').doc('admin')
                .collection('settings').doc('settings')
                .snapshots(),
            builder: (context, settingsSnap) {
              final settings  = settingsSnap.data?.data() as Map<String, dynamic>? ?? {};
              final balance   = (settings['totalPlatformBalance'] as num? ?? 0).toDouble();
              final feePct    = (settings['feePercentage'] as num? ?? 0.10).toDouble();

              return SliverMainAxisGroup(slivers: [
                // ── AI Briefing ──────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildBriefing(balance)),

                // ── The Vault ────────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildVault(balance, feePct)),

                // ── Growth Engine ────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildGrowthEngine()),

                // ── Transaction Feed ─────────────────────────────────────────
                SliverToBoxAdapter(child: _buildFeedHeader()),
                _buildTransactionFeed(),

                // ── Fee Panel + Export ────────────────────────────────────────
                SliverToBoxAdapter(child: _buildFeePanel(feePct)),
                SliverToBoxAdapter(child: _buildExportRow()),
                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ]);
            },
          ),
        ],
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      backgroundColor: _kSurface,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                  color: _kGreen, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('AnySkill Vault',
              style: TextStyle(color: _kGold, fontWeight: FontWeight.bold,
                  letterSpacing: 1.2, fontSize: 18)),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.ios_share_rounded, color: _kGold),
          onPressed: _exportReport,
          tooltip: 'ייצוא דוח',
        ),
      ],
    );
  }

  // ── AI Briefing ───────────────────────────────────────────────────────────
  Widget _buildBriefing(double balance) {
    return FutureBuilder<_Metrics>(
      future: _metricsFuture,
      builder: (context, snap) {
        final text = snap.hasData
            ? _briefing(snap.data!, balance)
            : 'מנתח נתונים...';
        return _GlassCard(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: _kGold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white70,
                        fontSize: 13, height: 1.4)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── The Vault ─────────────────────────────────────────────────────────────
  Widget _buildVault(double balance, double feePct) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', whereIn: ['paid_escrow', 'expert_completed'])
          .limit(500)
          .snapshots(),
      builder: (context, jobsSnap) {
        double pendingFees = 0;
        int pendingCount   = 0;
        if (jobsSnap.hasData) {
          for (final doc in jobsSnap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final amt = (d['totalAmount'] ?? d['totalPaidByCustomer'] ?? 0).toDouble();
            pendingFees += amt * feePct;
            pendingCount++;
          }
        }
        final transitRatio = balance > 0 ? (pendingFees / (balance + pendingFees)).clamp(0.0, 1.0) : 0.0;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          height: 210,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A1A), Color(0xFF0D0D0D), Color(0xFF1A1205)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _kGold.withValues(alpha: 0.25), width: 1),
            boxShadow: [
              BoxShadow(color: _kGold.withValues(alpha: 0.12),
                  blurRadius: 32, offset: const Offset(0, 8)),
            ],
          ),
          child: Stack(
            children: [
              // Glow orb top-left
              Positioned(top: -30, left: -30,
                child: Container(width: 120, height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: _kGold.withValues(alpha: 0.05)))),
              // Chip icon
              Positioned(top: 20, right: 24,
                child: Row(
                  children: [
                    const Icon(Icons.diamond_outlined, color: _kGold, size: 18),
                    const SizedBox(width: 6),
                    Text('AnySkill Vault',
                        style: TextStyle(color: _kGold.withValues(alpha: 0.8),
                            fontSize: 12, fontWeight: FontWeight.w600,
                            letterSpacing: 1.5)),
                  ],
                ),
              ),
              // Transit ring
              Positioned(bottom: 20, left: 24,
                child: SizedBox(
                  width: 70, height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(70, 70),
                        painter: _RingPainter(
                            progress: transitRatio, color: _kBlue),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(transitRatio * 100).round()}%',
                              style: const TextStyle(color: _kBlue,
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const Text('transit',
                              style: TextStyle(color: Colors.white38,
                                  fontSize: 8)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('יתרה חיה',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    // Count-up animation
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: balance),
                      duration: const Duration(milliseconds: 2200),
                      curve: Curves.easeOutCubic,
                      onEnd: () {
                        if (balance >= 10000) HapticFeedback.heavyImpact();
                      },
                      builder: (_, value, __) => Text(
                        '₪${NumberFormat('#,###.##').format(value)}',
                        style: const TextStyle(color: _kGold, fontSize: 38,
                            fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('עסקאות ממתינות ($pendingCount)',
                                style: const TextStyle(color: Colors.white38,
                                    fontSize: 10)),
                            Text(
                              '₪${NumberFormat('#,###.##').format(pendingFees)}',
                              style: const TextStyle(color: _kBlue,
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _showWithdrawSheet(balance),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              color: _kGold,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward_rounded,
                                    color: Colors.black, size: 16),
                                SizedBox(width: 5),
                                Text('משיכה חכמה',
                                    style: TextStyle(color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Growth Engine ─────────────────────────────────────────────────────────
  Widget _buildGrowthEngine() {
    return FutureBuilder<_Metrics>(
      future: _metricsFuture,
      builder: (context, snap) {
        final m = snap.data;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(child: _GrowthTile(
                icon: Icons.track_changes_rounded,
                color: _kGold,
                label: 'יעד חודשי',
                sublabel: m == null
                    ? '...'
                    : '₪${NumberFormat('#,###').format(m.monthlyEarnings)} / ₪${NumberFormat('#,###').format(_kMonthlyGoal)}',
                progress: m == null
                    ? null
                    : (m.monthlyEarnings / _kMonthlyGoal).clamp(0.0, 1.0),
                progressColor: _kGold,
              )),
              const SizedBox(width: 10),
              Expanded(child: _GrowthTile(
                icon: Icons.local_fire_department_rounded,
                color: _kRed,
                label: 'Market Heat',
                sublabel: m?.topCategory.isEmpty ?? true
                    ? 'טוען...'
                    : m!.topCategory,
                progress: null,
                progressColor: _kRed,
                badge: m?.topCategory.isEmpty ?? true ? null : '🔥 HOT',
              )),
              const SizedBox(width: 10),
              Expanded(child: _GrowthTile(
                icon: Icons.health_and_safety_rounded,
                color: _kGreen,
                label: 'Retention',
                sublabel: m == null
                    ? '...'
                    : '${(( m.successRate) * 100).round()}% הצלחה',
                progress: m?.successRate,
                progressColor: m == null
                    ? _kGreen
                    : (m.successRate >= 0.8 ? _kGreen : _kRed),
              )),
            ],
          ),
        );
      },
    );
  }

  // ── Transaction feed header ───────────────────────────────────────────────
  Widget _buildFeedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Row(
        children: [
          const Expanded(
            child: Text('Transaction Feed',
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: _kSurface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: _searchCtrl,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'חיפוש...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Colors.white38, size: 18),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Transaction feed ──────────────────────────────────────────────────────
  Widget _buildTransactionFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('platform_earnings')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                      child: CircularProgressIndicator(color: _kGold))));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: _GlassCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(40),
              child: const Column(children: [
                Icon(Icons.receipt_long_rounded,
                    color: Colors.white24, size: 48),
                SizedBox(height: 12),
                Text('אין עסקאות עדיין',
                    style: TextStyle(color: Colors.white38, fontSize: 15)),
              ]),
            ),
          );
        }

        final docs = snap.data!.docs.where((doc) {
          if (_searchQuery.isEmpty) return true;
          final d    = doc.data() as Map<String, dynamic>;
          final desc = (d['description'] ?? '').toString().toLowerCase();
          final cat  = (d['category'] ?? d['serviceType'] ?? '').toString().toLowerCase();
          return desc.contains(_searchQuery) || cat.contains(_searchQuery);
        }).toList();

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _TxCard(doc: docs[i], onResolve: _resolveTransaction),
            childCount: docs.length,
          ),
        );
      },
    );
  }

  Future<void> _resolveTransaction(String docId) async {
    await FirebaseFirestore.instance
        .collection('platform_earnings')
        .doc(docId)
        .set({'reviewed': true, 'reviewedAt': FieldValue.serverTimestamp()},
             SetOptions(merge: true));
    HapticFeedback.lightImpact();
    if (mounted) _snack('עסקה סומנה כנבדקה ✓', _kGreen);
  }

  // ── Fee control panel ─────────────────────────────────────────────────────
  Widget _buildFeePanel(double currentFee) {
    return _GlassCard(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(children: [
            const Icon(Icons.tune_rounded, color: _kGold, size: 18),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context).systemWalletFeePanel,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Text('נוכחי: ${(currentFee * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    color: _kSurface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12)),
                child: TextField(
                  controller: _feeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                      hintText: '10',
                      hintStyle: TextStyle(color: Colors.white38),
                      suffixText: '%',
                      suffixStyle: TextStyle(color: _kGold),
                      border: InputBorder.none),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _GoldButton(
              label: AppLocalizations.of(context).systemWalletUpdateFee,
              icon: Icons.check_rounded,
              onTap: _updateFee,
              compact: true,
            ),
          ]),
        ],
      ),
    );
  }

  // ── Export row ────────────────────────────────────────────────────────────
  Widget _buildExportRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _GoldButton(
        label: 'ייצוא דוח Financial Intelligence',
        icon: Icons.download_rounded,
        onTap: _exportReport,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction card widget
// ─────────────────────────────────────────────────────────────────────────────
class _TxCard extends StatelessWidget {
  const _TxCard({required this.doc, required this.onResolve});
  final QueryDocumentSnapshot        doc;
  final Future<void> Function(String) onResolve;

  IconData _catIcon(String cat) {
    for (final c in APP_CATEGORIES) {
      if ((c['name'] as String).contains(cat) || cat.contains(c['name'] as String)) {
        return c['icon'] as IconData;
      }
    }
    return Icons.work_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final tx      = doc.data() as Map<String, dynamic>;
    final date    = (tx['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final amount  = (tx['amount'] as num? ?? 0).toDouble();
    final desc    = tx['description'] as String? ??
        'עסקה: ${(tx['jobId'] as String? ?? '').substring(0, math.min(8, (tx['jobId'] as String? ?? '').length))}';
    final cat     = (tx['category'] ?? tx['serviceType'] ?? '') as String;
    final reviewed = tx['reviewed'] == true;
    final flagged  = !reviewed && amount > 500;

    // Derive initials from description (e.g. "אביחי ➔ סיגלית" → "א")
    final initial  = desc.isNotEmpty ? desc[0] : '?';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: flagged
              ? _kGold.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _kGold.withValues(alpha: 0.18),
              child: Text(initial,
                  style: const TextStyle(color: _kGold,
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Positioned(
              bottom: -2, right: -2,
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                    color: _kSurface2, shape: BoxShape.circle,
                    border: Border.all(color: _kSurface, width: 1.5)),
                child: Icon(_catIcon(cat), size: 10, color: _kBlue),
              ),
            ),
          ],
        ),
        title: Text(desc,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          DateFormat('dd/MM/yy · HH:mm', 'he').format(date),
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flagged)
              GestureDetector(
                onTap: () => onResolve(doc.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kGold.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Resolve',
                      style: TextStyle(color: _kGold,
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+₪${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: _kGreen,
                        fontWeight: FontWeight.bold, fontSize: 15)),
                if (reviewed)
                  const Text('✓ נבדק',
                      style: TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Growth Engine tile
// ─────────────────────────────────────────────────────────────────────────────
class _GrowthTile extends StatelessWidget {
  const _GrowthTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
    required this.progress,
    required this.progressColor,
    this.badge,
  });
  final IconData icon;
  final Color    color;
  final String   label;
  final String   sublabel;
  final double?  progress;
  final Color    progressColor;
  final String?  badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge!,
                      style: TextStyle(color: color, fontSize: 9,
                          fontWeight: FontWeight.bold)),
                )
              else
                const SizedBox.shrink(),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54,
                  fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 3),
          Text(sublabel,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12,
                  fontWeight: FontWeight.bold, height: 1.3)),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared glass card
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.margin  = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget       child;
  final EdgeInsets   margin;
  final EdgeInsets   padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gold CTA button
// ─────────────────────────────────────────────────────────────────────────────
class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });
  final String       label;
  final IconData     icon;
  final VoidCallback onTap;
  final bool         compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: compact ? 44 : 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFB8960C), _kGold, Color(0xFFFFF0A0)],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: _kGold.withValues(alpha: 0.3),
              blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(color: Colors.black,
                    fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transit ring painter
// ─────────────────────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});
  final double progress;
  final Color  color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 5;

    canvas.drawCircle(center, radius, Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dark input field helper
// ─────────────────────────────────────────────────────────────────────────────
Widget _darkField({
  required TextEditingController ctrl,
  required String label,
  TextInputType keyboardType = TextInputType.text,
}) {
  return Container(
    decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12)),
    child: TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
  );
}
