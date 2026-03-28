import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/web_utils.dart';
import 'pending_categories_screen.dart';
import 'business_ai_screen.dart';
import 'xp_manager_screen.dart';
import 'dispute_resolution_screen.dart';
import 'system_performance_tab.dart';
import 'registration_funnel_tab.dart';
import '../services/category_service.dart';
import '../services/visual_fetcher_service.dart';
import '../l10n/app_localizations.dart'; // ignore: unused_import — partial i18n pass
import 'live_activity_tab.dart';
import 'admin_design_tab.dart';
import 'admin_chat_view_screen.dart';
import 'admin_demo_experts_tab.dart';
import 'admin_brand_assets_tab.dart';
import 'admin_payouts_tab.dart';
import 'admin_banners_tab.dart';
import 'admin_pro_tab.dart';
import 'admin_billing_tab.dart';
import '../widgets/hint_icon.dart';
import 'package:firebase_auth/firebase_auth.dart';


class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _searchQuery  = "";
  int    _sectionIndex = 0; // 0 = ניהול, 1 = תוכן, 2 = מערכת
  double _feePct        = 10.0;
  double _urgencyFeePct = 5.0;
  bool   _settingsLoaded = false;
  bool   _refreshingImages   = false;
  bool   _fixingImages       = false;
  bool   _resettingCounters  = false;

  // ── ID verification — tracks which UIDs are mid-request (prevents double-tap)
  final Set<String> _verifyingUids = {};
  // ── Locally approved UIDs — hides the Approve button instantly after CF success
  //    without waiting for the paginated _users list to reload.
  final Set<String> _approvedUids = {};
  int    _fixImagesDone    = 0;
  int    _fixImagesTotal   = 0;

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

  // ── DAU (Daily Active Users) — decoupled from allUsers stream ───────────────
  int  _insDau       = 0;
  bool _insDauLoaded = false;
  StreamSubscription<QuerySnapshot>? _insDauSub;

  // ── Paginated user list ─────────────────────────────────────────────────────
  final List<QueryDocumentSnapshot> _users = [];
  QueryDocumentSnapshot?            _lastUserDoc;
  bool _hasMoreUsers = true;
  bool _loadingUsers = false;
  bool _usersLoaded  = false;
  int  _totalCustomers = 0;
  int  _totalProviders = 0;

  @override
  void initState() {
    super.initState();
    _syncAppVersion();
    _loadAdminSettings();
    _setupInsightsStreams();
    _loadUsersPage();

  }

  // ── Auto-sync app version to Firestore ───────────────────────────────────────
  // Reads the real version from pubspec.yaml via PackageInfo and writes it to
  // admin/settings.latestVersion. This triggers the update banner for all other
  // users who are running an older build — no more manual version updates.
  Future<void> _syncAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version;
      if (version.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('admin')
          .doc('settings')
          .set({'latestVersion': version}, SetOptions(merge: true));
      debugPrint('Admin: synced latestVersion → $version');
    } catch (e) {
      debugPrint('Admin: version sync failed — $e');
    }
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

  Future<void> _loadAdminSettings() async {
    final doc = await FirebaseFirestore.instance
        .collection('admin').doc('admin')
        .collection('settings').doc('settings').get();
    if (!mounted) return;
    final d = doc.data() ?? {};
    setState(() {
      // Firestore stores decimal fraction (0.10 = 10%) — multiply ×100 for UI display
      _feePct        = (((d['feePercentage']       as num?) ?? 0.10) * 100).toDouble();
      _urgencyFeePct = (((d['urgencyFeePercentage'] as num?) ?? 0.05) * 100).toDouble();
      _settingsLoaded = true;
    });
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

    // 1. GMV — sum totalAmount of all completed jobs
    _insCompletedSub = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'completed')
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
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() { _insUnanswered = snap.docs.length; _insUnanswLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() { _insUnanswered = 0; _insUnanswLoaded = true; });
    });

    // 6. Banner analytics — click counts per banner (sorted desc)
    _insBannersSub = FirebaseFirestore.instance
        .collection('banners')
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

  // ── Paginated user list loader ─────────────────────────────────────────────
  Future<void> _loadUsersPage() async {
    if (_loadingUsers || !_hasMoreUsers) return;
    setState(() => _loadingUsers = true);

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .limit(50);
    if (_lastUserDoc != null) {
      query = query.startAfterDocument(_lastUserDoc!);
    }

    try {
      final snap = await query.get();
      if (!mounted) return;
      setState(() {
        _users.addAll(snap.docs);
        _hasMoreUsers = snap.docs.length == 50;
        if (snap.docs.isNotEmpty) _lastUserDoc = snap.docs.last;
        _usersLoaded  = true;
        _loadingUsers = false;
        _totalCustomers = _users
            .where((d) => (d.data() as Map)['isCustomer'] == true)
            .length;
        _totalProviders = _users
            .where((d) => (d.data() as Map)['isProvider'] == true)
            .length;
      });
    } catch (e) {
      if (mounted) setState(() { _loadingUsers = false; _usersLoaded = true; });
      debugPrint('Admin: _loadUsersPage error — $e');
    }
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
      final List<int> dayReqs  = List.filled(7, 0); // Mon=0 … Sun=6

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

  // ── CSV Export ────────────────────────────────────────────────────────────

  Future<void> _exportTransactionsCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text("מכין קובץ CSV...")));

    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .get();

      final buf = StringBuffer();
      // UTF-8 BOM for Excel compatibility
      buf.write('\uFEFF');
      buf.writeln('מזהה,משתמש,כותרת,סכום,סוג,תאריך');

      for (final doc in snap.docs) {
        final d  = doc.data();
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        final dateStr = ts != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(ts)
            : '';
        final amount = (d['amount'] as num? ?? 0).toStringAsFixed(2);
        // Escape any commas or quotes inside fields
        String esc(dynamic v) {
          final s = (v ?? '').toString().replaceAll('"', '""');
          return '"$s"';
        }
        buf.writeln([
          esc(doc.id),
          esc(d['userId']),
          esc(d['title']),
          esc(amount),
          esc(d['type']),
          esc(dateStr),
        ].join(','));
      }

      final csvStr  = buf.toString();
      final filename =
          'anyskill_transactions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';

      triggerCsvDownload(csvStr, filename);

      if (mounted) {
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text("${snap.size} רשומות יוצאו ל-$filename"),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text("שגיאה: $e")));
      }
    }
  }

  Future<void> _saveAdminSettings() async {
    await FirebaseFirestore.instance
        .collection('admin').doc('admin')
        .collection('settings').doc('settings')
        .set({
          // Divide ÷100 to store as decimal fraction (10% → 0.10)
          'feePercentage':       _feePct / 100,
          'urgencyFeePercentage': _urgencyFeePct / 100,
        }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.green, content: Text("ההגדרות נשמרו ✓")));
    }
  }

  String _calculateSeniority(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.inDays >= 365) {
      return "${(difference.inDays / 365).toStringAsFixed(1)} שנים";
    } else if (difference.inDays >= 30) {
      return "${(difference.inDays / 30).floor()} חודשים";
    } else {
      return "${difference.inDays} ימים";
    }
  }

  // תפריט פעולות משודרג - הכל במקום אחד
  void _showUserActions(String uid, Map<String, dynamic> data) {
    bool isBanned    = data['isBanned']    ?? false;
    bool isVerified  = data['isVerified']  ?? false;
    bool isPromoted  = data['isPromoted']  ?? false;
    bool isVerifiedProvider = data['isVerifiedProvider'] ?? true;
    final compliance = data['compliance'] as Map<String, dynamic>?;
    final docUrl = compliance?['docUrl'] as String?;
    final taxStatus = compliance?['taxStatus'] as String?;
    final bool isProvider = data['isProvider'] == true;
    String name = data['name'] ?? "משתמש";
    String currentNote = data['adminNote'] ?? "";

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Divider(),
              
              // אימות מומחה (וי כחול)
              ListTile(
                leading: Icon(isVerified ? Icons.verified_user : Icons.verified, color: Colors.blue),
                title: Text(isVerified ? "בטל אימות (הסר וי כחול)" : "אמת מומחה (הענק וי כחול)"),
                onTap: () {
                  FirebaseFirestore.instance.collection('users').doc(uid).update({'isVerified': !isVerified});
                  Navigator.pop(context);
                },
              ),

              // ספק מומלץ (זוהר זהוב בחיפוש)
              ListTile(
                leading: Icon(isPromoted ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isPromoted ? Colors.amber : Colors.grey),
                title: Text(isPromoted ? "בטל קידום (הסר זוהר זהוב)" : "קדם ספק (הוסף זוהר זהוב + עדיפות)"),
                subtitle: const Text("ספקים מקודמים מופיעים ראשונים בחיפוש",
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  FirebaseFirestore.instance.collection('users').doc(uid)
                      .update({'isPromoted': !isPromoted});
                  Navigator.pop(context);
                },
              ),

              // ציות ואימות ספק — רק לספקים עם מסמכים
              if (isProvider && compliance != null) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.shield_rounded,
                          color: isVerifiedProvider ? Colors.green : Colors.orange, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        isVerifiedProvider ? "ספק מאושר" : "ממתין לאישור ציות",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isVerifiedProvider ? Colors.green : Colors.orange,
                          fontSize: 13,
                        ),
                      ),
                      if (taxStatus != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            taxStatus == 'business' ? "עוסק פטור/מורשה" : "חשבונית לשכיר",
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (docUrl != null)
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded, color: Colors.blue),
                    title: const Text("צפה במסמך שהועלה"),
                    subtitle: const Text("פתח קישור לקובץ", style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      _openDocumentUrl(docUrl);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    isVerifiedProvider ? Icons.shield_outlined : Icons.verified_user_rounded,
                    color: isVerifiedProvider ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    isVerifiedProvider ? "בטל אישור ספק (נעל חשבון)" : "אשר ספק (פתח גישה)",
                    style: TextStyle(
                      color: isVerifiedProvider ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    FirebaseFirestore.instance.collection('users').doc(uid).update({
                      'isVerifiedProvider': !isVerifiedProvider,
                      if (!isVerifiedProvider) 'compliance.verified': true,
                    });
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
              ],

              // עמלה מותאמת — רק לספקים
              if (data['isProvider'] == true)
                ListTile(
                  leading: const Icon(Icons.percent_rounded, color: Colors.purple),
                  title: const Text("עמלת עסקה מותאמת אישית"),
                  subtitle: Text(
                    data['customCommission'] != null
                        ? "${((data['customCommission'] as num) * 100).toStringAsFixed(0)}% (מותאם)"
                        : "לא הוגדרה — ברירת מחדל גלובלית",
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showCustomCommissionDialog(
                      uid,
                      name,
                      (data['customCommission'] as num?)?.toDouble(),
                    );
                  },
                ),

              // הערת מנהל
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.amber),
                title: const Text("עדכן הערת מנהל פנימית"),
                subtitle: Text(currentNote.isNotEmpty ? currentNote : "אין הערות"),
                onTap: () {
                  Navigator.pop(context);
                  _showAddNoteDialog(uid, currentNote);
                },
              ),

              // חסימה/שחרור
              ListTile(
                leading: Icon(isBanned ? Icons.lock_open : Icons.block, color: Colors.orange),
                title: Text(isBanned ? "שחרר חסימת חשבון" : "חסום משתמש מהמערכת"),
                onTap: () {
                  FirebaseFirestore.instance.collection('users').doc(uid).update({'isBanned': !isBanned});
                  Navigator.pop(context);
                },
              ),

              // מחיקה
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text("מחק חשבון לצמיתות", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(uid, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddNoteDialog(String uid, String currentNote) {
    final TextEditingController noteController = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("הערת מנהל"),
        content: TextField(controller: noteController, maxLines: 3, decoration: const InputDecoration(hintText: "כתוב הערה...", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ביטול")),
          ElevatedButton(onPressed: () {
            FirebaseFirestore.instance.collection('users').doc(uid).update({'adminNote': noteController.text});
            Navigator.pop(context);
          }, child: const Text("שמור")),
        ],
      ),
    );
  }

  void _showCustomCommissionDialog(String uid, String name, double? current) {
    final ctrl = TextEditingController(
        text: current != null ? (current * 100).toStringAsFixed(0) : '');
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("עמלה מותאמת — $name"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "הגדר עמלה אישית לספק זה.\nהשאר ריק או לחץ 'הסר' כדי לחזור לעמלה הגלובלית.",
              style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.5),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: "לדוגמה: 8",
                suffixText: "%",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .update({'customCommission': FieldValue.delete()});
              if (ctx.mounted) Navigator.pop(ctx);
              messenger.showSnackBar(
                  SnackBar(content: Text("עמלת ברירת מחדל שוחזרה עבור $name")));
            },
            child: const Text("הסר (גלובלי)", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final pct = double.tryParse(ctrl.text.trim());
              if (pct == null || pct < 0 || pct > 100) return;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .update({'customCommission': pct / 100});
              if (ctx.mounted) Navigator.pop(ctx);
              messenger.showSnackBar(SnackBar(
                  backgroundColor: Colors.purple,
                  content: Text("עמלה של ${pct.toStringAsFixed(0)}% נשמרה עבור $name")));
            },
            child: const Text("שמור", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Edit Classification Dialog — live Firestore categories ──────────────────
  // Fetches the `categories` collection on open so the admin always sees the
  // same parent/sub tree that is shown on the home screen.
  void _showEditClassificationDialog(
      String uid, String currentCat, String currentSub, String providerName) {
    // Kick off the fetch before showing the dialog so there's no extra delay.
    final Future<QuerySnapshot> catFuture =
        FirebaseFirestore.instance.collection('categories').get();

    // Mutable state hoisted so both FutureBuilder and StatefulBuilder can share.
    String selCat = currentCat;
    String selSub = currentSub;
    bool   saving = false;

    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<QuerySnapshot>(
        future: catFuture,
        builder: (ctx, snap) {
          // ── Loading state ─────────────────────────────────────────────
          if (!snap.hasData) {
            return AlertDialog(
              title: Text('ערוך סיווג — $providerName',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              content: const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }

          // ── Build parent / sub maps from live Firestore docs ──────────
          final allDocs = snap.data!.docs;

          final parentDocs = allDocs
              .where((d) =>
                  ((d.data() as Map)['parentId'] as String? ?? '').isEmpty)
              .toList()
            ..sort((a, b) {
              final oA = ((a.data() as Map)['order'] as num? ?? 999).toInt();
              final oB = ((b.data() as Map)['order'] as num? ?? 999).toInt();
              return oA.compareTo(oB);
            });

          final parentNames = parentDocs
              .map((d) => (d.data() as Map)['name'] as String? ?? '')
              .where((n) => n.isNotEmpty)
              .toList();

          // Map: parentDocId → [subCategoryName, ...]
          final Map<String, List<String>> subsByParentId = {};
          for (final doc in allDocs) {
            final d        = doc.data() as Map<String, dynamic>;
            final parentId = d['parentId'] as String? ?? '';
            final subName  = d['name']     as String? ?? '';
            if (parentId.isNotEmpty && subName.isNotEmpty) {
              subsByParentId.putIfAbsent(parentId, () => []).add(subName);
            }
          }

          // Map: parentName → [subCategoryName, ...]
          final Map<String, List<String>> subsByName = {
            for (final pd in parentDocs)
              (pd.data() as Map)['name'] as String? ?? '':
                  subsByParentId[pd.id] ?? [],
          };

          // Validate current selection against live data.
          if (!parentNames.contains(selCat)) {
            selCat = parentNames.isNotEmpty ? parentNames.first : '';
          }
          final initSubs = subsByName[selCat] ?? [];
          if (!initSubs.contains(selSub)) {
            selSub = initSubs.isNotEmpty ? initSubs.first : '';
          }

          // ── Dialog with StatefulBuilder for selection changes ─────────
          return StatefulBuilder(builder: (ctx2, setDlg) {
            final subs = subsByName[selCat] ?? [];
            return AlertDialog(
              title: Text('ערוך סיווג — $providerName',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('קטגוריה',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: parentNames.contains(selCat)
                        ? selCat
                        : (parentNames.isNotEmpty ? parentNames.first : null),
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon:
                          const Icon(Icons.category_rounded, size: 18),
                    ),
                    items: parentNames
                        .map((name) => DropdownMenuItem(
                              value: name,
                              child: Text(name,
                                  textAlign: TextAlign.right),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final newSubs = subsByName[v] ?? [];
                      setDlg(() {
                        selCat = v;
                        selSub =
                            newSubs.isNotEmpty ? newSubs.first : '';
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('תת-קטגוריה',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  if (subs.isEmpty)
                    const Text('אין תת-קטגוריות לקטגוריה זו',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey))
                  else
                    DropdownButtonFormField<String>(
                      value: subs.contains(selSub)
                          ? selSub
                          : subs.first,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        prefixIcon:
                            const Icon(Icons.tune_rounded, size: 18),
                      ),
                      items: subs
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s,
                                    textAlign: TextAlign.right),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setDlg(() => selSub = v ?? selSub),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded,
                            size: 14, color: Color(0xFF6366F1)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'השמירה תסמן את הסיווג כ"נבדק על-ידי אדמין" ותסיר את תג AI Suggested.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700]),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('ביטול'),
                ),
                ElevatedButton.icon(
                  icon: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 16),
                  label: const Text('שמור'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          setDlg(() => saving = true);
                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .update({
                              'serviceType':             selCat,
                              'subCategory':             selSub,
                              'isProvider':              true,
                              'isSpecialist':            true,
                              'categoryReviewedByAdmin': true,
                              'classificationUpdatedAt':
                                  FieldValue.serverTimestamp(),
                              'classificationUpdatedBy':
                                  FirebaseAuth.instance.currentUser?.uid ??
                                      'admin',
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    '✅ $providerName — סיווג עודכן: $selCat › $selSub'),
                                backgroundColor:
                                    const Color(0xFF6366F1),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ));
                            }
                          } catch (e) {
                            setDlg(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('שגיאה: $e'),
                                backgroundColor: Colors.red,
                              ));
                            }
                          }
                        },
                ),
              ],
            );
          });
        },
      ),
    );
  }

  void _showAddBalanceDialog(String uid, String name) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final TextEditingController amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("הטענת ארנק ל-$name"),
        content: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "סכום להוספה", suffixText: "₪", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("ביטול")),
          ElevatedButton(onPressed: () async {
            final val = double.tryParse(amountController.text.trim());
            if (val == null || val <= 0) return;
            Navigator.pop(dialogContext);
            // FieldValue.increment מונע race condition
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
              tx.update(userRef, {'balance': FieldValue.increment(val)});
              tx.set(FirebaseFirestore.instance.collection('transactions').doc(), {
                'userId': uid,
                'amount': val,
                'title': 'טעינת ארנק ע״י מנהל',
                'timestamp': FieldValue.serverTimestamp(),
                'type': 'admin_topup',
              });
            });
            scaffoldMessenger.showSnackBar(SnackBar(content: Text("נטענו ₪$val לארנק של $name")));
          }, child: const Text("אשר והטען")),
        ],
      ),
    );
  }

  void _confirmDelete(String uid, String name) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקה סופית"),
        content: Text("האם למחוק את $name לצמיתות?\nהחשבון יימחק גם מ-Auth וגם מהמסד. לא ניתן לשחזר."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFunctions.instance.httpsCallable('deleteUser').call({'uid': uid});
                messenger.showSnackBar(
                  SnackBar(backgroundColor: Colors.green, content: Text("$name נמחק בהצלחה")),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(backgroundColor: Colors.red, content: Text("שגיאה במחיקה: $e")),
                );
              }
            },
            child: const Text("מחק", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBroadcastDialog() {
    final TextEditingController broadcastController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text("שידור גלובלי"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ההודעה תופיע כבאנר כחול לכל המשתמשים בדף הבית.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: broadcastController,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "כתוב את ההודעה כאן...",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(ctx),
              child: const Text("ביטול"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent),
              onPressed: isSending
                  ? null
                  : () async {
                      final msg = broadcastController.text.trim();
                      if (msg.isEmpty) return;
                      setDlgState(() => isSending = true);

                      // 1. Write banner (shown immediately to all online users)
                      await FirebaseFirestore.instance
                          .collection('admin')
                          .doc('settings')
                          .set({'broadcastMessage': msg},
                              SetOptions(merge: true));

                      // 2. Log to broadcast_history
                      await FirebaseFirestore.instance
                          .collection('broadcast_history')
                          .add({
                        'message':   msg,
                        'sentAt':    FieldValue.serverTimestamp(),
                        'sentBy':    'admin',
                        'platform':  'in-app-banner',
                      });

                      // 3. Call Cloud Function to push FCM to all users
                      try {
                        await FirebaseFunctions.instance
                            .httpsCallable('sendGlobalBroadcast')
                            .call({'message': msg});
                      } catch (e) {
                        debugPrint('Broadcast FCM error (non-fatal): $e');
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('שידור נשלח בהצלחה!'),
                            backgroundColor: Colors.blueAccent,
                          ),
                        );
                      }
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white),
              label: const Text("שדר עכשיו",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: _buildSectionToggle(),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: Colors.blueAccent, size: 28),
            onPressed: _showBroadcastDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_usersLoaded
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _sectionIndex,
              children: [
                _buildManagementSection(_users, _totalCustomers, _totalProviders),
                _buildContentSection(),
                _buildSystemSection(),
                const AdminDesignTab(),
              ],
            ),
    );
  }

  // ── Section toggle (SegmentedButton in AppBar title) ────────────────────────

  Widget _buildSectionToggle() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          label: Text('ניהול'),
          icon: Icon(Icons.manage_accounts_rounded, size: 15),
        ),
        ButtonSegment(
          value: 1,
          label: Text('תוכן'),
          icon: Icon(Icons.movie_filter_rounded, size: 15),
        ),
        ButtonSegment(
          value: 2,
          label: Text('מערכת'),
          icon: Icon(Icons.settings_rounded, size: 15),
        ),
        ButtonSegment(
          value: 3,
          label: Text('עיצוב'),
          icon: Icon(Icons.design_services_rounded, size: 15),
        ),
      ],
      selected: {_sectionIndex},
      onSelectionChanged: (s) => setState(() => _sectionIndex = s.first),
      style: ButtonStyle(
        tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
        visualDensity:  VisualDensity.compact,
        textStyle:      WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Management section (ניהול) — 14 tabs ──────────────────────────────────

  Widget _buildManagementSection(
    List<QueryDocumentSnapshot> allUsers,
    int customers,
    int providers,
  ) {
    return DefaultTabController(
      length: 14,
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "חפש שם, מייל או מזהה...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Stats badges
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pulseBadge("👥 $customers לקוחות"),
                _pulseBadge("🛠️ $providers ספקים"),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Tabs
          const TabBar(
            isScrollable: true,
            labelColor:     Colors.blueAccent,
            indicatorColor: Colors.blueAccent,
            tabs: [
              Tab(text: "הכל"),
              Tab(text: "לקוחות"),
              Tab(text: "ספקים"),
              Tab(text: "חסומים"),
              Tab(text: "מחלוקות 🔴"),
              Tab(text: "משיכות 💸"),
              Tab(text: "XP & רמות 🎮"),
              Tab(text: "אימות זהות 🪪"),
              Tab(text: "משפך הרשמה 📈"),
              Tab(text: "לייב פיד 📡"),
              Tab(text: "צ'אטים 💬"),
              Tab(text: "דמו ★"),
              Tab(text: "Pro ⭐"),
              Tab(text: "בינה עסקית 🧠"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildList(allUsers),
                _buildList(allUsers.where((d) => (d.data() as Map)['isCustomer'] == true).toList()),
                _buildList(allUsers.where((d) => (d.data() as Map)['isProvider'] == true).toList()),
                _buildList(allUsers.where((d) => (d.data() as Map)['isBanned'] == true).toList()),
                const DisputeResolutionScreen(),
                _buildWithdrawalsList(),
                const XpManagerScreen(),
                _buildIdVerificationTab(),
                const RegistrationFunnelTab(),
                const LiveActivityTab(),
                _buildSupportTab(),
                const AdminDemoExpertsTab(),
                const AdminProTab(),
                const BusinessAiScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Content section (תוכן) — 4 tabs ─────────────────────────────────────

  Widget _buildContentSection() {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            labelColor:     Color(0xFFD97706),
            indicatorColor: Color(0xFFD97706),
            tabs: [
              Tab(icon: Icon(Icons.auto_stories_rounded, size: 18), text: 'סטוריז 📸'),
              Tab(icon: Icon(Icons.school_rounded,       size: 18), text: 'אקדמיה 🎓'),
              Tab(icon: Icon(Icons.videocam_rounded,     size: 18), text: 'וידאו ✅'),
              Tab(icon: Icon(Icons.lock_outline_rounded, size: 18), text: 'משוב פרטי 🔒'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildStoriesManagementTab(),
                _buildAcademyManagementTab(),
                _buildVideoVerificationTab(),
                _buildPrivateFeedbackTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Private feedback tab ───────────────────────────────────────────────────
  Widget _buildPrivateFeedbackTab() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final allDocs = snap.data?.docs ?? [];
        // Filter client-side: only reviews with a non-empty privateAdminComment
        final docs = allDocs.where((doc) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          final msg = d['privateAdminComment']?.toString() ?? '';
          return msg.trim().isNotEmpty;
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 52, color: Colors.grey),
                SizedBox(height: 12),
                Text('אין הודעות פרטיות למנהל',
                    style: TextStyle(color: Colors.grey, fontSize: 15)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>? ?? {};
            final reviewerName   = d['reviewerName']?.toString()       ?? '—';
            final privateComment = d['privateAdminComment']?.toString() ?? '';
            final overallRating  = (d['overallRating'] as num?)?.toDouble()
                ?? (d['rating'] as num?)?.toDouble()
                ?? 0.0;
            final isPublished    = d['isPublished'] as bool? ?? true;
            final ts             = d['createdAt'] ?? d['timestamp'];
            final timeStr = ts is Timestamp
                ? DateFormat('dd/MM/yy HH:mm').format(ts.toDate())
                : '—';
            final isClientReview = d['isClientReview'] as bool? ?? true;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFCD34D)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPublished
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isPublished ? 'פורסם' : 'ממתין',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isPublished
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              overallRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFBBF24)),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.star_rounded,
                                size: 14, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 8),
                            Text(
                              isClientReview ? 'לקוח→מומחה' : 'מומחה→לקוח',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'מאת: $reviewerName',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        privateComment,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF92400E)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeStr,
                      textAlign: TextAlign.right,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Stories management tab ─────────────────────────────────────────────────
  Widget _buildStoriesManagementTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded, size: 52, color: Colors.grey),
                SizedBox(height: 12),
                Text('אין סטוריז פעילים כרגע',
                    style: TextStyle(color: Colors.grey, fontSize: 15)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>? ?? {};
            final uid          = docs[i].id;
            final name         = d['providerName']?.toString()   ?? uid;
            final serviceType  = d['serviceType']?.toString()    ?? '';
            final videoUrl     = d['videoUrl']?.toString()       ?? '';
            final ts           = d['timestamp'];
            final timeStr      = ts is Timestamp
                ? DateFormat('dd/MM HH:mm').format(ts.toDate())
                : '—';
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFFEF3C7),
                  backgroundImage: (d['providerAvatar']?.toString() ?? '').startsWith('http')
                      ? NetworkImage(d['providerAvatar'] as String)
                      : null,
                  child: (d['providerAvatar']?.toString() ?? '').startsWith('http')
                      ? null
                      : const Icon(Icons.person, color: Color(0xFFD97706)),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (serviceType.isNotEmpty) Text(serviceType,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1))),
                    Text(timeStr,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (videoUrl.isNotEmpty)
                      Text('📹 ${videoUrl.substring(0, videoUrl.length.clamp(0, 50))}…',
                          style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 22),
                  tooltip: 'מחק סטורי',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('מחיקת סטורי'),
                        content: Text('למחוק את הסטורי של $name?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false),
                              child: const Text('ביטול')),
                          TextButton(onPressed: () => Navigator.pop(context, true),
                              child: const Text('מחק', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseFirestore.instance
                          .collection('stories')
                          .doc(uid)
                          .delete();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🗑️ הסטורי נמחק'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Academy management tab ─────────────────────────────────────────────────
  Widget _buildAcademyManagementTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('courses')
          .orderBy('order')
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ── Summary card ──────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_rounded, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${docs.length} קורסים פעילים',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const Text('AnySkill Academy',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            // ── Course list ───────────────────────────────────────────────
            if (docs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('אין קורסים עדיין. הוסף קורסים ל-Firestore בקולקציית courses.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
                ),
              )
            else
              ...docs.map((doc) {
                final d           = doc.data() as Map<String, dynamic>? ?? {};
                final title       = d['title']?.toString()       ?? '—';
                final category    = d['category']?.toString()    ?? '';
                final duration    = d['duration']?.toString()    ?? '';
                final order       = (d['order'] as num? ?? 0).toInt();
                final xpReward    = (d['xpReward'] as num? ?? 200).toInt();
                final quizCount   = (d['quizQuestions'] as List? ?? []).length;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('#$order',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (category.isNotEmpty)
                                  _miniChip(category, const Color(0xFF6366F1)),
                                if (duration.isNotEmpty)
                                  _miniChip('⏱ $duration', Colors.teal),
                                _miniChip('+$xpReward XP', Colors.amber.shade700),
                                _miniChip('$quizCount שאלות', Colors.grey.shade600),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 20),
                        tooltip: 'מחק קורס',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('מחיקת קורס'),
                              content: Text('למחוק את הקורס "$title"?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('ביטול')),
                                TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('מחק',
                                        style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance
                                .collection('courses')
                                .doc(doc.id)
                                .delete();
                          }
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _miniChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  // ── System section (מערכת) — 7 tabs ──────────────────────────────────────

  Widget _buildSystemSection() {
    return DefaultTabController(
      length: 9,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            labelColor:     Color(0xFF7C3AED),
            indicatorColor: Color(0xFF7C3AED),
            tabs: [
              Tab(text: "קטגוריות 🏷️"),
              Tab(text: "באנרים 🎨"),
              Tab(text: "מוניטיזציה 💰"),
              Tab(text: "כספים 💵"),
              Tab(text: "תובנות 📊"),
              Tab(text: "ביצועים 🖥️"),
              Tab(text: "מיתוג 🎨"),
              Tab(text: "חסימות 🛡️"),
              Tab(text: "תשלומים 💳"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCategoriesTab(),
                const AdminBannersTab(),
                _buildMonetizationTab(),
                const AdminBillingTab(),
                _buildInsightsTab(),
                const SystemPerformanceTab(),
                const AdminBrandAssetsTab(),
                _buildChatGuardTab(),
                const AdminPayoutsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Chat Guard admin tab ──────────────────────────────────────────────────

  Widget _buildChatGuardTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('activity_log')
          .where('type', isEqualTo: 'bypass_attempt')
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Status card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: Colors.white, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chat Guard — פעיל',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${docs.length} ניסיונות עקיפה זוהו',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Active patterns ──────────────────────────────────────────
            const Text(
              'פטרנים פעילים',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                '📵 טלפון ישראלי', '💬 וואטסאפ', '💵 מזומן',
                '🔗 wa.me', '📞 טלפון', '💳 ביט',
                '🌐 Outside App', '💸 Cash',
              ].map((label) => Chip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color(0xFFEDE9FE),
                side: const BorderSide(color: Color(0xFF7C3AED), width: 0.5),
              )).toList(),
            ),
            const SizedBox(height: 24),

            // ── Bypass attempts log ──────────────────────────────────────
            const Text(
              'ניסיונות עקיפה אחרונים',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),

            if (docs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'אין ניסיונות עקיפה עדיין ✅',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final d         = doc.data() as Map<String, dynamic>;
                final userId    = (d['userId']    as String?) ?? '—';
                final flagType  = (d['flagType']  as String?) ?? '—';
                final attempts  = (d['attemptCount'] as num?)?.toInt() ?? 1;
                final ts        = (d['timestamp'] as dynamic);
                String timeStr  = '';
                if (ts != null) {
                  try {
                    final dt = (ts as dynamic).toDate() as DateTime;
                    timeStr  = '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2,'0')}';
                  } catch (_) {}
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: attempts >= 3
                      ? const Color(0xFFFFF1F2)
                      : const Color(0xFFFAF5FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: attempts >= 3
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFDDD6FE),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: attempts >= 3
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF7C3AED),
                      child: Text(
                        '$attempts',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      userId.length > 20 ? '${userId.substring(0, 20)}…' : userId,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '$flagType  •  $timeStr',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    trailing: attempts >= 3
                        ? const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18)
                        : null,
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  // ── Category Management ───────────────────────────────────────────────────

  /// Formats raw click counts for compact display: 1 234 → "1.2k", < 1 000 → "$n".
  static String _fmtClicks(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  /// Resets clickCount to 0 on every category document in a single batch.
  Future<void> _resetPopularityCounters(
      List<Map<String, dynamic>> allCats) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.restart_alt_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('איפוס מונים', style: TextStyle(fontSize: 17)),
        ]),
        content: const Text(
          'פעולה זו תאפס את מונה הלחיצות של כל הקטגוריות ל-0.\n'
          'הדירוג הדינמי יתחיל מחדש.\n\n'
          'האם אתה בטוח?',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('אפס', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingCounters = true);
    try {
      final db    = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final cat in allCats) {
        batch.update(
          db.collection('categories').doc(cat['id'] as String),
          {'clickCount': 0},
        );
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          content: Text('✅ מוני הפופולריות אופסו בהצלחה'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resettingCounters = false);
    }
  }

  /// Top-5 leaderboard card shown at the top of the categories tab.
  Widget _buildPopularityLeaderboard(List<Map<String, dynamic>> mainCats) {
    final top = (List.of(mainCats)
          ..sort((a, b) {
            final cA = (a['clickCount'] as num? ?? 0).toInt();
            final cB = (b['clickCount'] as num? ?? 0).toInt();
            return cB.compareTo(cA);
          }))
        .take(5)
        .toList();

    // Don't show the leaderboard if no category has any clicks yet.
    final totalClicks =
        top.fold<int>(0, (s, c) => s + (c['clickCount'] as num? ?? 0).toInt());
    if (totalClicks == 0) return const SizedBox.shrink();

    const medals = ['🥇', '🥈', '🥉', '4.', '5.'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFFBBF24), size: 20),
              SizedBox(width: 6),
              Text('Top 5 — קטגוריות הכי פופולריות',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
            const SizedBox(height: 12),
            ...top.asMap().entries.map((e) {
              final rank   = e.key;
              final cat    = e.value;
              final clicks = (cat['clickCount'] as num? ?? 0).toInt();
              final pct    = totalClicks > 0 ? clicks / totalClicks : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  // Medal / rank
                  SizedBox(
                    width: 28,
                    child: Text(medals[rank],
                        style: const TextStyle(fontSize: 14)),
                  ),
                  // Name
                  Expanded(
                    child: Text(
                      cat['name'] as String? ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Progress bar
                  SizedBox(
                    width: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.toDouble(),
                        minHeight: 6,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFBBF24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Count
                  Text(
                    '${_fmtClicks(clicks)} 👁',
                    style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CategoryService.stream(),
      builder: (context, snapshot) {
        final cats = snapshot.data ?? [];
        final mainCats = cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();
        final subCats  = cats.where((c) => (c['parentId'] as String? ?? '').isNotEmpty).toList();

        // Build grouped items: for each main cat append its subs
        final List<Map<String, dynamic>> grouped = [];
        for (final main in mainCats) {
          grouped.add({...main, '_isMain': true});
          final children = subCats.where((s) => s['parentId'] == main['id']).toList();
          for (final sub in children) {
            grouped.add({...sub, '_isMain': false, '_parentName': main['name']});
          }
        }

        return Column(
          children: [
            // ── Global card scale slider ────────────────────────────────────
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('system_settings')
                  .doc('global')
                  .snapshots(),
              builder: (context, settingsSnap) {
                final settingsData =
                    (settingsSnap.data?.data() as Map<String, dynamic>?) ?? {};
                final currentScale =
                    (settingsData['categoryCardScale'] as num? ?? 1.0).toDouble();

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.aspect_ratio_rounded,
                              color: Color(0xFF6366F1), size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'גודל כרטיסי קטגוריה — גלובלי',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${currentScale.toStringAsFixed(2)}×',
                              style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value:       currentScale,
                        min:         0.6,
                        max:         1.5,
                        divisions:   18,
                        activeColor: const Color(0xFF6366F1),
                        inactiveColor:
                            const Color(0xFF6366F1).withValues(alpha: 0.15),
                        // onChanged is required by Flutter; visual feedback only —
                        // the StreamBuilder will re-render when Firestore updates.
                        onChanged:   (_) {},
                        onChangeEnd: (v) {
                          FirebaseFirestore.instance
                              .collection('system_settings')
                              .doc('global')
                              .set({'categoryCardScale': v},
                                  SetOptions(merge: true));
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0.6×',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 11)),
                          TextButton(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero),
                            onPressed: (currentScale - 1.0).abs() < 0.01
                                ? null
                                : () {
                                    FirebaseFirestore.instance
                                        .collection('system_settings')
                                        .doc('global')
                                        .set({'categoryCardScale': 1.0},
                                            SetOptions(merge: true));
                                  },
                            child: const Text('איפוס לברירת מחדל (1.0×)',
                                style: TextStyle(fontSize: 11)),
                          ),
                          Text('1.5×',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text("הוסף קטגוריה", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () => _showCategoryDialog(existingCount: cats.length),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1)),
                label: const Text("קטגוריות ממתינות לאישור AI",
                    style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PendingCategoriesScreen())),
              ),
            ),
            // ── AI Auto-Created Categories Log ──────────────────────────────
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admin_logs')
                  .where('type', isEqualTo: 'new_category')
                  .where('isReviewed', isEqualTo: false)
                  .orderBy('createdAt', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Row(children: [
                        const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6), size: 18),
                        const SizedBox(width: 6),
                        Text('קטגוריות חדשות שנוצרו ע"י AI (${docs.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8B5CF6))),
                      ]),
                    ),
                    ...docs.map((doc) {
                      final d = doc.data()! as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDDD6FE)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.new_label_rounded, color: Color(0xFF8B5CF6), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['categoryName'] ?? '—',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (d['subCategoryName'] != null)
                                      Text('תת-קטגוריה: ${d['subCategoryName']}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                                    const SizedBox(height: 4),
                                    Text('על בסיס: "${d['triggerDescription'] ?? ''}"',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                    Text('ביטחון: ${((d['confidence'] as num? ?? 0) * 100).round()}%',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => FirebaseFirestore.instance
                                    .collection('admin_logs')
                                    .doc(doc.id)
                                    .update({'isReviewed': true}),
                                child: const Text('סמן כנבדק', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
            // ── Refresh Category Images ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _refreshingImages
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.image_search_rounded, color: Colors.white),
                label: Text(
                  _refreshingImages ? 'מרענן תמונות...' : 'רענן תמונות קטגוריה',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: _refreshingImages
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _refreshingImages = true);
                        try {
                          await VisualFetcherService.forceRefreshAll();
                          messenger.showSnackBar(const SnackBar(
                            backgroundColor: Color(0xFF22C55E),
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'תמונות הקטגוריות עודכנו בהצלחה ✅',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ));
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('שגיאה: $e'),
                          ));
                        } finally {
                          if (mounted) setState(() => _refreshingImages = false);
                        }
                      },
              ),
            ),
            // ── Fix All Images (unique, no duplicates) ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _fixingImages
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, color: Colors.white),
                label: Text(
                  _fixingImages
                      ? 'מתקן תמונות... $_fixImagesDone/$_fixImagesTotal'
                      : '🔧 תקן כל התמונות (ייחודי)',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: (_fixingImages || _refreshingImages)
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() {
                          _fixingImages   = true;
                          _fixImagesDone  = 0;
                          _fixImagesTotal = 0;
                        });
                        try {
                          await VisualFetcherService.fixAllImages(
                            onProgress: (done, total) {
                              if (mounted) {
                                setState(() {
                                  _fixImagesDone  = done;
                                  _fixImagesTotal = total;
                                });
                              }
                            },
                          );
                          messenger.showSnackBar(const SnackBar(
                            backgroundColor: Color(0xFF22C55E),
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              '✅ כל תמונות הקטגוריות עודכנו בהצלחה!',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ));
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('שגיאה: $e'),
                          ));
                        } finally {
                          if (mounted) setState(() => _fixingImages = false);
                        }
                      },
              ),
            ),
            // ── Popularity Leaderboard ──────────────────────────────────────
            _buildPopularityLeaderboard(mainCats),

            // ── Reset Counters button ───────────────────────────────────────
            if (cats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _resettingCounters
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.orange))
                      : const Icon(Icons.restart_alt_rounded),
                  label: Text(
                    _resettingCounters
                        ? 'מאפס...'
                        : '🔄 אפס מוני פופולריות',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed:
                      _resettingCounters ? null : () => _resetPopularityCounters(cats),
                ),
              ),

            if (!snapshot.hasData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (cats.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("אין קטגוריות — לחץ 'הוסף'", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final cat = grouped[index];
                    final isMain = cat['_isMain'] as bool;
                    final parentName = cat['_parentName'] as String?;

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: 10,
                        left: isMain ? 0 : 24, // indent sub-categories
                      ),
                      child: Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isMain ? Colors.grey.shade200 : Colors.blue.shade100,
                          ),
                        ),
                        color: isMain ? Colors.white : Colors.blue.shade50,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isMain ? Colors.blue[50] : Colors.blue[100],
                            child: Icon(
                              CategoryService.getIcon(cat['iconName']),
                              color: isMain ? Colors.blueAccent : Colors.blue[700],
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              if (!isMain)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[200],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text("תת", style: TextStyle(fontSize: 10, color: Colors.blue[900], fontWeight: FontWeight.bold)),
                                ),
                              Expanded(
                                child: Text(
                                  cat['name'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMain ? 15 : 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            isMain ? (cat['iconName'] ?? '') : "תחת: $parentName",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ── Click-count badge ──────────────────────
                              Builder(builder: (_) {
                                final clicks =
                                    (cat['clickCount'] as num? ?? 0).toInt();
                                final isHot  = clicks >= 100;
                                final isWarm = clicks >= 10;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isHot
                                        ? Colors.orange[50]
                                        : isWarm
                                            ? Colors.amber[50]
                                            : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isHot
                                          ? Colors.orange.shade300
                                          : isWarm
                                              ? Colors.amber.shade300
                                              : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isHot ? '🔥' : '👁',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _fmtClicks(clicks),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isHot
                                              ? Colors.orange[800]
                                              : isWarm
                                                  ? Colors.amber[800]
                                                  : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                                onPressed: () => _showCategoryDialog(existing: cat, existingCount: cats.length),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _confirmDeleteCategory(cat['id'] as String, cat['name'] ?? '', isMain: isMain),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _showCategoryDialog({Map<String, dynamic>? existing, int existingCount = 0}) {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final imgController = TextEditingController(text: existing?['img'] ?? '');
    String selectedIcon = existing?['iconName'] ?? CategoryService.iconMap.keys.first;
    // parentId: '' = main category, non-empty = sub-category
    String selectedParentId = existing?['parentId'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing == null ? "הוסף קטגוריה" : "עריכת קטגוריה", textAlign: TextAlign.right),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Parent category selector ──────────────────────────────
                const Text("קטגוריית אב", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: CategoryService.streamMainCategories(),
                  builder: (_, snap) {
                    final mainCats = snap.data ?? [];
                    // Guard: if the currently-selected parentId no longer exists, reset to ''
                    final validParentId = mainCats.any((c) => c['id'] == selectedParentId)
                        ? selectedParentId
                        : '';
                    if (validParentId != selectedParentId) {
                      // Use addPostFrameCallback to avoid setState-during-build
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setDialog(() => selectedParentId = validParentId);
                      });
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButton<String>(
                        value: validParentId,
                        isExpanded: true,
                        underline: const SizedBox(),
                        onChanged: (val) {
                          if (val != null) setDialog(() => selectedParentId = val);
                        },
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Row(children: [
                              Icon(Icons.folder_outlined, size: 18, color: Colors.grey),
                              SizedBox(width: 8),
                              Text("ראשי (ללא הורה)", style: TextStyle(fontSize: 13)),
                            ]),
                          ),
                          ...mainCats.map((c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Row(children: [
                              Icon(CategoryService.getIcon(c['iconName']), size: 18, color: Colors.blueAccent),
                              const SizedBox(width: 8),
                              Text(c['name'] ?? '', style: const TextStyle(fontSize: 13)),
                            ]),
                          )),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // ── Name ─────────────────────────────────────────────────
                const Text("שם קטגוריה", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: "לדוגמה: פילאטיס",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Icon ─────────────────────────────────────────────────
                const Text("אייקון", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: selectedIcon,
                    isExpanded: true,
                    underline: const SizedBox(),
                    onChanged: (val) {
                      if (val != null) setDialog(() => selectedIcon = val);
                    },
                    items: CategoryService.iconMap.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Icon(e.value, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 10),
                          Text(e.key, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Image URL ────────────────────────────────────────────
                const Text("קישור תמונה (אופציונלי)", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: imgController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: "https://...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                if (existing == null) {
                  await FirebaseFirestore.instance.collection('categories').doc(name).set({
                    'name': name,
                    'iconName': selectedIcon,
                    'img': imgController.text.trim(),
                    'order': existingCount,
                    'parentId': selectedParentId,
                  });
                } else {
                  await FirebaseFirestore.instance.collection('categories').doc(existing['id'] as String).update({
                    'name': name,
                    'iconName': selectedIcon,
                    'img': imgController.text.trim(),
                    'parentId': selectedParentId,
                  });
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: Colors.green, content: Text(existing == null ? "הקטגוריה נוספה!" : "הקטגוריה עודכנה!")),
                  );
                }
              },
              child: const Text("שמור", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCategory(String docId, String name, {bool isMain = true}) async {
    // For main categories, check how many sub-categories will also be deleted
    int subCount = 0;
    if (isMain) {
      final subSnap = await FirebaseFirestore.instance
          .collection('categories')
          .where('parentId', isEqualTo: docId)
          .get();
      subCount = subSnap.docs.length;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("מחיקת קטגוריה", textAlign: TextAlign.right),
        content: Text(
          subCount > 0
              ? "האם למחוק את הקטגוריה \"$name\"?\nגם $subCount תת-קטגוריות שלה יימחקו.\nפעולה זו אינה ניתנת לביטול."
              : "האם למחוק את הקטגוריה \"$name\"?\nפעולה זו אינה ניתנת לביטול.",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              // Cascade delete: remove all sub-categories first, then the parent
              final subSnap = await FirebaseFirestore.instance
                  .collection('categories')
                  .where('parentId', isEqualTo: docId)
                  .get();
              final batch = FirebaseFirestore.instance.batch();
              for (final sub in subSnap.docs) {
                batch.delete(sub.reference);
              }
              batch.delete(FirebaseFirestore.instance.collection('categories').doc(docId));
              await batch.commit();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("הקטגוריה \"$name\" נמחקה")),
                );
              }
            },
            child: const Text("מחק", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _pulseBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildWithdrawalsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text("אין בקשות משיכה ממתינות", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final w = docs[index].data() as Map<String, dynamic>;
            final wId = docs[index].id;
            final uid = w['userId'] as String? ?? '';
            final amount = (w['amount'] ?? 0.0).toDouble();
            DateTime? requestedAt = (w['requestedAt'] as Timestamp?)?.toDate();
            final formattedDate = requestedAt != null
                ? DateFormat('dd/MM HH:mm').format(requestedAt)
                : '—';

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.blue.shade100),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row: amount + date ──────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("₪${amount.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 20)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(formattedDate,
                              style: TextStyle(
                                  color: Colors.orange[800], fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── User name (live lookup) ─────────────────────────
                    FutureBuilder<DocumentSnapshot?>(
                      future: uid.isNotEmpty
                          ? FirebaseFirestore.instance.collection('users').doc(uid).get()
                          : Future.value(null),
                      builder: (context, userSnap) {
                        String userName = uid.isEmpty ? '—' : 'טוען...';
                        if (userSnap.connectionState == ConnectionState.done) {
                          if (userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                            final uData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                            userName = uData['name'] as String? ?? uid;
                          } else {
                            userName = uid;
                          }
                        }
                        return Row(
                          children: [
                            const Icon(Icons.person_outline, size: 15, color: Colors.blueGrey),
                            const SizedBox(width: 5),
                            Text(userName,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),

                    // ── Bank details ────────────────────────────────────
                    _wDetailRow(Icons.account_balance_outlined, "בנק", w['bankName']),
                    _wDetailRow(Icons.tag,                       "חשבון", w['accountNumber']),
                    _wDetailRow(Icons.fork_right,                "סניף", w['branchNumber']),
                    const SizedBox(height: 14),

                    // ── Action buttons ──────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.close, color: Colors.red, size: 18),
                            label: const Text("דחה",
                                style: TextStyle(color: Colors.red, fontSize: 13)),
                            onPressed: () async {
                              await FirebaseFirestore.instance.runTransaction((tx) async {
                                tx.update(
                                  FirebaseFirestore.instance.collection('withdrawals').doc(wId),
                                  {'status': 'rejected', 'resolvedAt': FieldValue.serverTimestamp()},
                                );
                                if (uid.isNotEmpty) {
                                  tx.update(
                                    FirebaseFirestore.instance.collection('users').doc(uid),
                                    {'balance': FieldValue.increment(amount)},
                                  );
                                  tx.set(FirebaseFirestore.instance.collection('transactions').doc(), {
                                    'userId': uid,
                                    'amount': amount,
                                    'title': 'בקשת משיכה נדחתה — הסכום הוחזר',
                                    'timestamp': FieldValue.serverTimestamp(),
                                    'type': 'refund',
                                  });
                                }
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("הבקשה נדחתה והסכום הוחזר")));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check, color: Colors.white, size: 18),
                            label: const Text("בוצע — סמן כהושלם",
                                style: TextStyle(color: Colors.white, fontSize: 13)),
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('withdrawals')
                                  .doc(wId)
                                  .update({
                                'status': 'completed',
                                'completedAt': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Colors.green,
                                    content: Text("ההעברה סומנה כהושלמה ✓"),
                                  ));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Small helper for a labelled detail row in the withdrawal card ──────────
  Widget _wDetailRow(IconData icon, String label, dynamic value) {
    final str = (value?.toString() ?? '').isNotEmpty ? value.toString() : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 5),
          Text("$label: ", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          Text(str, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }



  Widget _buildList(List<QueryDocumentSnapshot> users) {
    var filtered = users.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      String name = (data['name'] ?? "").toLowerCase();
      String email = (data['email'] ?? "").toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100, top: 10),
      itemCount: filtered.length + (_hasMoreUsers || _loadingUsers ? 1 : 0),
      itemBuilder: (context, index) {
        // "Load More" footer
        if (index == filtered.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _loadingUsers
                ? const Center(child: CircularProgressIndicator())
                : OutlinedButton.icon(
                    onPressed: _loadUsersPage,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text("טען 50 משתמשים נוספים"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
          );
        }
        var data = filtered[index].data() as Map<String, dynamic>;
        String uid = filtered[index].id;
        bool isVerified         = data['isVerified']         ?? false;
        bool isPromoted         = data['isPromoted']         ?? false;
        bool isOnline           = data['isOnline']           ?? false;
        bool isProvider         = data['isProvider']         ?? false;
        bool isVerifiedProvider = data['isVerifiedProvider'] ?? true; // default true = legacy users unaffected
        final compliance        = data['compliance']         as Map<String, dynamic>?;
        final docUrl            = compliance?['docUrl']      as String?;
        final taxStatus         = compliance?['taxStatus']   as String?;
        DateTime joinDate = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        // Pending compliance badge — shown when provider hasn't been approved yet
        final hasPendingCompliance = isProvider && !isVerifiedProvider && docUrl != null;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: hasPendingCompliance
                  ? Colors.orange.shade300
                  : Colors.grey.shade100,
              width: hasPendingCompliance ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Compliance alert banner (provider pending) ──────────────
              if (hasPendingCompliance)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ממתין לאימות מסמך מס — ${taxStatus == 'business' ? 'עוסק רשום' : 'חשבונית לשכיר'}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange),
                        ),
                      ),
                      GestureDetector(
                          onTap: () => _openDocumentUrl(docUrl),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_open_rounded,
                                    size: 13, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text('צפה במסמך',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange)),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // One-tap approve button
                      GestureDetector(
                        onTap: () {
                          FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .update({'isVerifiedProvider': true});
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('${data['name'] ?? ''} אומת — גישה לעבודות אופשרה ✓'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_user_rounded,
                                  size: 13, color: Colors.green),
                              const SizedBox(width: 4),
                              const Text('אשר',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              ListTile(
            onLongPress: () => _showUserActions(uid, data),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: (data['profileImage'] != null && data['profileImage'] != "") ? NetworkImage(data['profileImage']) : null,
                  child: data['profileImage'] == null ? const Icon(Icons.person) : null,
                ),
                Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: isOnline ? Colors.green : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
              ],
            ),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(data['name'] ?? "משתמש", style: const TextStyle(fontWeight: FontWeight.bold)),
                if (isVerified) const Icon(Icons.verified, color: Colors.blue, size: 16),
                if (isProvider && isVerifiedProvider)
                  const Tooltip(
                    message: 'מס אומת',
                    child: Icon(Icons.shield_rounded, color: Colors.green, size: 14),
                  ),
                if (isProvider && !isVerifiedProvider && docUrl == null)
                  const Tooltip(
                    message: 'מסמך מס חסר',
                    child: Icon(Icons.shield_outlined, color: Colors.red, size: 14),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['email'] ?? "", style: const TextStyle(fontSize: 12)),
                // ── Phone — tappable tel: link ─────────────────────────
                Builder(builder: (context) {
                  final phone = ((data['phone'] as String?) ?? (data['phoneNumber'] as String?) ?? '').trim();
                  if (phone.isEmpty) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => launchUrl(Uri.parse('tel:$phone')),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone_rounded, size: 12, color: Colors.green),
                        const SizedBox(width: 3),
                        Text(phone,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.green,
                            )),
                      ],
                    ),
                  );
                }),
                Text("יתרה: ₪${(data['balance'] ?? 0.0).toStringAsFixed(2)} | וותק: ${_calculateSeniority(joinDate)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                // ── Category label + action buttons (providers only) ──
                if (isProvider) ...[
                  const SizedBox(height: 4),
                  // Row 1: category label (full width, wraps naturally)
                  Builder(builder: (_) {
                    final cat      = (data['serviceType'] as String? ?? '').trim();
                    final sub      = (data['subCategory']  as String? ?? '').trim();
                    final reviewed = data['categoryReviewedByAdmin'] as bool? ?? false;
                    return Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(Icons.category_rounded,
                            size: 11,
                            color: reviewed ? Colors.indigo : Colors.orange),
                        Text(
                          cat.isEmpty
                              ? 'ללא קטגוריה'
                              : sub.isEmpty ? cat : '$cat › $sub',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: reviewed ? Colors.indigo : Colors.orange,
                          ),
                        ),
                        if (!reviewed)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.orange.shade300, width: 0.8),
                            ),
                            child: const Text('AI Suggested',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: 4),
                  // Row 2: action buttons in Wrap — stacks safely on small screens
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Edit Classification
                      GestureDetector(
                        onTap: () => _showEditClassificationDialog(
                            uid,
                            data['serviceType'] as String? ?? '',
                            data['subCategory']  as String? ?? '',
                            data['name']         as String? ?? 'ספק'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF6366F1), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded,
                                  size: 11, color: Color(0xFF6366F1)),
                              SizedBox(width: 3),
                              Text('ערוך סיווג',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6366F1),
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      // Quick Approve — only for unapproved providers.
                      // _approvedUids provides instant local hiding after CF success.
                      if (!_approvedUids.contains(uid) &&
                          ((data['isPendingExpert'] == true) ||
                           (isProvider && data['isApprovedProvider'] != true)))
                        GestureDetector(
                          onTap: _verifyingUids.contains(uid)
                              ? null
                              : () => _approveExpertApplication(
                                    context,
                                    uid,
                                    data['name']        as String? ?? 'ספק',
                                    data['email']       as String? ?? '',
                                    data['serviceType'] as String? ?? '',
                                  ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.purple.shade300, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _verifyingUids.contains(uid)
                                    ? const SizedBox(
                                        width: 11,
                                        height: 11,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: Colors.purple),
                                      )
                                    : const Icon(Icons.verified_rounded,
                                        size: 11, color: Colors.purple),
                                const SizedBox(width: 3),
                                Text('אשר',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.purple.shade700,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Verification badge quick-toggle ──────────────────
                GestureDetector(
                  onTap: () {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .update({'isVerified': !isVerified});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isVerified
                          ? "אימות הוסר מ-${data['name'] ?? ''}"
                          : "${data['name'] ?? ''} אומת ✓"),
                      backgroundColor:
                          isVerified ? Colors.orange : Colors.blue,
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  child: Tooltip(
                    message: isVerified ? "בטל אימות" : "אמת מומחה",
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: isVerified
                            ? Colors.blue.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isVerified
                                ? Colors.blue.shade300
                                : Colors.grey.shade300),
                      ),
                      child: Icon(
                        isVerified
                            ? Icons.verified
                            : Icons.verified_outlined,
                        color: isVerified ? Colors.blue : Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // ── Promote toggle ────────────────────────────────────
                GestureDetector(
                  onTap: () {
                    FirebaseFirestore.instance.collection('users').doc(uid)
                        .update({'isPromoted': !isPromoted});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isPromoted
                          ? "קידום הוסר מ-${data['name'] ?? ''}"
                          : "${data['name'] ?? ''} קודם ⭐"),
                      backgroundColor: isPromoted ? Colors.grey : Colors.amber[700],
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  child: Tooltip(
                    message: isPromoted ? "בטל קידום" : "קדם ספק",
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: isPromoted ? Colors.amber.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isPromoted ? Colors.amber.shade400 : Colors.grey.shade300),
                      ),
                      child: Icon(
                        isPromoted ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isPromoted ? Colors.amber[700] : Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // ── Wallet top-up ─────────────────────────────────────
                IconButton(
                  icon: const Icon(Icons.add_card, color: Colors.green),
                  onPressed: () =>
                      _showAddBalanceDialog(uid, data['name'] ?? 'משתמש'),
                ),
              ],
            ),
          ),           // closes ListTile
          ],           // closes Column.children
        ),             // closes Column
        );             // closes Card
      },
    );
  }

  /// Opens a document URL in a new browser tab (web only).
  void _openDocumentUrl(String? url) {
    if (url == null) return;
    openUrl(url);
  }

  // ── Monetization Tab ─────────────────────────────────────────────────────

  Widget _buildMonetizationTab() {

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Global Commission % ───────────────────────────────────────
          _monoCard(
            icon: Icons.percent_rounded,
            color: const Color(0xFF6366F1),
            title: "עמלת פלטפורמה גלובלית",
            child: _settingsLoaded
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${_feePct.toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6366F1))),
                          const Text("מכל עסקה (ברירת מחדל)",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF6366F1),
                          thumbColor: const Color(0xFF6366F1),
                          inactiveTrackColor: Colors.grey[200],
                          overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _feePct,
                          min: 0,
                          max: 30,
                          divisions: 30,
                          onChanged: (v) => setState(() => _feePct = v),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("0%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("30%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "ניתן לדרוס לספקים ספציפיים דרך רשימת הספקים ← עמלה מותאמת",
                          style: TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),

          // ── Urgency Fee ───────────────────────────────────────────────
          _monoCard(
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFEA580C),
            title: "תוספת דחיפות (בקשות דחופות)",
            child: _settingsLoaded
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("+${_urgencyFeePct.toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEA580C))),
                          const Text("על בקשות דחופות",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFEA580C),
                          thumbColor: const Color(0xFFEA580C),
                          inactiveTrackColor: Colors.grey[200],
                          overlayColor:
                              const Color(0xFFEA580C).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _urgencyFeePct,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          onChanged: (v) => setState(() => _urgencyFeePct = v),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("0%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("20%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),

          // ── Save button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text("שמור הגדרות",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _saveAdminSettings,
            ),
          ),
          const SizedBox(height: 22),

          // ── Promoted Providers ────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isPromoted', isEqualTo: true)
                .limit(100)
                .snapshots(),
            builder: (ctx, snap) {
              final promotedUsers = snap.data?.docs ?? [];
              return _monoCard(
                icon: Icons.star_rounded,
                color: Colors.amber[700]!,
                title: "ספקים מקודמים (${promotedUsers.length})",
                child: promotedUsers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("אין ספקים מקודמים כרגע",
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      )
                    : Column(
                        children: promotedUsers.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundImage: (d['profileImage'] != null &&
                                      d['profileImage'] != '')
                                  ? NetworkImage(d['profileImage'])
                                  : null,
                              child: d['profileImage'] == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(d['name'] ?? '—',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(d['serviceType'] ?? d['email'] ?? '',
                                style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 22),
                              tooltip: "בטל קידום",
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(doc.id)
                                    .update({'isPromoted': false});
                              },
                            ),
                          );
                        }).toList(),
                      ),
              );
            },
          ),
          const SizedBox(height: 22),

          // ── Monthly Earnings Chart ────────────────────────────────────
          _monoCard(
            icon: Icons.bar_chart_rounded,
            color: Colors.green[700]!,
            title: "עמלות החודש",
            child: _buildEarningsChart(),
          ),
          const SizedBox(height: 22),

          // ── Escrow Commissions (pending jobs) ─────────────────────────
          _monoCard(
            icon: Icons.lock_clock_rounded,
            color: Colors.orange[700]!,
            title: "עמלות בהמתנה (Escrow)",
            child: _buildEscrowSection(),
          ),
          const SizedBox(height: 22),

          // ── CSV Export ────────────────────────────────────────────────
          _monoCard(
            icon: Icons.download_rounded,
            color: Colors.teal[700]!,
            title: "ייצוא לרואה חשבון",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "הורד את כל תנועות הארנק כקובץ CSV מוכן לפתיחה ב-Excel.",
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text("ייצא עסקאות ל-CSV",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: _exportTransactionsCsv,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _monoCard({
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

  // ── Escrow section: live list of jobs in paid_escrow ─────────────────────
  Widget _buildEscrowSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'paid_escrow')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs;
        double total = 0;
        for (final d in docs) {
          total += (((d.data() as Map<String, dynamic>)['totalAmount']) as num? ?? 0).toDouble();
        }

        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text("אין עסקאות בהמתנה כרגע",
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Total badge ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${docs.length} עסקאות",
                      style: TextStyle(color: Colors.orange[700], fontSize: 13)),
                  Text("סה״כ: ₪${total.toStringAsFixed(0)}",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                          fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── Per-job rows ─────────────────────────────────────────────
            ...docs.map((doc) {
              final j    = doc.data() as Map<String, dynamic>;
              final amt  = ((j['totalAmount']) as num? ?? 0).toDouble();
              final expert   = j['expertName']   as String? ?? '—';
              final customer = j['customerName'] as String? ?? '—';
              final ts   = (j['createdAt'] as Timestamp?)?.toDate();
              final date = ts != null ? DateFormat('dd/MM HH:mm').format(ts) : '—';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(
                  children: [
                    Text("₪${amt.toStringAsFixed(0)}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("$customer ← $expert",
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.right),
                          Text(date,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.hourglass_top_rounded,
                        size: 16, color: Colors.orange[400]),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildEarningsChart() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('platform_earnings')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .orderBy('timestamp')
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ));
        }

        // Group by day-of-month
        final Map<int, double> byDay = {};
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final ts = (d['timestamp'] as Timestamp?)?.toDate();
          if (ts == null) continue;
          final fee = ((d['platformFee'] ?? d['amount'] ?? 0) as num).toDouble();
          byDay[ts.day] = (byDay[ts.day] ?? 0) + fee;
        }

        final total = byDay.values.fold(0.0, (a, b) => a + b);
        final maxVal = byDay.values.fold(0.0, (a, b) => a > b ? a : b);

        if (byDay.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text("אין עמלות החודש עדיין",
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Total badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text("סה״כ החודש: ₪${total.toStringAsFixed(0)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                      fontSize: 15)),
            ),
            const SizedBox(height: 16),
            // Bar chart
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(daysInMonth, (i) {
                  final day = i + 1;
                  final val = byDay[day] ?? 0;
                  final frac = maxVal > 0 ? val / maxVal : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (val > 0)
                            Tooltip(
                              message: "יום $day: ₪${val.toStringAsFixed(0)}",
                              child: Container(
                                height: (frac * 85).clamp(3.0, 85.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            )
                          else
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          const SizedBox(height: 2),
                          if (day % 7 == 1 || day == daysInMonth)
                            Text("$day",
                                style: TextStyle(
                                    fontSize: 7, color: Colors.grey[500]))
                          else
                            const SizedBox(height: 9),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Insights & Analytics Tab ──────────────────────────────────────────────

  Widget _buildInsightsTab() {
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

          // ── User Activity (DAU from parent stream, unanswered from own stream) ──
          _monoCard(
            icon: Icons.people_alt_rounded,
            color: Colors.purple,
            title: "פעילות משתמשים",
            child: Row(
              children: [
                Expanded(child: _insightsMiniCard(
                    'פעילים היום (DAU)',
                    _insDauLoaded ? dau.toString() : '…',
                    Colors.purple)),
                const SizedBox(width: 10),
                Expanded(child: _insightsMiniCard(
                    'בקשות ללא מענה',
                    _insUnanswLoaded ? _insUnanswered.toString() : '…',
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
              final providers = _users
                  .map((d) => d.data() as Map<String, dynamic>)
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
                  "יהיה זמין בקרוב 🚀",
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
                _SyncPhonesButton(),
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

  Widget _pulseTile({
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

  Widget _speedBar(String label, double hours, Color color, double max) {
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

  Widget _chartLegendDot({required Color color, required String label}) =>
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

  Widget _applicationChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _insightsMiniCard(String label, String value, Color color) {
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

  String _fmtNum(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  // ── ID Verification Tab ────────────────────────────────────────────────────
  Widget _buildIdVerificationTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hint icon (admin-controlled help) ───────────────────────────
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: HintIcon(screenKey: 'identity_verification'),
          ),

          // ── Expert Applications ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text('🚀', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                const Text('בקשות הצטרפות כמומחים',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Stream A: classic pending applications (isPendingExpert == true)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isPendingExpert', isEqualTo: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapA) {
              // Stream B: providers with isApprovedProvider explicitly = false
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('isProvider', isEqualTo: true)
                    .where('isApprovedProvider', isEqualTo: false)
                    .limit(50)
                    .snapshots(),
                builder: (context, snapB) {
                  // Stream C: providers whose isApprovedProvider field is ABSENT
                  // (e.g. legacy providers approved via old code that never set the flag).
                  // We query isProvider==true without the flag and filter client-side.
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('isProvider', isEqualTo: true)
                        .limit(50)
                        .snapshots(),
                    builder: (context, snapC) {
                      if (!snapA.hasData && !snapB.hasData && !snapC.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      // Stream C: keep only docs where isApprovedProvider is NOT true
                      final cDocs = (snapC.data?.docs ?? []).where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        // include only providers not yet explicitly approved
                        return data['isApprovedProvider'] != true;
                      }).toList();

                      // Merge A + B + C, deduplicate by document ID
                      final seenIds = <String>{};
                      final docs = <DocumentSnapshot>[
                        ...?snapA.data?.docs,
                        ...?snapB.data?.docs,
                        ...cDocs,
                      ].where((d) => seenIds.add(d.id)).toList();

                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text('אין בקשות ממתינות',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[500])),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) =>
                            _buildExpertApplicationCard(ctx, docs[i]),
                      );
                    },
                  );
                },
              );
            },
          ),

          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 8),

          // ── ID Verification ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Text('🪪', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                const Text('אימות זהות',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('idVerificationStatus', isEqualTo: 'pending')
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text('אין ספקים הממתינים לאימות',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500])),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) =>
                    _buildIdVerificationCard(ctx, docs[i]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExpertApplicationCard(
      BuildContext context, DocumentSnapshot doc) {
    final data    = doc.data() as Map<String, dynamic>;
    final uid     = doc.id;
    final name    = data['name']  as String? ?? 'ללא שם';
    final email   = data['email'] as String? ?? '';
    final photo   = data['profileImage'] as String?;
    final appData = data['expertApplicationData'] as Map<String, dynamic>? ?? {};
    // Fall back to top-level fields for providers who bypassed the pending flow
    final category   = (appData['category']    as String? ?? data['serviceType']   as String? ?? '').trim();
    final subCat     = (appData['subCategory']  as String? ?? data['subCategory']   as String? ?? '').trim();
    final aboutMe    = (appData['aboutMe']      as String? ?? data['aboutMe']       as String? ?? '').trim();
    final taxId      = (appData['taxId']        as String? ?? '').trim();
    final price      = (appData['pricePerHour'] as num?    ?? data['pricePerHour']  as num?    ?? 0).toDouble();
    final phone      = ((data['phone'] as String?) ?? (data['phoneNumber'] as String?) ?? '').trim();
    final isPending  = data['isPendingExpert'] as bool? ?? false;

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── User info row ─────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.purple.shade50,
                  backgroundImage: (photo != null && photo.isNotEmpty)
                      ? NetworkImage(photo)
                      : null,
                  child: (photo == null || photo.isEmpty)
                      ? Text(
                          name.isNotEmpty ? name[0] : '?',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (email.isNotEmpty)
                        Text(email,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      if (phone.isNotEmpty)
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse('tel:$phone')),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.phone_rounded,
                                  size: 11, color: Colors.green),
                              const SizedBox(width: 3),
                              Text(phone,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.green)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Status badge — purple for pending application, amber for bypassed provider
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.purple.shade50
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isPending
                            ? Colors.purple.shade200
                            : Colors.amber.shade400),
                  ),
                  child: Text(
                    isPending ? 'ממתין לאישור' : 'ספק לא מאושר',
                    style: TextStyle(
                        fontSize: 11,
                        color: isPending ? Colors.purple : Colors.amber[800],
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            // ── Service details ───────────────────────────────────────────
            if (category.isNotEmpty || subCat.isNotEmpty || price > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (category.isNotEmpty)
                    _applicationChip(
                      subCat.isEmpty ? category : '$category › $subCat',
                      Icons.category_rounded,
                      Colors.indigo,
                    ),
                  if (price > 0)
                    _applicationChip(
                      '₪${price.toStringAsFixed(0)} / יחידה',
                      Icons.attach_money_rounded,
                      Colors.green,
                    ),
                  if (taxId.isNotEmpty)
                    _applicationChip(taxId, Icons.badge_outlined, Colors.grey),
                ],
              ),
            ],
            if (aboutMe.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(aboutMe,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5, height: 1.5)),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _rejectExpertApplication(
                          context, uid, name),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.red),
                  label:
                      const Text('דחה', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _approveExpertApplication(
                          context, uid, name, email, category),
                  icon: _verifyingUids.contains(uid)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.verified_rounded,
                          size: 16, color: Colors.white),
                  label: const Text('אשר כספק מומחה',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdVerificationCard(
      BuildContext context, DocumentSnapshot doc) {
    final data  = doc.data() as Map<String, dynamic>;
    final uid   = doc.id;
    final name  = data['name']  as String? ?? 'ללא שם';
    final email = data['email'] as String? ?? '';
    final idUrl = data['idVerificationUrl'] as String?;

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // User info row
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.indigo.shade50,
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(email,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text('ממתין',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            // ID photo
            if (idUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: idUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    height: 80,
                    color: Colors.grey.shade100,
                    child: const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey)),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('לא הועלתה תמונת מסמך',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _rejectVerification(
                          context, uid, name, email),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.red),
                  label:
                      const Text('דחה', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _approveVerification(
                          context, uid, name, email),
                  icon: _verifyingUids.contains(uid)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white),
                  label: const Text('אמת',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveVerification(
      BuildContext context, String uid, String name, String email) async {
    if (_verifyingUids.contains(uid)) return;
    setState(() => _verifyingUids.add(uid));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('approveUserVerification',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call({'uid': uid, 'action': 'approve', 'email': email, 'name': name});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $name אומת/ה בהצלחה — אימייל נשלח'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה באישור: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  Future<void> _rejectVerification(
      BuildContext context, String uid, String name, String email) async {
    if (_verifyingUids.contains(uid)) return;
    // Confirm before rejecting
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור דחייה'),
        content: Text('לדחות את הבקשה של $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('דחה', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _verifyingUids.add(uid));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('approveUserVerification',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call({'uid': uid, 'action': 'reject', 'email': email, 'name': name});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name נדחה/ה — אימייל נשלח'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בדחייה: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  Future<void> _approveExpertApplication(BuildContext context, String uid,
      String name, String email, String category) async {
    if (_verifyingUids.contains(uid)) return;
    setState(() => _verifyingUids.add(uid));
    try {
      // Use Cloud Function — Admin SDK bypasses client-side security rules,
      // so the notifications write (allow create: if false) succeeds.
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
      await fn.httpsCallable('adminApproveProvider').call({
        'uid':      uid,
        'name':     name,
        'category': category,
      });

      // Mark as approved locally — hides the Approve button immediately,
      // independent of when the paginated _users list next reloads.
      if (mounted) setState(() => _approvedUids.add(uid));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $name אושר/ה כספק מומחה — התראה נשלחה'),
          backgroundColor: Colors.purple.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה באישור: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  Future<void> _rejectExpertApplication(
      BuildContext context, String uid, String name) async {
    if (_verifyingUids.contains(uid)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור דחייה'),
        content: Text('לדחות את הבקשה של $name?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('דחה', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _verifyingUids.add(uid));
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isPendingExpert':    false,
        'expertApplicationData': FieldValue.delete(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name — הבקשה נדחתה'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בדחייה: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  // ── Support Intervention Tab — admin views active/disputed jobs + chat ───────
  Widget _buildSupportTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', whereIn: ['paid_escrow', 'disputed', 'expert_completed'])
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('אין עבודות פעילות כרגע',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d          = docs[i].data()! as Map<String, dynamic>;
            final status     = d['status'] as String? ?? '';
            final amount     = (d['totalAmount'] as num? ?? 0).toDouble();
            final expertId   = d['expertId']   as String? ?? '';
            final customerId = d['customerId'] as String? ?? '';
            final expertName   = d['expertName']   as String? ?? expertId;
            final customerName = d['customerName'] as String? ?? customerId;

            // Derive chatRoomId: sorted UIDs joined by '_' (same as app logic)
            final ids = [expertId, customerId]..sort();
            final chatRoomId = ids.join('_');

            final isDisputed  = status == 'disputed';
            final statusColor = isDisputed
                ? Colors.red
                : status == 'paid_escrow'
                    ? const Color(0xFF10B981)
                    : Colors.orange;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDisputed
                        ? Colors.red.shade100
                        : Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '₪${amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.build_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(expertName,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 16),
                      const Icon(Icons.person_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(customerName,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDisputed
                            ? Colors.red
                            : const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_rounded,
                          color: Colors.white, size: 16),
                      label: const Text("צפה בצ'אט",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminChatViewScreen(
                            chatRoomId:   chatRoomId,
                            providerName: expertName,
                            customerName: customerName,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoVerificationTab() => const _VideoVerificationTabContent();
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
            '✅ עודכנו ${data['updated'] ?? 0} משתמשים מתוך ${data['scanned'] ?? 0}';
      });
    } catch (e) {
      setState(() {
        _syncing = false;
        _result = '❌ שגיאה: $e';
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
              color: _result.startsWith('✅') ? Colors.teal : Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ── Video Verification Admin Tab ──────────────────────────────────────────────
// Fetches all users with a verificationVideoUrl that hasn't yet been approved.
class _VideoVerificationTabContent extends StatelessWidget {
  const _VideoVerificationTabContent();

  Future<void> _approve(BuildContext context, String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'videoVerifiedByAdmin': true,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ הסרטון אושר — יופיע בפרופיל המומחה'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _reject(BuildContext context, String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'verificationVideoUrl': FieldValue.delete(),
      'videoVerifiedByAdmin': false,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🗑️ הסרטון נדחה והוסר'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('isProvider', isEqualTo: true)
          .limit(200)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = (snap.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>;
          final url  = data['verificationVideoUrl'] as String?;
          final approved = data['videoVerifiedByAdmin'] as bool? ?? false;
          return url != null && url.isNotEmpty && !approved;
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_rounded, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text('אין סרטוני אימות ממתינים',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc  = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final uid  = doc.id;
            final name = data['name'] as String? ?? uid;
            final videoUrl = data['verificationVideoUrl'] as String;
            final serviceType = data['serviceType'] as String? ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15)),
                              if (serviceType.isNotEmpty)
                                Text(serviceType,
                                    style: const TextStyle(
                                        fontSize: 13, color: Color(0xFF6366F1))),
                              Text(uid,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Text('ממתין לאישור',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(videoUrl);
                              if (uri != null) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.play_circle_outline_rounded,
                                size: 18),
                            label: const Text('צפה בסרטון'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6366F1),
                              side: const BorderSide(color: Color(0xFF6366F1)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _approve(context, uid),
                            icon: const Icon(Icons.check_circle_outline_rounded,
                                size: 18),
                            label: const Text('אשר סרטון'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _reject(context, uid),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          tooltip: 'דחה וסלק',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}