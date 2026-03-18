import 'dart:async';
import 'package:flutter/material.dart';
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
import 'admin_chat_view_screen.dart';


class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _searchQuery = "";
  double _feePct        = 10.0;
  double _urgencyFeePct = 5.0;
  bool   _settingsLoaded = false;
  bool   _refreshingImages   = false;
  bool   _fixingImages       = false;
  bool   _resettingCounters  = false;

  // ── ID verification — tracks which UIDs are mid-request (prevents double-tap)
  final Set<String> _verifyingUids = {};
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

  @override
  void initState() {
    super.initState();
    _syncAppVersion();
    _loadAdminSettings();
    _setupInsightsStreams();
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

    // Reset loaded flags so UI shows a brief spinner while first snapshots arrive
    if (mounted) {
      setState(() {
        _insGmvLoaded     = false;
        _insNetRevLoaded  = false;
        _insEscrowLoaded  = false;
        _insTxLoaded      = false;
        _insUnanswLoaded  = false;
        _insBannersLoaded = false;
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
    return DefaultTabController(
      length: 17,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("Control Center", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          actions: [
            IconButton(icon: const Icon(Icons.campaign_rounded, color: Colors.blueAccent, size: 30), onPressed: _showBroadcastDialog),
            const SizedBox(width: 10),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.blueAccent,
            indicatorColor: Colors.blueAccent,
            tabs: [Tab(text: "הכל"), Tab(text: "לקוחות"), Tab(text: "ספקים"), Tab(text: "חסומים"), Tab(text: "מחלוקות 🔴"), Tab(text: "משיכות 💸"), Tab(text: "קטגוריות 🏷️"), Tab(text: "באנרים 🎨"), Tab(text: "מוניטיזציה 💰"), Tab(text: "תובנות 📊"), Tab(text: "בינה עסקית 🧠"), Tab(text: "XP & רמות 🎮"), Tab(text: "ביצועים 🖥️"), Tab(text: "אימות זהות 🪪"), Tab(text: "משפך הרשמה 📈"), Tab(text: "לייב פיד 📡"), Tab(text: "צ'אטים 💬")],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').limit(500).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            var allUsers = snapshot.data!.docs;

            int customers = allUsers.where((d) => (d.data() as Map)['isCustomer'] == true).length;
            int providers = allUsers.where((d) => (d.data() as Map)['isProvider'] == true).length;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: "חפש שם, מייל או מזהה...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
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
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildList(allUsers),
                      _buildList(allUsers.where((d) => (d.data() as Map)['isCustomer'] == true).toList()),
                      _buildList(allUsers.where((d) => (d.data() as Map)['isProvider'] == true).toList()),
                      _buildList(allUsers.where((d) => (d.data() as Map)['isBanned'] == true).toList()),
                      const DisputeResolutionScreen(),
                      _buildWithdrawalsList(),
                      _buildCategoriesTab(),
                      _buildBannersTab(),
                      _buildMonetizationTab(allUsers),
                      _buildInsightsTab(allUsers),
                      const BusinessAiScreen(),
                      const XpManagerScreen(),
                      const SystemPerformanceTab(),
                      _buildIdVerificationTab(),
                      const RegistrationFunnelTab(),
                      const LiveActivityTab(),
                      _buildSupportTab(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
      itemCount: filtered.length,
      itemBuilder: (context, index) {
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
            title: Row(
              children: [
                Text(data['name'] ?? "משתמש", style: const TextStyle(fontWeight: FontWeight.bold)),
                if (isVerified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified, color: Colors.blue, size: 16)),
                // Provider compliance status icon
                if (isProvider && isVerifiedProvider)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: 'מס אומת',
                      child: Icon(Icons.shield_rounded, color: Colors.green, size: 14),
                    ),
                  ),
                if (isProvider && !isVerifiedProvider && docUrl == null)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: 'מסמך מס חסר',
                      child: Icon(Icons.shield_outlined, color: Colors.red, size: 14),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['email'] ?? "", style: const TextStyle(fontSize: 12)),
                Text("יתרה: ₪${(data['balance'] ?? 0.0).toStringAsFixed(2)} | וותק: ${_calculateSeniority(joinDate)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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

  // ── Banners Management ────────────────────────────────────────────────────

  static const _iconOptions = [
    'stars', 'school', 'emoji_events', 'favorite', 'bolt',
    'local_offer', 'rocket_launch', 'workspace_premium', 'celebration', 'trending_up',
  ];
  static const _iconLabels = {
    'stars': Icons.stars_rounded,
    'school': Icons.school_rounded,
    'emoji_events': Icons.emoji_events_rounded,
    'favorite': Icons.favorite_rounded,
    'bolt': Icons.bolt_rounded,
    'local_offer': Icons.local_offer_rounded,
    'rocket_launch': Icons.rocket_launch_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'celebration': Icons.celebration_rounded,
    'trending_up': Icons.trending_up_rounded,
  };

  Widget _buildBannersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text("הוסף באנר", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: () => _showBannerDialog(existingCount: docs.length),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text("Seed ברירת מחדל"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: docs.isNotEmpty ? null : _seedDefaultBanners,
                  ),
                ],
              ),
            ),
            if (!snapshot.hasData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (docs.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("אין באנרים — לחץ 'Seed ברירת מחדל' או 'הוסף באנר'",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                ),
              )
            else
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = [...docs];
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    final batch = FirebaseFirestore.instance.batch();
                    for (int i = 0; i < reordered.length; i++) {
                      batch.update(reordered[i].reference, {'order': i});
                    }
                    await batch.commit();
                  },
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isActive   = data['isActive'] as bool? ?? true;
                    final iconName   = data['iconName']  as String? ?? 'stars';
                    final color1Hex  = data['color1']    as String? ?? '667eea';
                    final expiresAt  = (data['expiresAt'] as Timestamp?)?.toDate();
                    final now        = DateTime.now();
                    final isExpired  = expiresAt != null && expiresAt.isBefore(now);
                    final expiresSoon = expiresAt != null && !isExpired &&
                        expiresAt.isBefore(now.add(const Duration(days: 7)));

                    return Card(
                      key: ValueKey(doc.id),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _hexToAdminColor(color1Hex),
                                    _hexToAdminColor(data['color2'] as String? ?? '764ba2'),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_iconLabels[iconName] ?? Icons.stars_rounded,
                                  color: Colors.white, size: 22),
                            ),
                            title: Text(data['title'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(data['subtitle'] as String? ?? '',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: isActive,
                                  activeColor: Colors.green,
                                  onChanged: (val) => doc.reference.update({'isActive': val}),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                                  onPressed: () => _showBannerDialog(doc: doc, data: data),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _confirmDeleteBanner(doc.id),
                                ),
                              ],
                            ),
                          ),
                          // Expiry status chip
                          if (expiresAt != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isExpired ? Icons.event_busy_rounded : Icons.schedule_rounded,
                                    size: 13,
                                    color: isExpired
                                        ? Colors.red[700]
                                        : expiresSoon
                                            ? Colors.orange[700]
                                            : Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isExpired
                                        ? 'פג תוקף — ${DateFormat('dd/MM/yyyy').format(expiresAt)}'
                                        : 'פג תוקף ב-${DateFormat('dd/MM/yyyy').format(expiresAt)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: expiresSoon || isExpired
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isExpired
                                          ? Colors.red[700]
                                          : expiresSoon
                                              ? Colors.orange[700]
                                              : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Featured provider chip (shown when providerId is set)
                          if ((data['providerId'] as String?) != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.amber.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundImage: ((data['providerPhoto'] as String?) ?? '').isNotEmpty
                                          ? NetworkImage(data['providerPhoto'] as String)
                                          : null,
                                      backgroundColor: Colors.amber.shade200,
                                      child: ((data['providerPhoto'] as String?) ?? '').isEmpty
                                          ? Text(
                                              ((data['providerName'] as String?) ?? '?')[0].toUpperCase(),
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.workspace_premium_rounded,
                                        size: 14, color: Colors.amber.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      data['providerName'] as String? ?? 'ספק מקודם',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.amber.shade900),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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

  static Color _hexToAdminColor(String hex) {
    final clean = hex.replaceAll('#', '').replaceAll('0x', '');
    final padded = clean.length == 6 ? 'FF$clean' : clean;
    return Color(int.parse(padded, radix: 16));
  }

  Future<void> _seedDefaultBanners() async {
    final defaults = [
      {'title': 'מצא מומחים מובילים', 'subtitle': 'אלפי מומחים מחכים לך',       'color1': '667eea', 'color2': '764ba2', 'iconName': 'stars',         'order': 0, 'isActive': true},
      {'title': 'שיעורים פרטיים',      'subtitle': 'ממש מהמקום שאתה נמצא',     'color1': '11998e', 'color2': '38ef7d', 'iconName': 'school',        'order': 1, 'isActive': true},
      {'title': 'פתח את הפוטנציאל שלך','subtitle': 'עם המומחים הטובים ביותר', 'color1': 'f953c6', 'color2': 'b91d73', 'iconName': 'emoji_events', 'order': 2, 'isActive': true},
    ];
    final batch = FirebaseFirestore.instance.batch();
    for (final b in defaults) {
      batch.set(FirebaseFirestore.instance.collection('banners').doc(), b);
    }
    await batch.commit();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("3 באנרי ברירת מחדל נוצרו")));
  }

  void _showBannerDialog({QueryDocumentSnapshot? doc, Map<String, dynamic>? data, int existingCount = 0}) {
    final titleCtrl      = TextEditingController(text: data?['title']    as String? ?? '');
    final subtitleCtrl   = TextEditingController(text: data?['subtitle'] as String? ?? '');
    final color1Ctrl     = TextEditingController(text: data?['color1']   as String? ?? '667eea');
    final color2Ctrl     = TextEditingController(text: data?['color2']   as String? ?? '764ba2');
    final provSearchCtrl = TextEditingController();
    String selectedIcon = data?['iconName'] as String? ?? 'stars';
    bool   isActive     = data?['isActive'] as bool? ?? true;

    // Provider link state
    String? linkedProviderId    = data?['providerId']    as String?;
    String? linkedProviderName  = data?['providerName']  as String?;
    String? linkedProviderPhoto = data?['providerPhoto'] as String?;

    // Expiration date state (null = never expires)
    DateTime? expiresAt = (data?['expiresAt'] as Timestamp?)?.toDate();

    // Provider search results shown inside the dialog
    List<QueryDocumentSnapshot> provResults = [];
    bool provSearching = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {

          Future<void> searchProviders(String query) async {
            if (query.trim().length < 2) {
              setDialogState(() { provResults = []; });
              return;
            }
            setDialogState(() => provSearching = true);
            final snap = await FirebaseFirestore.instance
                .collection('users')
                .where('isProvider', isEqualTo: true)
                .limit(20)
                .get();
            final lower = query.trim().toLowerCase();
            final filtered = snap.docs.where((d) {
              final n = ((d.data() as Map)['name'] as String? ?? '').toLowerCase();
              return n.contains(lower);
            }).toList();
            if (ctx.mounted) setDialogState(() { provResults = filtered; provSearching = false; });
          }

          return AlertDialog(
            title: Text(doc == null ? "באנר חדש" : "עריכת באנר",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(controller: titleCtrl,    textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "כותרת")),
                  const SizedBox(height: 10),
                  TextField(controller: subtitleCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "תת כותרת")),
                  const SizedBox(height: 10),
                  TextField(controller: color1Ctrl,   textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "צבע 1 (hex)", hintText: "667eea")),
                  const SizedBox(height: 10),
                  TextField(controller: color2Ctrl,   textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "צבע 2 (hex)", hintText: "764ba2")),
                  const SizedBox(height: 14),
                  const Align(alignment: Alignment.centerRight, child: Text("אייקון:", style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _iconOptions.map((name) {
                      final selected = name == selectedIcon;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedIcon = name),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selected ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? Colors.blueAccent : Colors.transparent, width: 2),
                          ),
                          child: Icon(_iconLabels[name], size: 22, color: selected ? Colors.blueAccent : Colors.grey[600]),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("פעיל"),
                      Switch(value: isActive, onChanged: (v) => setDialogState(() => isActive = v)),
                    ],
                  ),

                  // ── Expiration Date ──────────────────────────────────────
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Date picker button
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: expiresAt != null ? Colors.red[700] : Colors.blueAccent,
                          padding: EdgeInsets.zero,
                        ),
                        icon: Icon(
                          expiresAt != null ? Icons.event_busy_rounded : Icons.date_range_rounded,
                          size: 18,
                        ),
                        label: Text(
                          expiresAt != null
                              ? DateFormat('dd/MM/yyyy').format(expiresAt!)
                              : "בחר תאריך תפוגה",
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: expiresAt ?? DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                            helpText: 'תאריך תפוגת הבאנר',
                            confirmText: 'אשר',
                            cancelText: 'ביטול',
                          );
                          if (picked != null) setDialogState(() => expiresAt = picked);
                        },
                      ),
                      // Clear button
                      if (expiresAt != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                          tooltip: "ללא תפוגה",
                          onPressed: () => setDialogState(() => expiresAt = null),
                        ),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text("תאריך תפוגה", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),

                  // ── Featured Provider Section ─────────────────────────────
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text("ספק מקודם (Featured Provider)",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(height: 6),

                  // Currently linked provider chip
                  if (linkedProviderId != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundImage: (linkedProviderPhoto != null && linkedProviderPhoto!.isNotEmpty)
                                ? NetworkImage(linkedProviderPhoto!) : null,
                            child: (linkedProviderPhoto == null || linkedProviderPhoto!.isEmpty)
                                ? Text((linkedProviderName ?? '?')[0].toUpperCase()) : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(linkedProviderName ?? linkedProviderId!,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                            onPressed: () => setDialogState(() {
                              linkedProviderId   = null;
                              linkedProviderName = null;
                              linkedProviderPhoto = null;
                              provResults = [];
                              provSearchCtrl.clear();
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Search field
                  TextField(
                    controller: provSearchCtrl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: "חפש ספק לפי שם",
                      hintText: "הקלד שם...",
                      suffixIcon: provSearching
                          ? const SizedBox(width: 20, height: 20,
                              child: Padding(padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2)))
                          : const Icon(Icons.search),
                    ),
                    onChanged: (v) => searchProviders(v),
                  ),

                  // Search results list
                  if (provResults.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: provResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final pd = provResults[i].data() as Map<String, dynamic>;
                          final pName  = pd['name']         as String? ?? 'ללא שם';
                          final pPhoto = pd['profileImage'] as String? ?? '';
                          final pType  = pd['serviceType']  as String? ?? '';
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundImage: pPhoto.isNotEmpty ? NetworkImage(pPhoto) : null,
                              child: pPhoto.isEmpty ? Text(pName[0].toUpperCase()) : null,
                            ),
                            title: Text(pName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: pType.isNotEmpty ? Text(pType, style: const TextStyle(fontSize: 11)) : null,
                            onTap: () => setDialogState(() {
                              linkedProviderId   = provResults[i].id;
                              linkedProviderName = pName;
                              linkedProviderPhoto = pPhoto;
                              provResults = [];
                              provSearchCtrl.clear();
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                onPressed: () async {
                  final payload = <String, dynamic>{
                    'title':    titleCtrl.text.trim(),
                    'subtitle': subtitleCtrl.text.trim(),
                    'color1':   color1Ctrl.text.trim().replaceAll('#', ''),
                    'color2':   color2Ctrl.text.trim().replaceAll('#', ''),
                    'iconName': selectedIcon,
                    'isActive': isActive,
                    'order':    data?['order'] ?? existingCount,
                    // Provider link — null means "generic banner, no navigation"
                    'providerId':    linkedProviderId,
                    'providerName':  linkedProviderName,
                    'providerPhoto': linkedProviderPhoto,
                    // Monetization tracking: timestamp of when provider was linked
                    'providerLinkedAt': linkedProviderId != null ? FieldValue.serverTimestamp() : null,
                    // Expiration — null means the banner never expires
                    'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
                  };
                  if (doc == null) {
                    await FirebaseFirestore.instance.collection('banners').add(payload);
                  } else {
                    await doc.reference.update(payload);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(doc == null ? "הוסף" : "שמור",
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Monetization Tab ─────────────────────────────────────────────────────

  Widget _buildMonetizationTab(List<QueryDocumentSnapshot> allUsers) {
    final promotedUsers = allUsers
        .where((d) => (d.data() as Map<String, dynamic>)['isPromoted'] == true)
        .toList();

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
          _monoCard(
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
                          child:
                              d['profileImage'] == null ? const Icon(Icons.person) : null,
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

  Widget _buildInsightsTab(List<QueryDocumentSnapshot> allUsers) {
    // DAU: from allUsers stream (already live via parent StreamBuilder)
    // Try both field names for last-seen timestamp
    final now        = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final dau = allUsers.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final ts = ((data['lastOnlineAt'] ?? data['lastActive']) as Timestamp?)?.toDate();
      return ts != null && ts.isAfter(todayStart);
    }).length;

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
                    'פעילים היום (DAU)', dau.toString(), Colors.purple)),
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
                          final clicks   = b['clicks'] as int;
                          final maxClicks =
                              (_insBanners.first['clicks'] as int) < 1
                                  ? 1
                                  : _insBanners.first['clicks'] as int;
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

          // ── Top Rated Providers (from parent allUsers stream) ─────────
          _monoCard(
            icon: Icons.star_rounded,
            color: const Color(0xFFF59E0B),
            title: "ספקים מובילים",
            child: Builder(builder: (context) {
              final providers = allUsers
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

  void _confirmDeleteBanner(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחק באנר"),
        content: const Text("האם אתה בטוח? הפעולה אינה הפיכה."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('banners').doc(docId).delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("מחק", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── ID Verification Tab ────────────────────────────────────────────────────
  Widget _buildIdVerificationTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('idVerificationStatus', isEqualTo: 'pending')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text('אין ספקים הממתינים לאימות',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final uid  = docs[i].id;
            final name  = data['name']  as String? ?? 'ללא שם';
            final email = data['email'] as String? ?? '';
            final idUrl = data['idVerificationUrl'] as String?;

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
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
                            border: Border.all(
                                color: Colors.amber.shade300),
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
                        child: Image.network(
                          idUrl,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
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
                            style: TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Reject button
                        OutlinedButton.icon(
                          onPressed: _verifyingUids.contains(uid)
                              ? null
                              : () => _rejectVerification(context, uid, name, email),
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.red),
                          label: const Text('דחה',
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Approve button
                        ElevatedButton.icon(
                          onPressed: _verifyingUids.contains(uid)
                              ? null
                              : () => _approveVerification(context, uid, name, email),
                          icon: _verifyingUids.contains(uid)
                              ? const SizedBox(
                                  width: 14, height: 14,
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
          },
        );
      },
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
}