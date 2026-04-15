import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_users_provider.dart';

/// Self-contained Insights & Analytics tab extracted from AdminScreen.
/// Owns all stream subscriptions, loaders, and state for the insights view.
class AdminInsightsTab extends ConsumerStatefulWidget {
  const AdminInsightsTab({super.key});

  @override
  ConsumerState<AdminInsightsTab> createState() => _AdminInsightsTabState();
}

class _AdminInsightsTabState extends ConsumerState<AdminInsightsTab> {
  // ── Insights tab — real-time aggregated state ──────────────────────────────
  double _insGmv       = 0;
  double _insNetRev    = 0;
  double _insEscrow    = 0;
  int    _insTxCount   = 0;
  int    _insUnanswered = 0;
  List<Map<String, dynamic>> _insBanners = [];

  // Per-metric "first snapshot received" flags — prevents showing 0 before data arrives
  bool _insGmvLoaded      = false;
  bool _insNetRevLoaded   = false;
  bool _insEscrowLoaded   = false;
  bool _insTxLoaded       = false;
  bool _insUnanswLoaded   = false;
  bool _insBannersLoaded  = false;

  StreamSubscription<QuerySnapshot>? _insCompletedSub;
  StreamSubscription<QuerySnapshot>? _insEarnSub;
  StreamSubscription<QuerySnapshot>? _insEscrowSub;
  StreamSubscription<QuerySnapshot>? _insTxSub;
  StreamSubscription<QuerySnapshot>? _insUnanswSub;
  StreamSubscription<QuerySnapshot>? _insBannersSub;

  // ── Pulse (urgency) analytics ───────────────────────────────────────────────
  int    _pulseUrgentTotal  = 0;
  int    _pulseUrgentFilled = 0;
  double _pulseRevenue      = 0;
  double _pulseAvgHoursUrgent  = 0;
  double _pulseAvgHoursRegular = 0;
  bool   _pulseLoaded = false;

  // ── Peak hours demand graph ─────────────────────────────────────────────────
  List<int> _hourReqs = List.filled(24, 0);
  List<int> _hourJobs = List.filled(24, 0);
  String    _peakReco  = '';
  bool      _peakLoaded = false;

  // ── DAU (Daily Active Users) ────────────────────────────────────────────────
  int  _insDau       = 0;
  bool _insDauLoaded = false;
  StreamSubscription<QuerySnapshot>? _insDauSub;

  @override
  void initState() {
    super.initState();
    _setupInsightsStreams();
  }

  @override
  void dispose() {
    _insCompletedSub?.cancel();
    _insEarnSub?.cancel();
    _insEscrowSub?.cancel();
    _insTxSub?.cancel();
    _insUnanswSub?.cancel();
    _insBannersSub?.cancel();
    _insDauSub?.cancel();
    super.dispose();
  }

  // ── Insights: set up (or re-set up) all real-time stream subscriptions ───────
  void _setupInsightsStreams() {
    // Cancel existing subscriptions before re-subscribing (called on force-refresh too)
    _insCompletedSub?.cancel();
    _insEarnSub?.cancel();
    _insEscrowSub?.cancel();
    _insTxSub?.cancel();
    _insUnanswSub?.cancel();
    _insBannersSub?.cancel();
    _insDauSub?.cancel();

    // Reset loaded flags so UI shows a brief spinner while first snapshots arrive
    if (mounted) {
      setState(() {
        _insGmvLoaded     = false;
        _insNetRevLoaded  = false;
        _insEscrowLoaded  = false;
        _insTxLoaded      = false;
        _insUnanswLoaded  = false;
        _insBannersLoaded = false;
        _insDauLoaded     = false;
        _pulseLoaded      = false;
        _peakLoaded       = false;
      });
    }

    // One-time async loaders for pulse analytics + peak hours
    _loadPulseAnalytics();
    _loadPeakHours();

    // 1. GMV — sum totalAmount of completed jobs (last 500 for performance)
    _insCompletedSub = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'completed')
        .limit(500)
        .snapshots()
        .listen((snap) {
      double gmv = 0;
      for (final d in snap.docs) {
        gmv += ((d.data())['totalAmount'] as num? ?? 0).toDouble();
      }
      if (mounted) setState(() { _insGmv = gmv; _insGmvLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insGmv = 0; _insGmvLoaded = true; });
    });

    // 2. Net revenue — sum amount from platform_earnings
    _insEarnSub = FirebaseFirestore.instance
        .collection('platform_earnings')
        .limit(500)
        .snapshots()
        .listen((snap) {
      double rev = 0;
      for (final d in snap.docs) {
        rev += ((d.data())['amount'] as num? ?? 0).toDouble();
      }
      if (mounted) setState(() { _insNetRev = rev; _insNetRevLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insNetRev = 0; _insNetRevLoaded = true; });
    });

    // 3. Escrow held — sum totalAmount of paid_escrow jobs
    _insEscrowSub = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'paid_escrow')
        .limit(500)
        .snapshots()
        .listen((snap) {
      double esc = 0;
      for (final d in snap.docs) {
        esc += ((d.data())['totalAmount'] as num? ?? 0).toDouble();
      }
      if (mounted) setState(() { _insEscrow = esc; _insEscrowLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insEscrow = 0; _insEscrowLoaded = true; });
    });

    // 4. Transaction count — total records in transactions collection
    _insTxSub = FirebaseFirestore.instance
        .collection('transactions')
        .limit(500)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() { _insTxCount = snap.docs.length; _insTxLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insTxCount = 0; _insTxLoaded = true; });
    });

    // 5. Unanswered opportunities — open job_requests with no provider interest yet
    _insUnanswSub = FirebaseFirestore.instance
        .collection('job_requests')
        .where('status', isEqualTo: 'open')
        .where('interestedCount', isEqualTo: 0)
        .limit(200)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() { _insUnanswered = snap.docs.length; _insUnanswLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insUnanswered = 0; _insUnanswLoaded = true; });
    });

    // 6. Banner analytics — click counts per banner (sorted desc)
    _insBannersSub = FirebaseFirestore.instance
        .collection('banners')
        .limit(50)
        .snapshots()
        .listen((snap) {
      final banners = snap.docs
          .map((d) => {
                'title':  (d.data())['title']  as String? ?? 'ללא שם',
                'clicks': ((d.data())['clicks'] as num? ?? 0).toInt(),
              })
          .toList()
        ..sort((a, b) => (b['clicks'] as int).compareTo(a['clicks'] as int));
      if (mounted) setState(() { _insBanners = banners; _insBannersLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insBanners = []; _insBannersLoaded = true; });
    });

    // 7. DAU — users active today (lastOnlineAt or lastActive >= today 00:00)
    final todayStart = DateTime.now();
    final dayStart = DateTime(todayStart.year, todayStart.month, todayStart.day);
    _insDauSub = FirebaseFirestore.instance
        .collection('users')
        .where('lastOnlineAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .limit(200)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() { _insDau = snap.docs.length; _insDauLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insDau = 0; _insDauLoaded = true; });
    });
  }

  // ── Pulse analytics loader ─────────────────────────────────────────────────
  Future<void> _loadPulseAnalytics() async {
    try {
      final db = FirebaseFirestore.instance;

      // Fetch all job_requests — filter client-side to avoid composite index
      final reqSnap = await db.collection('job_requests').limit(500).get();

      int urgentTotal  = 0;
      int urgentFilled = 0;
      double urgentTimeSum   = 0;
      int    urgentTimeCount = 0;
      double regularTimeSum   = 0;
      int    regularTimeCount = 0;

      for (final d in reqSnap.docs) {
        final data    = d.data();
        final isUrg   = data['isUrgent'] == true;
        final isClosed = (data['status'] as String?) == 'closed';
        final created  = (data['createdAt'] as Timestamp?)?.toDate();
        final updated  = (data['updatedAt'] as Timestamp?)?.toDate();

        if (isUrg) {
          urgentTotal++;
          if (isClosed) {
            urgentFilled++;
            if (created != null && updated != null) {
              urgentTimeSum += updated.difference(created).inMinutes.toDouble();
              urgentTimeCount++;
            }
          }
        } else if (isClosed && created != null && updated != null) {
          regularTimeSum += updated.difference(created).inMinutes.toDouble();
          regularTimeCount++;
        }
      }

      // Revenue from urgent-tagged completed jobs
      double revenue = 0;
      final urgJobSnap = await db
          .collection('jobs')
          .where('status', isEqualTo: 'completed')
          .where('isUrgent', isEqualTo: true)
          .limit(500)
          .get();
      for (final d in urgJobSnap.docs) {
        revenue += ((d.data())['totalAmount'] as num? ?? 0).toDouble();
      }

      if (mounted) {
        setState(() {
          _pulseUrgentTotal     = urgentTotal;
          _pulseUrgentFilled    = urgentFilled;
          _pulseRevenue         = revenue;
          _pulseAvgHoursUrgent  = urgentTimeCount  > 0 ? urgentTimeSum  / urgentTimeCount  / 60 : 0;
          _pulseAvgHoursRegular = regularTimeCount > 0 ? regularTimeSum / regularTimeCount / 60 : 0;
          _pulseLoaded          = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _pulseLoaded = true);
    }
  }

  // ── Peak hours loader ──────────────────────────────────────────────────────
  Future<void> _loadPeakHours() async {
    try {
      final db     = FirebaseFirestore.instance;
      final cutoff = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 30)));

      final results = await Future.wait([
        db.collection('job_requests')
            .where('createdAt', isGreaterThan: cutoff)
            .limit(1000)
            .get(),
        db.collection('jobs')
            .where('status', isEqualTo: 'completed')
            .where('createdAt', isGreaterThan: cutoff)
            .limit(1000)
            .get(),
      ]);

      final List<int> hourReqs = List.filled(24, 0);
      final List<int> hourJobs = List.filled(24, 0);
      final List<int> dayReqs  = List.filled(7, 0); // Mon=0 ... Sun=6

      for (final d in results[0].docs) {
        final ts = ((d.data())['createdAt'] as Timestamp?)?.toDate();
        if (ts != null) {
          hourReqs[ts.hour]++;
          dayReqs[ts.weekday - 1]++;
        }
      }
      for (final d in results[1].docs) {
        final ts = ((d.data())['createdAt'] as Timestamp?)?.toDate();
        if (ts != null) hourJobs[ts.hour]++;
      }

      // 3-hour rolling window with the highest demand gap
      int peakStart = 17;
      int maxGap    = -9999;
      for (int h = 0; h < 22; h++) {
        final gap = (hourReqs[h] + hourReqs[h + 1] + hourReqs[h + 2]) -
            (hourJobs[h] + hourJobs[h + 1] + hourJobs[h + 2]);
        if (gap > maxGap) {
          maxGap    = gap;
          peakStart = h;
        }
      }

      // Most active day of week
      int peakDayIdx = 0;
      for (int i = 1; i < 7; i++) {
        if (dayReqs[i] > dayReqs[peakDayIdx]) peakDayIdx = i;
      }
      const dayNames = ['שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
      final reco = maxGap <= 0
          ? 'ביקוש ואספקה מאוזנים — אין צורך ב-Auto-Pulse כרגע'
          : 'המלצה: הפעל Auto-Pulse ביום ${dayNames[peakDayIdx]} בין $peakStart:00-${peakStart + 3}:00 למקסום הכנסות';

      if (mounted) {
        setState(() {
          _hourReqs   = hourReqs;
          _hourJobs   = hourJobs;
          _peakReco   = reco;
          _peakLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hourReqs   = List.filled(24, 0);
          _hourJobs   = List.filled(24, 0);
          _peakLoaded = true;
        });
      }
    }
  }

  // ── Number formatter ────────────────────────────────────────────────────────
  static String _fmtNum(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    // DAU is computed by _insDauSub stream subscription in _setupInsightsStreams
    final dau = _insDau;

    // All 4 financial metrics must have loaded before showing numbers
    final finLoaded = _insGmvLoaded && _insNetRevLoaded && _insEscrowLoaded && _insTxLoaded;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("תובנות ואנליטיקס",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.blueAccent),
                onPressed: _setupInsightsStreams,
                tooltip: "כפה רענון — סגור וחדש את כל ה-Listeners",
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Financial Overview (real-time) ────────────────────────────
          _monoCard(
            icon: Icons.account_balance_wallet_rounded,
            color: Colors.green,
            title: "סקירה פיננסית",
            child: !finLoaded
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _insightsMiniCard(
                              'GMV סה"כ', '₪${_fmtNum(_insGmv)}', Colors.green)),
                          const SizedBox(width: 10),
                          Expanded(child: _insightsMiniCard(
                              'הכנסות נטו', '₪${_fmtNum(_insNetRev)}', Colors.teal)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _insightsMiniCard(
                              'ב-Escrow', '₪${_fmtNum(_insEscrow)}', Colors.orange)),
                          const SizedBox(width: 10),
                          Expanded(child: _insightsMiniCard(
                              'עסקאות', _fmtNum(_insTxCount.toDouble()), Colors.blue)),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // ── User Activity (DAU from own stream, unanswered from own stream) ──
          _monoCard(
            icon: Icons.people_alt_rounded,
            color: Colors.purple,
            title: "פעילות משתמשים",
            child: Row(
              children: [
                Expanded(child: _insightsMiniCard(
                    'פעילים היום (DAU)',
                    _insDauLoaded ? dau.toString() : '...',
                    Colors.purple)),
                const SizedBox(width: 10),
                Expanded(child: _insightsMiniCard(
                    'בקשות ללא מענה',
                    _insUnanswLoaded ? _insUnanswered.toString() : '...',
                    _insUnanswered > 5 ? Colors.red : Colors.green)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Urgency & Pulse Analytics ─────────────────────────────────
          _buildPulseAnalyticsCard(),
          const SizedBox(height: 16),

          // ── Peak Hours & Demand Graph ──────────────────────────────────
          _buildPeakHoursCard(),
          const SizedBox(height: 16),

          // ── Banner Analytics (real-time click counts) ─────────────────
          _monoCard(
            icon: Icons.bar_chart_rounded,
            color: Colors.indigo,
            title: "אנליטיקס באנרים",
            child: !_insBannersLoaded
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _insBanners.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("אין באנרים עדיין",
                            style: TextStyle(color: Colors.grey)),
                      )
                    : Column(
                        children: _insBanners.map((b) {
                          final clicks    = (b['clicks']   as int? ?? 0);
                          final firstClicks =
                              (_insBanners.first['clicks'] as int? ?? 0);
                          final maxClicks = firstClicks < 1 ? 1 : firstClicks;
                          final ratio = clicks / maxClicks;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('$clicks קליקים',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                    Text(b['title'] as String,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 8,
                                    backgroundColor:
                                        Colors.indigo.withValues(alpha: 0.1),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.indigo),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
          ),
          const SizedBox(height: 16),

          // ── Top Rated Providers (from loaded user pages) ──────────────
          _monoCard(
            icon: Icons.star_rounded,
            color: const Color(0xFFF59E0B),
            title: "ספקים מובילים",
            child: Builder(builder: (context) {
              final usersState = ref.watch(adminUsersNotifierProvider);
              final providers = usersState.users
                  .map((d) => d.data())
                  .where((d) =>
                      d['isProvider'] == true &&
                      (d['reviewsCount'] as num? ?? 0) > 0)
                  .toList()
                ..sort((a, b) => ((b['rating'] as num? ?? 0)
                    .compareTo(a['rating'] as num? ?? 0)));

              final top = providers.take(5).toList();
              if (top.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("אין ספקים עם ביקורות עדיין",
                      style: TextStyle(color: Colors.grey)),
                );
              }

              return Column(
                children: top.map((d) {
                  // Support both 'name' (used by most screens) and 'fullName'
                  final name = (d['name'] ?? d['fullName'] ?? 'ספק') as String;
                  final rating  = (d['rating']       as num? ?? 0).toDouble();
                  final reviews = (d['reviewsCount'] as num? ?? 0).toInt();
                  final photo   = d['profileImage']  as String?;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Color(0xFFF59E0B), size: 16),
                            const SizedBox(width: 4),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(width: 4),
                            Text('($reviews)',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        Text(name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: (photo != null && photo.isNotEmpty)
                              ? NetworkImage(photo)
                              : null,
                          child: (photo == null || photo.isEmpty)
                              ? Text(
                                  name.isNotEmpty ? name[0] : '?',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            }),
          ),
          const SizedBox(height: 16),

          // ── Response Time Placeholder ─────────────────────────────────
          _monoCard(
            icon: Icons.timer_outlined,
            color: Colors.blueGrey,
            title: "זמן תגובה ממוצע",
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "יהיה זמין בקרוב",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Data Integrity Tools ──────────────────────────────────────────
          _monoCard(
            icon: Icons.health_and_safety_rounded,
            color: Colors.teal,
            title: "שלמות נתונים",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "סנכרן מספרי טלפון חסרים מ-Firebase Auth לאוסף המשתמשים.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 10),
                const _SyncPhonesButton(),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Urgency & Pulse Analytics Card ───────────────────────────────────────
  Widget _buildPulseAnalyticsCard() {
    const amber  = Color(0xFFF59E0B);
    const orange = Color(0xFFEA580C);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C1917), Color(0xFF292524)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: amber.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt_rounded, color: amber, size: 20),
              ),
              const Text(
                'ניתוח Urgency & Pulse',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (!_pulseLoaded) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(color: amber),
              ),
            ),
          ] else ...[
            // ── 3 metric tiles ────────────────────────────────────────────
            Row(children: [
              Expanded(child: _pulseTile(
                icon: Icons.timer_rounded,
                label: 'מהירות המרה',
                value: _pulseAvgHoursUrgent < 0.1 && _pulseAvgHoursRegular < 0.1
                    ? 'אין נתונים'
                    : '${_pulseAvgHoursUrgent.toStringAsFixed(1)}h / ${_pulseAvgHoursRegular.toStringAsFixed(1)}h',
                sub: 'Pulse vs. רגיל',
                valueColor: amber,
              )),
              const SizedBox(width: 10),
              Expanded(child: _pulseTile(
                icon: Icons.check_circle_rounded,
                label: 'אחוז מימוש',
                value: _pulseUrgentTotal == 0
                    ? '—'
                    : '${(_pulseUrgentFilled / _pulseUrgentTotal * 100).toStringAsFixed(0)}%',
                sub: '$_pulseUrgentFilled / $_pulseUrgentTotal בקשות',
                valueColor: _pulseUrgentTotal > 0 &&
                        _pulseUrgentFilled / _pulseUrgentTotal >= 0.6
                    ? const Color(0xFF22C55E)
                    : orange,
              )),
            ]),
            const SizedBox(height: 10),

            // ── Economic impact full-width tile ───────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: amber.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_money_rounded, color: amber, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₪${_fmtNum(_pulseRevenue)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: amber),
                      ),
                      const Text('הכנסות כלכליות מ-Pulse',
                          style: TextStyle(fontSize: 11, color: Colors.white54)),
                    ],
                  ),
                  const Spacer(),
                  // Conversion speed bar
                  if (_pulseAvgHoursUrgent > 0 && _pulseAvgHoursRegular > 0) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _speedBar('Pulse', _pulseAvgHoursUrgent, amber,
                            _pulseAvgHoursRegular),
                        const SizedBox(height: 4),
                        _speedBar('רגיל', _pulseAvgHoursRegular,
                            Colors.white24, _pulseAvgHoursRegular),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Peak Hours & Demand Card ──────────────────────────────────────────────
  Widget _buildPeakHoursCard() {
    const amber  = Color(0xFFF59E0B);
    const blue   = Color(0xFF3B82F6);

    final maxVal = () {
      int m = 1;
      for (final v in [..._hourReqs, ..._hourJobs]) {
        if (v > m) m = v;
      }
      return m.toDouble();
    }();

    final reqSpots  = List.generate(24, (h) => FlSpot(h.toDouble(), _hourReqs[h].toDouble()));
    final jobSpots  = List.generate(24, (h) => FlSpot(h.toDouble(), _hourJobs[h].toDouble()));

    return _monoCard(
      icon: Icons.query_stats_rounded,
      color: amber,
      title: 'שעות שיא וביקוש',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Line chart ────────────────────────────────────────────────
          if (!_peakLoaded)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(color: amber)),
            )
          else
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minX: 0, maxX: 23,
                  minY: 0, maxY: maxVal * 1.25,
                  lineBarsData: [
                    // ── Requests line (amber) ──
                    LineChartBarData(
                      spots: reqSpots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: amber,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                          radius: 3,
                          color: amber,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            amber.withValues(alpha: 0.20),
                            amber.withValues(alpha: 0.02),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    // ── Completions line (blue) ──
                    LineChartBarData(
                      spots: jobSpots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: blue,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                          radius: 2.5,
                          color: blue,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  // Shade the gap between requests and completions
                  betweenBarsData: [
                    BetweenBarsData(
                      fromIndex: 0,
                      toIndex: 1,
                      color: amber.withValues(alpha: 0.12),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxVal / 3).ceilToDouble().clamp(1, 999),
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 4,
                        reservedSize: 20,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}h',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        (maxVal / 3).ceilToDouble().clamp(1, 999),
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.10),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),

          const SizedBox(height: 10),

          // ── Legend ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _chartLegendDot(color: blue,  label: 'הזמנות הושלמו'),
              const SizedBox(width: 14),
              _chartLegendDot(color: amber, label: 'בקשות נפתחו'),
            ],
          ),

          const SizedBox(height: 14),

          // ── Recommendation box ────────────────────────────────────────
          if (_peakLoaded && _peakReco.isNotEmpty)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: amber.withValues(alpha: 0.30)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_rounded,
                      color: amber, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _peakReco,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  static Widget _monoCard({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  static Widget _insightsMiniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.right),
        ],
      ),
    );
  }

  static Widget _pulseTile({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(icon, size: 16, color: valueColor),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: valueColor)),
          Text(sub,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
              textAlign: TextAlign.right),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
              textAlign: TextAlign.right),
        ],
      ),
    );
  }

  static Widget _speedBar(String label, double hours, Color color, double max) {
    final ratio = max > 0 ? (hours / max).clamp(0.0, 1.0) : 0.0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(fontSize: 9, color: Colors.white38)),
      const SizedBox(width: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 70,
          height: 6,
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
    ]);
  }

  static Widget _chartLegendDot({required Color color, required String label}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(width: 5),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ]);
}

// ── Sync Phones Button (self-contained stateful widget) ──────────────────────
class _SyncPhonesButton extends StatefulWidget {
  const _SyncPhonesButton();
  @override
  State<_SyncPhonesButton> createState() => _SyncPhonesButtonState();
}

class _SyncPhonesButtonState extends State<_SyncPhonesButton> {
  bool _syncing = false;
  String _result = '';

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _result = '';
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
      final res = await fn.httpsCallable('syncUserPhones').call();
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _syncing = false;
        _result =
            'עודכנו ${data['updated'] ?? 0} משתמשים מתוך ${data['scanned'] ?? 0}';
      });
    } catch (e) {
      setState(() {
        _syncing = false;
        _result = 'שגיאה: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: _syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.phone_rounded, size: 16),
          label: Text(_syncing ? 'מסנכרן...' : 'סנכרן מספרי טלפון'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: _syncing ? null : _sync,
        ),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _result,
            style: TextStyle(
              fontSize: 12,
              color: _result.startsWith('עודכנו') ? Colors.teal : Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
