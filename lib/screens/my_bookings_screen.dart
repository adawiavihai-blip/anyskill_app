// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_modules/payment_module.dart';
import '../services/cancellation_policy_service.dart';
import '../widgets/customer_profile_sheet.dart';
import '../widgets/receipt_sheet.dart';
import '../l10n/app_localizations.dart';
import '../widgets/hint_icon.dart';
import 'expert_profile_screen.dart';
import 'chat_screen.dart';
import 'review_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const MyBookingsScreen({super.key, this.onGoToSearch});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _isProvider     = false;
  bool _providerLoaded = false;
  bool _tasksTimedOut  = false;  // true after 10s if stream still has no data
  Timer? _tasksTimeoutTimer;
  // Live subscription to the user doc — keeps _isProvider in sync in real-time.
  // A one-time get() could stay false if it raced with the first build, causing
  // Sigalit to see only customer tabs and never find her provider task list.
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Loading overlay controller ─────────────────────────────────────────────
  // We store the dialog's own BuildContext so we can ALWAYS pop exactly that
  // route — never accidentally popping a parent route.
  BuildContext? _loadingDialogCtx;

  void _showLoadingOverlay() {
    debugPrint('QA: Opening loading dialog');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _loadingDialogCtx = ctx;
        return const PopScope(
          canPop: false,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void _hideLoadingOverlay() {
    debugPrint('QA: Dismissing loading dialog');
    final ctx = _loadingDialogCtx;
    _loadingDialogCtx = null;
    if (ctx != null && ctx.mounted && Navigator.canPop(ctx)) {
      Navigator.of(ctx).pop();
    }
  }

  // ── Calendar / availability state ─────────────────────────────────────────
  Set<DateTime> _unavailableDates = {};
  DateTime _calendarFocusedDay = DateTime.now();
  DateTime? _selectedCalendarDay;
  bool _calendarSaving = false;

  // ── Stable streams ─────────────────────────────────────────────────────────
  late final Stream<QuerySnapshot> _expertStream;
  late final Stream<QuerySnapshot> _customerStream;

  // ── Status buckets ─────────────────────────────────────────────────────────
  // Active: jobs still in progress. History: terminal states only.
  static const _activeStatuses  = {
    'paid_escrow', 'expert_completed', 'disputed',
    'pending', 'accepted', 'in_progress',
    'awaiting_payment',
  };
  // History uses catch-all (!_activeStatuses) in _buildFilteredCustomerList,
  // but this set is kept for reference and potential direct use.
  static const _historyStatuses = {
    'completed', 'cancelled', 'refunded',
    'split_resolved', 'cancelled_with_penalty',
    'payment_failed',
  };

  @override
  void initState() {
    super.initState();
    // No orderBy — avoids composite index requirement.
    // Documents are sorted client-side in the list builders.
    // Limit raised to 200 to prevent "ghost" bookings where older jobs
    // silently fall off the 50-doc window and reappear on next stream event.
    // No orderBy — avoids composite index. Sorted client-side in builders.
    _expertStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('expertId', isEqualTo: currentUserId)
        .limit(200)
        .snapshots();
    _customerStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('customerId', isEqualTo: currentUserId)
        .limit(200)
        .snapshots();
    _subscribeProviderStatus();
    _loadUnavailableDates();
    // NOTE: timeout timer moved to _buildProviderTasksTab — it must start
    // when the StreamBuilder actually begins listening, not at initState
    // (where it races against the _providerLoaded fetch and may expire
    // before the tasks tab even renders).
  }

  @override
  void dispose() {
    _tasksTimeoutTimer?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  // Live subscription so _isProvider stays in sync even if the user doc
  // updates (e.g. admin grants provider status while the screen is open).
  // Replaces the old one-shot get() which could race with the first build
  // and leave _isProvider=false, hiding the provider tabs permanently.
  bool _isAdmin = false;

  void _subscribeProviderStatus() {
    if (currentUserId.isEmpty) {
      setState(() => _providerLoaded = true);
      return;
    }
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .snapshots()
        .listen(
      (doc) {
        if (!mounted) return;
        final data = doc.data() ?? {};
        final isProvider = data['isProvider'] == true;
        final isAdmin    = data['isAdmin']    == true;
        setState(() {
          // Admin sees CLIENT tabs by default (פעילות + היסטוריה).
          // If admin is ALSO a provider (isProvider: true), they see
          // provider tabs like any regular provider. No special merging.
          _isProvider     = isProvider;
          _isAdmin        = isAdmin;
          _providerLoaded = true;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _providerLoaded = true);
      },
    );
  }

  // ── Availability calendar helpers ──────────────────────────────────────────
  Future<void> _loadUnavailableDates() async {
    if (currentUserId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();
    final List<dynamic> raw =
        (doc.data()?['unavailableDates'] as List<dynamic>?) ?? [];
    if (mounted) {
      setState(() {
        _unavailableDates = raw
            .map((d) => DateTime.tryParse(d.toString()))
            .whereType<DateTime>()
            .map((d) => DateTime.utc(d.year, d.month, d.day))
            .toSet();
      });
    }
  }

  Future<void> _saveUnavailableDates() async {
    setState(() => _calendarSaving = true);
    try {
      final isoStrings = _unavailableDates
          .map((d) =>
              '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}')
          .toList();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .update({'unavailableDates': isoStrings});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.green,
              content: Text(AppLocalizations.of(context).availabilityUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.red, content: Text('שגיאה בשמירה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _calendarSaving = false);
    }
  }

  // ── Business logic: customer release escrow ────────────────────────────────
  Future<void> _handleCompleteJob(
      BuildContext context,
      String jobId,
      Map<String, dynamic> jobData,
      double amount) async {
    // Capture l10n before any await (async-gap safety).
    final l10n = AppLocalizations.of(context);

    _showLoadingOverlay();

    String? error;
    try {
      error = await PaymentModule.releaseEscrowFundsWithError(
        jobId: jobId,
        expertId: jobData['expertId'] ?? '',
        expertName: jobData['expertName'] ?? 'מומחה',
        customerName: jobData['customerName'] ?? 'לקוח',
        totalAmount: amount,
      );

      // Safety: verify Firestore actually reflects 'completed' before
      // dismissing the overlay and showing success. This prevents the race
      // condition where the CF resolves before the client stream catches up.
      if (error == null) {
        final snap = await FirebaseFirestore.instance
            .collection('jobs')
            .doc(jobId)
            .get();
        final confirmedStatus =
            (snap.data() ?? {})['status'] as String? ?? '';
        debugPrint('QA: Firestore job status after release = $confirmedStatus');
        if (confirmedStatus != 'completed') {
          error = 'הסטטוס לא עודכן — נסה שוב (status: $confirmedStatus)';
        } else {
          // Stamp completedAt so the 7-day review window can be calculated
          // for both parties. Use merge:true so any CF-written fields survive.
          // Awaited (not fire-and-forget) — a silent failure would shift the
          // window to createdAt, giving both parties unintended extra time.
          try {
            await FirebaseFirestore.instance
                .collection('jobs')
                .doc(jobId)
                .set({'completedAt': FieldValue.serverTimestamp()},
                    SetOptions(merge: true));
          } catch (e) {
            debugPrint('completedAt stamp failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('QA: Unexpected error in _handleCompleteJob: $e');
      error = e.toString();
    } finally {
      _hideLoadingOverlay();
    }

    if (!context.mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Colors.green,
            content: Text(l10n.bookingCompleted)),
      );
      // Open new double-blind ReviewScreen instead of legacy dialog
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            jobId:          jobId,
            revieweeId:     jobData['expertId']?.toString()    ?? '',
            revieweeName:   jobData['expertName']?.toString()  ?? 'מומחה',
            revieweeAvatar: jobData['expertImage']?.toString() ?? '',
            isClientReview: true,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.releasePaymentError),
          content: SelectableText(error!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(l10n.close)),
          ],
        ),
      );
    }
  }

  // ── Business logic: expert mark done ──────────────────────────────────────
  Future<void> _markJobDone(
      BuildContext context, String jobId, String chatRoomId) async {
    final strMarkedDone = AppLocalizations.of(context).markedDoneSuccess;
    // CRITICAL: use rootNavigator: true.
    // showDialog() pushes to the ROOT navigator (its default useRootNavigator=true).
    // The app wraps tabs in _nestedTab() nested navigators, so Navigator.of(context)
    // without rootNavigator would get the NESTED navigator — pop() would then
    // pop the wrong route and leave the loading dialog open forever ("freeze").
    final nav       = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      // 15-second timeout: prevents an indefinite spinner on bad mobile networks.
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobId)
          .update({
        'status': 'expert_completed',
        'expertCompletedAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw TimeoutException('הזמן הסתיים. בדוק את חיבור האינטרנט.'),
      );

      if (chatRoomId.isNotEmpty) {
        final chatRef =
            FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
        await chatRef.collection('messages').add({
          'senderId': 'system',
          'message':
              '✅ המומחה סיים את העבודה! לחץ על "אשר ושחרר" כדי לשחרר את התשלום.',
          'type': 'text',
          'timestamp': FieldValue.serverTimestamp(),
        });
        await chatRef.set({
          'lastMessage': '✅ המומחה סיים את העבודה!',
          'lastMessageTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      messenger.showSnackBar(
        SnackBar(backgroundColor: Colors.green, content: Text(strMarkedDone)),
      );
    } catch (e) {
      // ignore: avoid_print
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e is TimeoutException
              ? (e.message ?? 'הזמן הסתיים')
              : e.toString().toLowerCase().contains('permission')
                  ? 'אין הרשאה לעדכן את סטטוס ההזמנה.'
                  : 'שגיאה: $e'),
        ),
      );
    } finally {
      // Always dismiss the loading dialog regardless of success/failure/timeout.
      // Guard with canPop() in case the route was already dismissed (e.g. the
      // user navigated away or the stream rebuild disposed the route).
      if (nav.canPop()) nav.pop();
    }
  }

  // ── Business logic: customer cancel ───────────────────────────────────────
  Future<void> _cancelBooking(BuildContext context, String jobId,
      Map<String, dynamic> job, double amount) async {
    final penalty    = CancellationPolicyService.penaltyAmountFor(job);
    final hasPenalty = penalty > 0;
    final refund     = amount - penalty;
    final policy     = job['cancellationPolicy'] as String? ?? 'flexible';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                hasPenalty
                    ? Icons.warning_amber_rounded
                    : Icons.cancel_outlined,
                color: hasPenalty ? Colors.orange : Colors.red,
                size: 22),
            const SizedBox(width: 8),
            const Text('ביטול הזמנה',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: hasPenalty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      'אזהרה: חלון הביטול החינמי עבר.\n'
                      'לפי מדיניות ${CancellationPolicyService.label(policy)}, '
                      'ביטול כעת יגרור קנס של '
                      '₪${penalty.toStringAsFixed(0)}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.deepOrange),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'תקבל בחזרה: ₪${refund.toStringAsFixed(0)}\n'
                    'ישולם למומחה: ₪${penalty.toStringAsFixed(0)} (בניכוי עמלה)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              )
            : Text(
                'האם לבטל את ההזמנה?\n₪${amount.toStringAsFixed(0)} יוחזרו לארנק שלך.',
                textAlign: TextAlign.center,
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('לא, חזור')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: hasPenalty ? Colors.orange : Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
                hasPenalty
                    ? 'כן, בטל (קנס ₪${penalty.toStringAsFixed(0)})'
                    : 'כן, בטל',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final nav       = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await PaymentModule.cancelWithPolicy(
          jobId: jobId, cancelledBy: 'customer');
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(hasPenalty
            ? 'ההזמנה בוטלה — ₪${refund.toStringAsFixed(0)} הוחזרו לארנק'
            : 'ההזמנה בוטלה — ₪${amount.toStringAsFixed(0)} הוחזרו לארנק'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red, content: Text('שגיאה בביטול: $e')));
    } finally {
      if (nav.canPop()) nav.pop();
    }
  }

  // ── Business logic: provider cancel ───────────────────────────────────────
  Future<void> _providerCancelBooking(
      BuildContext context, String jobId, Map<String, dynamic> job) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('ביטול מצד הספק',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'ביטול מצד הספק מחזיר ללקוח 100% מהסכום\n'
          'ויפחית XP מהפרופיל שלך.\n\nהאם להמשיך?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('לא, חזור')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('כן, בטל',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final nav       = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await PaymentModule.cancelWithPolicy(
          jobId: jobId, cancelledBy: 'provider');
      messenger.showSnackBar(const SnackBar(
        backgroundColor: Colors.orange,
        content: Text('ההזמנה בוטלה — הלקוח יקבל החזר מלא'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red, content: Text('שגיאה בביטול: $e')));
    } finally {
      if (nav.canPop()) nav.pop();
    }
  }

  // ── Business logic: open dispute ───────────────────────────────────────────
  Future<void> _openDispute(BuildContext context, String jobId) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(c).disputeTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(c).disputeDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(c).disputeHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(AppLocalizations.of(c).cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(c, true);
            },
            child: Text(AppLocalizations.of(c).submitDispute,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final uid     = FirebaseAuth.instance.currentUser?.uid ?? '';
    final reason  = reasonCtrl.text.trim();

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status':          'disputed',
      'disputeReason':   reason,
      'disputeOpenedAt': FieldValue.serverTimestamp(),
      'disputerId':      uid,
    });

    // ── Activity log → Admin Live Feed ───────────────────────────────
    FirebaseFirestore.instance.collection('activity_log').add({
      'type':      'new_dispute',
      'title':     '⚖️ מחלוקת חדשה נפתחה',
      'detail':    reason.isNotEmpty ? reason : '(ללא פירוט)',
      'jobId':     jobId,
      'disputerId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'priority':  'high',
    }).ignore();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('המחלוקת נפתחה — הצוות יצור קשר תוך 48 שעות'),
        ),
      );
    }
  }

  // ── Rating dialog ──────────────────────────────────────────────────────────

  // ── Job details bottom sheet ───────────────────────────────────────────────
  void _showJobDetailsSheet(
      BuildContext context, Map<String, dynamic> job, String jobId) {
    final status = job['status'] ?? '';
    const statusLabels = {
      'paid_escrow':             'ממתין לסיום',
      'expert_completed':        'ממתין לאישור',
      'completed':               'הושלם',
      'cancelled':               'בוטל',
      'disputed':                'במחלוקת',
      'split_resolved':          'נפתר — פשרה',
      'cancelled_with_penalty':  'בוטל (קנס)',
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 20),
            const Text('פרטי הזמנה',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _detailRow(Icons.tag, 'מזהה הזמנה', jobId),
            _detailRow(Icons.person_outline, 'מומחה',
                job['expertName'] ?? '—'),
            _detailRow(
                Icons.person_2_outlined, 'לקוח', job['customerName'] ?? '—'),
            _detailRow(Icons.info_outline, 'סטטוס',
                statusLabels[status] ?? status),
            _detailRow(
                Icons.attach_money,
                'סכום',
                '₪${(job['totalAmount'] ?? job['totalPaidByCustomer'] ?? 0).toStringAsFixed(0)}'),
            if (job['appointmentDate'] != null)
              _detailRow(
                  Icons.calendar_today,
                  'תאריך',
                  DateFormat('dd/MM/yyyy').format(
                      (job['appointmentDate'] as Timestamp).toDate())),
            if ((job['appointmentTime'] ?? '').toString().isNotEmpty)
              _detailRow(
                  Icons.access_time, 'שעה', job['appointmentTime']),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text('$label: ',
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // ── Receipt helper ─────────────────────────────────────────────────────────
  Future<void> _showReceiptFor(
      BuildContext context, Map<String, dynamic> job) async {
    final expertId = job['expertId'] as String? ?? '';
    String? taxId;
    if (expertId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(expertId)
          .get();
      taxId = snap.data()?['taxId'] as String?;
    }
    if (context.mounted) {
      showReceiptSheet(context, jobData: job, providerTaxId: taxId);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_providerLoaded) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: _isProvider ? 3 : 2, // Provider: Tasks+Calendar+History, Customer: Activity+History
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 20,
          title: Text(
            _isProvider ? 'העבודות שלי' : 'ההזמנות שלי',
            style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 20),
          ),
          actions: [
            HintIcon(
                screenKey: _isProvider
                    ? 'my_tasks_expert'
                    : 'my_bookings_client'),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                    bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
              ),
              child: TabBar(
                indicatorColor: const Color(0xFF6366F1),
                indicatorWeight: 3,
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                tabs: _isProvider
                    ? const [Tab(text: 'משימות שלי'), Tab(text: 'יומן'), Tab(text: 'היסטוריה')]
                    : const [Tab(text: 'פעילות'), Tab(text: 'היסטוריה')],
              ),
            ),
          ),
        ),
        body: TabBarView(
          // _KeepAlivePage prevents Flutter from disposing the tab's widget
          // subtree (including its StreamBuilder state) when the user switches
          // tabs. Without this, every tab switch triggers a full rebuild +
          // Firestore round-trip, causing the freeze Avi reported on iPhone.
          children: _isProvider
              ? [
                  _KeepAlivePage(child: _buildProviderTasksTab()),
                  _KeepAlivePage(child: _buildCalendarView()),
                  _KeepAlivePage(child: _buildProviderHistoryTab()),
                ]
              : [
                  _KeepAlivePage(
                      child: _buildFilteredCustomerList(_activeStatuses)),
                  _KeepAlivePage(
                      child: _buildFilteredCustomerList(_historyStatuses)),
                ],
        ),
      ),
    );
  }

  // ── Customer filtered list ─────────────────────────────────────────────────
  Widget _buildFilteredCustomerList(Set<String> statusFilter) {
    final isHistory = statusFilter == _historyStatuses;
    return StreamBuilder<QuerySnapshot>(
      stream: _customerStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _BookingsShimmer();
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded,
                    size: 40, color: Color(0xFFEF4444)),
                const SizedBox(height: 12),
                const Text('לא ניתן לטעון את ההזמנות כרגע. אנא נסה שוב.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
              ]),
            ),
          );
        }

        final all = snapshot.data?.docs ?? [];
        final filtered = all.where((d) {
          final status =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          if (status.isEmpty) return false;
          // For the history tab: catch-all — show every status that is NOT
          // an active status so no "unknown" terminal status falls through
          // the cracks (e.g. if the Cloud Function writes 'paid' instead of
          // 'completed').  For the active tab: use the explicit set as before.
          return isHistory
              ? !_activeStatuses.contains(status)
              : statusFilter.contains(status);
        }).toList()
          ..sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) {
              return tb.compareTo(ta); // newest first
            }
            return 0;
          });

        if (filtered.isEmpty) {
          return _buildEmptyState(isExpert: false, isHistory: isHistory);
        }

        return _buildGroupedList(filtered, isExpert: false, isHistory: isHistory);
      },
    );
  }

  // ── Provider tasks list ────────────────────────────────────────────────────
  /// Tracks job IDs for which we already auto-opened the review popup,
  /// so we don't re-trigger on every stream rebuild.
  final Set<String> _reviewTriggeredFor = {};

  /// Auto-opens ReviewScreen for completed jobs the provider hasn't reviewed.
  /// CRITICAL: Only triggers when the current user IS the expert for this job.
  /// Without this guard, admins (who see merged streams) would be asked to
  /// rate themselves on jobs where they are the CUSTOMER, not the expert.
  void _autoTriggerProviderReview(BuildContext ctx, List<QueryDocumentSnapshot> docs) {
    // ── Admins NEVER get auto-review popups ──────────────────────────────
    // Admins use the admin panel to manage reviews. Auto-popups trapped
    // them in a self-rating loop because their UID appeared in merged streams.
    if (_isAdmin) return;

    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['status'] != 'completed') continue;
      if (d['providerReviewDone'] == true) continue;
      if (d['providerReviewShown'] == true) continue; // already prompted
      if (_reviewTriggeredFor.contains(doc.id)) continue;

      // Require completedAt — proves payment was finalized in Firestore
      final completedAt = d['completedAt'];
      if (completedAt == null) continue;

      // Anti-fraud: only the EXPERT for this job can auto-review
      final jobExpertId   = d['expertId']?.toString()   ?? '';
      final jobCustomerId = d['customerId']?.toString() ?? '';
      if (jobExpertId != currentUserId) continue;
      if (jobExpertId == jobCustomerId) continue;

      _reviewTriggeredFor.add(doc.id);

      // Mark reviewShown in Firestore IMMEDIATELY to prevent re-trigger
      // even if the stream fires again before the popup is dismissed.
      FirebaseFirestore.instance.collection('jobs').doc(doc.id).update({
        'providerReviewShown': true,
      }).catchError((_) {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => ReviewScreen(
            jobId:          doc.id,
            revieweeId:     jobCustomerId,
            revieweeName:   d['customerName']?.toString() ?? 'לקוח',
            revieweeAvatar: '',
            isClientReview: false,
          ),
        ));
      });
      break; // only one popup at a time
    }
  }

  /// Tracks whether the tasks StreamBuilder has received its first snapshot.
  /// Used to show shimmer vs empty state correctly.
  bool _tasksFirstSnapshotReceived = false;

  Widget _buildProviderTasksTab() {
    // Start the timeout WHEN the tab renders (not in initState which races
    // against _providerLoaded). This gives the full 10 seconds for the
    // expert stream to deliver data.
    _tasksTimeoutTimer ??= Timer(const Duration(seconds: 10), () {
      if (mounted && !_tasksFirstSnapshotReceived) {
        setState(() => _tasksTimedOut = true);
      }
    });

    return _buildSingleTasksStream(_expertStream);
  }

  /// Standard single-stream view for providers (expert-side jobs only).
  /// Provider History tab — shows completed, cancelled, refunded jobs.
  Widget _buildProviderHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _expertStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final historyDocs = docs.where((d) {
          final status = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return !_activeStatuses.contains(status) && status.isNotEmpty;
        }).toList()
          ..sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

        if (historyDocs.isEmpty) {
          return _buildEmptyState(isExpert: true, isHistory: true);
        }
        return _buildGroupedList(historyDocs, isExpert: true, isHistory: true);
      },
    );
  }

  Widget _buildSingleTasksStream(Stream<QuerySnapshot> stream) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        // ── Error state ─────────────────────────────────────────────────
        if (snapshot.hasError) {
          debugPrint('[Tasks] ERROR: ${snapshot.error}');
          final err = snapshot.error.toString().toLowerCase();
          final isPermission =
              err.contains('permission') || err.contains('insufficient');
          final isIndex = err.contains('index') ||
              err.contains('failed-precondition') ||
              err.contains('requires an index');
          final msg = isPermission
              ? 'אין הרשאה לצפות במשימות. פנה לתמיכה.'
              : isIndex
                  ? 'אינדקס מסד הנתונים עדיין נבנה. נסה שוב בעוד דקה.'
                  : 'חלה שגיאה בטעינת המשימות, אנא נסה שנית.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: Color(0xFFEF4444)),
                  const SizedBox(height: 16),
                  Text(msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF64748B))),
                ],
              ),
            ),
          );
        }

        // ── Waiting for first snapshot ───────────────────────────────────
        // Show shimmer while the stream hasn't delivered anything yet.
        // After the timeout, fall through to the data/empty check below
        // so we don't show a shimmer forever.
        if (!snapshot.hasData && !_tasksTimedOut) {
          return const _BookingsShimmer();
        }

        final docs = snapshot.data?.docs ?? [];
        _tasksFirstSnapshotReceived = true;
        _tasksTimeoutTimer?.cancel();

        // Debug: log what the stream returned
        debugPrint('[Tasks] expertStream returned ${docs.length} docs for uid=$currentUserId');
        for (final d in docs) {
          final m = d.data() as Map<String, dynamic>;
          debugPrint('  • job=${d.id} status=${m['status']} '
              'expertId=${m['expertId']} customerId=${m['customerId']}');
        }

        if (docs.isEmpty) {
          debugPrint('[Tasks] EMPTY — showing empty state');
          return _buildEmptyState(isExpert: true, isHistory: false);
        }

        // ── Auto-trigger review popup for newly completed jobs ──────
        // If a job just transitioned to 'completed' and the provider
        // hasn't reviewed yet, open the ReviewScreen automatically.
        _autoTriggerProviderReview(context, docs);

        return _buildExpertTasksList(docs);
      },
    );
  }

  // ── Expert tasks: Today (active) + History ─────────────────────────────────
  int _jobTimestamp(QueryDocumentSnapshot d) {
    final ts = (d.data() as Map)['createdAt'];
    return ts is Timestamp ? ts.millisecondsSinceEpoch : 0;
  }

  Widget _buildExpertTasksList(List<QueryDocumentSnapshot> docs) {
    // Sort newest first (no server-side orderBy to avoid composite index).
    final sorted = [...docs]
      ..sort((a, b) => _jobTimestamp(b).compareTo(_jobTimestamp(a)));

    // Use the class-level _activeStatuses set for consistency
    final activeDocs  = sorted
        .where((d) => _activeStatuses.contains(
            (d.data() as Map<String, dynamic>)['status'] as String? ?? ''))
        .toList();
    final historyDocs = sorted
        .where((d) => !_activeStatuses.contains(
            (d.data() as Map<String, dynamic>)['status'] as String? ?? ''))
        .toList();

    // Sum expected earnings from pending (paid_escrow) jobs
    double todayEarnings = 0;
    for (final doc in activeDocs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['status'] == 'paid_escrow') {
        todayEarnings += ((d['netAmountForExpert'] ??
                d['totalPaidByCustomer'] ??
                d['totalAmount'] ??
                0.0) as num)
            .toDouble();
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // ── Today earnings summary ──────────────────────────────────
        if (activeDocs.isNotEmpty) ...[
          _ExpertEarningsSummary(
              expectedEarnings: todayEarnings,
              activeCount: activeDocs
                  .where((d) =>
                      (d.data() as Map<String, dynamic>)['status'] ==
                      'paid_escrow')
                  .length),
          const SizedBox(height: 16),
          _groupHeader('פעיל', activeDocs.length),
          const SizedBox(height: 10),
          for (final doc in activeDocs)
            _ExpertJobCard(
              key: ValueKey(doc.id),
              job: doc.data() as Map<String, dynamic>,
              jobId: doc.id,
              onMarkDone: (jobId, chatRoomId) =>
                  _markJobDone(context, jobId, chatRoomId),
              onCancel: (jobId) => _providerCancelBooking(
                  context, jobId, doc.data() as Map<String, dynamic>),
              onDetails: () => _showJobDetailsSheet(
                  context, doc.data() as Map<String, dynamic>, doc.id),
              onReceipt: () =>
                  _showReceiptFor(context, doc.data() as Map<String, dynamic>),
              onRate: () {
                final d = doc.data() as Map<String, dynamic>;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ReviewScreen(
                    jobId:          doc.id,
                    revieweeId:     d['customerId']?.toString()   ?? '',
                    revieweeName:   d['customerName']?.toString() ?? 'לקוח',
                    revieweeAvatar: '',
                    isClientReview: false,
                  ),
                ));
              },
            ),
          const SizedBox(height: 20),
        ],

        // ── History ─────────────────────────────────────────────────
        if (historyDocs.isNotEmpty) ...[
          _groupHeader('היסטוריה', historyDocs.length),
          const SizedBox(height: 10),
          for (final doc in historyDocs)
            _ExpertJobCard(
              key: ValueKey(doc.id),
              job: doc.data() as Map<String, dynamic>,
              jobId: doc.id,
              onMarkDone: (jobId, chatRoomId) =>
                  _markJobDone(context, jobId, chatRoomId),
              onCancel: (jobId) => _providerCancelBooking(
                  context, jobId, doc.data() as Map<String, dynamic>),
              onDetails: () => _showJobDetailsSheet(
                  context, doc.data() as Map<String, dynamic>, doc.id),
              onReceipt: () =>
                  _showReceiptFor(context, doc.data() as Map<String, dynamic>),
              onRate: () {
                final d = doc.data() as Map<String, dynamic>;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ReviewScreen(
                    jobId:          doc.id,
                    revieweeId:     d['customerId']?.toString()   ?? '',
                    revieweeName:   d['customerName']?.toString() ?? 'לקוח',
                    revieweeAvatar: '',
                    isClientReview: false,
                  ),
                ));
              },
            ),
        ],
      ],
    );
  }

  // ── Grouped list ───────────────────────────────────────────────────────────
  Widget _buildGroupedList(List<QueryDocumentSnapshot> docs,
      {required bool isExpert, bool isHistory = false}) {
    final now = DateTime.now();
    final thisMonthStart  = DateTime(now.year, now.month, 1);
    final lastMonthStart  = DateTime(now.year, now.month - 1, 1);

    final groups = <String, List<QueryDocumentSnapshot>>{
      'החודש':      [],
      'חודש שעבר':  [],
      'ישן יותר':   [],
    };

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts   = data['createdAt'] as Timestamp?;
      final date = ts?.toDate() ?? DateTime(2000);
      if (!date.isBefore(thisMonthStart)) {
        groups['החודש']!.add(doc);
      } else if (!date.isBefore(lastMonthStart)) {
        groups['חודש שעבר']!.add(doc);
      } else {
        groups['ישן יותר']!.add(doc);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        for (final entry in groups.entries)
          if (entry.value.isNotEmpty) ...[
            _groupHeader(entry.key, entry.value.length),
            const SizedBox(height: 10),
            for (final doc in entry.value)
              isExpert
                  ? _ExpertJobCard(
                      key: ValueKey(doc.id),
                      job: doc.data() as Map<String, dynamic>,
                      jobId: doc.id,
                      onMarkDone: (jobId, chatRoomId) =>
                          _markJobDone(context, jobId, chatRoomId),
                      onCancel: (jobId) => _providerCancelBooking(
                          context, jobId, doc.data() as Map<String, dynamic>),
                      onDetails: () => _showJobDetailsSheet(
                          context,
                          doc.data() as Map<String, dynamic>,
                          doc.id),
                      onReceipt: () => _showReceiptFor(
                          context, doc.data() as Map<String, dynamic>),
                    )
                  : isHistory
                      ? _HistoryOrderCard(
                          key: ValueKey(doc.id),
                          job: doc.data() as Map<String, dynamic>,
                          jobId: doc.id,
                          onReceipt: () => _showReceiptFor(
                              context, doc.data() as Map<String, dynamic>),
                        )
                      : _CustomerBookingCard(
                          key: ValueKey(doc.id),
                          job: doc.data() as Map<String, dynamic>,
                          jobId: doc.id,
                          currentUserId: currentUserId,
                          onCompleteJob: (amount) => _handleCompleteJob(
                              context,
                              doc.id,
                              doc.data() as Map<String, dynamic>,
                              amount),
                          onCancel: (amount) => _cancelBooking(
                              context,
                              doc.id,
                              doc.data() as Map<String, dynamic>,
                              amount),
                          onDispute: () => _openDispute(context, doc.id),
                          onRate: () {
                            final d = doc.data() as Map<String, dynamic>;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReviewScreen(
                                  jobId:          doc.id,
                                  revieweeId:     d['expertId']?.toString()    ?? '',
                                  revieweeName:   d['expertName']?.toString()  ?? 'מומחה',
                                  revieweeAvatar: d['expertImage']?.toString() ?? '',
                                  isClientReview: true,
                                ),
                              ),
                            );
                          },
                          onDetails: () => _showJobDetailsSheet(
                              context,
                              doc.data() as Map<String, dynamic>,
                              doc.id),
                          onRebook: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExpertProfileScreen(
                                expertId: (doc.data()
                                        as Map<String, dynamic>)['expertId'] ??
                                    '',
                                expertName: (doc.data()
                                            as Map<String, dynamic>)['expertName'] ??
                                        'מומחה',
                              ),
                            ),
                          ),
                          onReceipt: () => _showReceiptFor(
                              context, doc.data() as Map<String, dynamic>),
                        ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _groupHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 2),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                letterSpacing: 0.4),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Calendar view (provider availability + scheduled jobs) ───────────────
  Widget _buildCalendarView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _expertStream,
      builder: (context, snap) {
        // Build appointment-day lookup from stream data
        final appointmentDays = <DateTime>{};
        final jobsByDay       = <DateTime, List<Map<String, dynamic>>>{};
        for (final doc in snap.data?.docs ?? []) {
          final d  = doc.data() as Map<String, dynamic>;
          final ts = d['appointmentDate'] as Timestamp?;
          if (ts == null) continue;
          final dt   = ts.toDate();
          final norm = DateTime.utc(dt.year, dt.month, dt.day);
          appointmentDays.add(norm);
          jobsByDay.putIfAbsent(norm, () => []).add(d);
        }

        // Jobs for the currently selected day
        final selJobs = _selectedCalendarDay == null
            ? <Map<String, dynamic>>[]
            : jobsByDay[DateTime.utc(
                    _selectedCalendarDay!.year,
                    _selectedCalendarDay!.month,
                    _selectedCalendarDay!.day)] ??
                [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('ניהול זמינות',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'לחץ על תאריך לבחירה. לחיצה ארוכה לחסימה/שחרור.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 4),
              // Legend
              Row(children: [
                Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                        color: Colors.red[200],
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 5),
                Text('חסום', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(width: 14),
                Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFF6366F1), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('הזמנה', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ]),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10)],
                ),
                child: TableCalendar(
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _calendarFocusedDay,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: 'חודש'},
                  startingDayOfWeek: StartingDayOfWeek.sunday,
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  // Purple dots for days with appointments
                  eventLoader: (day) {
                    final norm = DateTime.utc(day.year, day.month, day.day);
                    return appointmentDays.contains(norm) ? ['job'] : [];
                  },
                  calendarStyle: CalendarStyle(
                    // Selected day (user tap to view appointments)
                    selectedDecoration: const BoxDecoration(
                        color: Color(0xFF6366F1), shape: BoxShape.circle),
                    selectedTextStyle: const TextStyle(color: Colors.white),
                    todayDecoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        shape: BoxShape.circle),
                    todayTextStyle: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.bold),
                    // Purple marker dots
                    markerDecoration: const BoxDecoration(
                        color: Color(0xFF6366F1), shape: BoxShape.circle),
                    markersMaxCount: 1,
                    markerSize: 5,
                  ),
                  // Custom builder: overlay stripe pattern on blocked dates
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      final norm = DateTime.utc(day.year, day.month, day.day);
                      if (!_unavailableDates.contains(norm)) return null;
                      return _StripedBlockedDay(day: day, isSelected: false);
                    },
                    selectedBuilder: (context, day, focusedDay) {
                      final norm = DateTime.utc(day.year, day.month, day.day);
                      if (_unavailableDates.contains(norm)) {
                        return _StripedBlockedDay(day: day, isSelected: true);
                      }
                      return null; // use default selected style
                    },
                  ),
                  selectedDayPredicate: (day) =>
                      _selectedCalendarDay != null &&
                      isSameDay(_selectedCalendarDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedCalendarDay = selectedDay;
                      _calendarFocusedDay  = focusedDay;
                    });
                  },
                  onDayLongPressed: (selectedDay, focusedDay) {
                    final norm = DateTime.utc(
                        selectedDay.year, selectedDay.month, selectedDay.day);
                    setState(() {
                      if (_unavailableDates.contains(norm)) {
                        _unavailableDates.remove(norm);
                      } else {
                        _unavailableDates.add(norm);
                      }
                      _calendarFocusedDay = focusedDay;
                    });
                  },
                  onPageChanged: (focusedDay) =>
                      setState(() => _calendarFocusedDay = focusedDay),
                ),
              ),

              // ── Selected day appointments ─────────────────────────────
              if (_selectedCalendarDay != null) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.event_note_rounded,
                      size: 15, color: Color(0xFF6366F1)),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('EEEE, d בMMMM', 'he')
                        .format(_selectedCalendarDay!),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1A1A2E)),
                  ),
                ]),
                const SizedBox(height: 8),
                if (selJobs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'אין הזמנות ביום זה',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500]),
                    ),
                  )
                else
                  for (final j in selJobs)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.3)),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                        )],
                      ),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEEF2FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: Color(0xFF6366F1), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(j['customerName'] ?? 'לקוח',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              if ((j['appointmentTime'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text(j['appointmentTime'],
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        _StatusBadge(j['status'] ?? ''),
                      ]),
                    ),
              ],

              // ── Blocked dates chips ───────────────────────────────────
              if (_unavailableDates.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.block_rounded,
                      size: 14, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  const Text('תאריכים חסומים:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B))),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: (_unavailableDates.toList()..sort())
                      .map((d) => Chip(
                            label: Text('${d.day}/${d.month}/${d.year}',
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.red[50],
                            deleteIcon:
                                const Icon(Icons.close, size: 16),
                            onDeleted: () =>
                                setState(() => _unavailableDates.remove(d)),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              _calendarSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _saveUnavailableDates,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('שמור חסימות',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
            ],
          ),
        );
      },
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(
      {required bool isExpert, required bool isHistory}) {
    final icon   = isHistory ? Icons.history_rounded
        : isExpert ? Icons.work_outline
        : Icons.home_repair_service_rounded;
    final title  = isExpert
        ? 'אין משימות עדיין'
        : isHistory
            ? 'אין היסטוריית הזמנות'
            : 'יש לך משימה? לנו יש את האדם הנכון בשבילה.';
    final subtitle = isExpert
        ? 'הזמנות מלקוחות יופיעו כאן. ודא שהפרופיל שלך מעודכן.'
        : isHistory
            ? 'הזמנות שהושלמו יופיעו כאן.'
            : 'אל תתפשר על פחות מהטוב ביותר. בוא נתחיל?';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  shape: BoxShape.circle),
              child: Icon(icon, size: 54, color: const Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF94A3B8))),
            if (!isExpert && !isHistory) ...[
              const SizedBox(height: 28),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text('הזמן שירות עכשיו',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                onPressed: widget.onGoToSearch,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Keep-alive tab wrapper ─────────────────────────────────────────────────
//
// Wraps any tab child in a StatefulWidget with AutomaticKeepAliveClientMixin.
// Flutter's TabBarView normally disposes non-visible tabs, which destroys
// the StreamBuilder state and forces a full Firestore re-fetch on every
// switch. This wrapper keeps the entire subtree (including StreamBuilder
// state) alive in memory, making tab switches instant.

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by the mixin
    return widget.child;
  }
}


// ── Bookings shimmer skeleton ──────────────────────────────────────────────
//
// Shown only on the very first load (waiting && !hasData).
// Lighter than a centered spinner — avoids layout jank on iPhone by keeping
// the list region occupied while Firestore delivers the first snapshot.

class _BookingsShimmer extends StatefulWidget {
  const _BookingsShimmer();

  @override
  State<_BookingsShimmer> createState() => _BookingsShimmerState();
}

class _BookingsShimmerState extends State<_BookingsShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.4 + _anim.value * 0.4;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, __) => Opacity(
            opacity: opacity,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // Avatar placeholder
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  // Text lines placeholder
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(height: 14, width: 120, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
                          Container(height: 10, width: 80,  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
                          Container(height: 10, width: 100, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Profile avatar ─────────────────────────────────────────────────────────

class _ProfileAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final double size;

  const _ProfileAvatar(
      {required this.uid, required this.name, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        final data =
            snap.data?.data() as Map<String, dynamic>? ?? {};
        final url = data['profileImage'] as String?;
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: const Color(0xFFEEF2FF),
          backgroundImage:
              (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
          child: (url == null || url.isEmpty)
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF6366F1)),
                )
              : null,
        );
      },
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge(this.status);

  static const _map = <String, (Color, Color, String)>{
    'paid_escrow':             (Color(0xFFFFF7ED), Color(0xFFF97316), 'בנאמנות'),
    'expert_completed':        (Color(0xFFEFF6FF), Color(0xFF3B82F6), 'ממתין לאישור'),
    'completed':               (Color(0xFFF0FFF4), Color(0xFF16A34A), 'הושלם'),
    'cancelled':               (Color(0xFFFFF5F5), Color(0xFFEF4444), 'בוטל'),
    'cancelled_with_penalty':  (Color(0xFFFFF5F5), Color(0xFFEF4444), 'בוטל+קנס'),
    'disputed':                (Color(0xFFFEF2F2), Color(0xFFDC2626), 'במחלוקת'),
    'refunded':                (Color(0xFFF0FDFA), Color(0xFF0D9488), 'הוחזר'),
    'split_resolved':          (Color(0xFFFAF5FF), Color(0xFF9333EA), 'פשרה'),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) =
        _map[status] ?? (const Color(0xFFF8FAFC), const Color(0xFF94A3B8), 'בטיפול');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ── History order card (read-only, clean summary) ────────────────────────

class _HistoryOrderCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final VoidCallback? onReceipt;

  const _HistoryOrderCard({
    super.key,
    required this.job,
    required this.jobId,
    this.onReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final expertId   = job['expertId']   as String? ?? '';
    final expertName = job['expertName'] as String? ?? 'מומחה';
    final status     = job['status']     as String? ?? '';
    final amount     = ((job['totalAmount'] ?? job['totalPaidByCustomer'] ?? 0.0) as num).toDouble();
    final serviceType = job['serviceType'] as String? ?? '';

    DateTime? date;
    if (job['appointmentDate'] is Timestamp) {
      date = (job['appointmentDate'] as Timestamp).toDate();
    } else if (job['createdAt'] is Timestamp) {
      date = (job['createdAt'] as Timestamp).toDate();
    }
    final dateStr = date != null ? DateFormat('dd/MM/yy').format(date) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            _ProfileAvatar(uid: expertId, name: expertName, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expertName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E)),
                  ),
                  if (serviceType.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      serviceType,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (dateStr.isNotEmpty) ...[
                        const Icon(Icons.calendar_today_rounded,
                            size: 11, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 3),
                        Text(dateStr,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8))),
                        const SizedBox(width: 10),
                      ],
                      const Icon(Icons.attach_money_rounded,
                          size: 13, color: Color(0xFF94A3B8)),
                      Text(
                        '₪${amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(status),
                if (onReceipt != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onReceipt,
                    child: const Text(
                      'קבלה',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Customer booking card ──────────────────────────────────────────────────

class _CustomerBookingCard extends StatefulWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final String currentUserId;
  final void Function(double amount) onCompleteJob;
  final void Function(double amount) onCancel;
  final VoidCallback onDispute;
  final VoidCallback onRate;
  final VoidCallback onDetails;
  final VoidCallback onRebook;
  final VoidCallback onReceipt;

  const _CustomerBookingCard({
    super.key,
    required this.job,
    required this.jobId,
    required this.currentUserId,
    required this.onCompleteJob,
    required this.onCancel,
    required this.onDispute,
    required this.onRate,
    required this.onDetails,
    required this.onRebook,
    required this.onReceipt,
  });

  @override
  State<_CustomerBookingCard> createState() => _CustomerBookingCardState();
}

class _CustomerBookingCardState extends State<_CustomerBookingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;
  Timer? _workTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    // Rebuild every 30 s so "work started X min ago" stays fresh
    _workTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _workTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendTip(BuildContext context, double tipAmount) async {
    final expertId   = widget.job['expertId']   as String? ?? '';
    final expertName = widget.job['expertName'] as String? ?? 'מומחה';
    if (expertId.isEmpty || widget.currentUserId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('שלח טיפ',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'לשלוח ₪${tipAmount.toStringAsFixed(0)} טיפ ל-$expertName?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ביטול')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1)),
            onPressed: () => Navigator.pop(c, true),
            child:
                const Text('שלח', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final db  = FirebaseFirestore.instance;
    final bat = db.batch();
    bat.set(db.collection('transactions').doc(), {
      'type':         'tip',
      'senderId':     widget.currentUserId,
      'receiverId':   expertId,
      'senderName':   widget.job['customerName'] ?? 'לקוח',
      'receiverName': expertName,
      'amount':       tipAmount,
      'jobId':        widget.jobId,
      'payoutStatus': 'pending',
      'timestamp':    FieldValue.serverTimestamp(),
    });
    bat.update(db.collection('users').doc(expertId), {
      'pendingBalance': FieldValue.increment(tipAmount),
    });
    bat.update(db.collection('users').doc(widget.currentUserId), {
      'balance': FieldValue.increment(-tipAmount),
    });
    try {
      await bat.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF6366F1),
          content: Text('₪${tipAmount.toStringAsFixed(0)} נשלחו ל-$expertName 🎉'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('שגיאה בשליחת טיפ: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job         = widget.job;
    final status      = job['status'] as String? ?? '';
    final expertId    = job['expertId']   as String? ?? '';
    final expertName  = job['expertName'] as String? ?? 'מומחה';
    final expertPhone = job['expertPhone'] as String? ?? '';
    final amount      = (job['totalAmount'] ??
            job['totalPaidByCustomer'] ??
            job['amount'] ??
            0.0)
        .toDouble();

    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptStr  = apptDate != null
        ? DateFormat('dd/MM/yy').format(apptDate)
        : 'טרם נקבע';
    final apptTime   = job['appointmentTime'] as String? ?? '';
    final chatRoomId = job['chatRoomId']      as String? ?? '';
    final isCompleted = status == 'completed';
    final isActive    = status == 'paid_escrow' || status == 'expert_completed';
    final isReviewed  = job['clientReviewDone'] == true;

    // ── Live signal fields ──────────────────────────────────────────
    final expertOnWay   = job['expertOnWay']   == true;
    final workStartedTs = job['workStartedAt'] as Timestamp?;
    final expertLat     = (job['expertLat'] as num?)?.toDouble();
    final expertLng     = (job['expertLng'] as num?)?.toDouble();

    // ── Step index ──────────────────────────────────────────────────
    final int stepIndex;
    if (status == 'expert_completed' || status == 'completed') {
      stepIndex = 3;
    } else if (workStartedTs != null) {
      stepIndex = 2;
    } else if (expertOnWay) {
      stepIndex = 1;
    } else {
      stepIndex = 0;
    }

    final workMinutes = workStartedTs != null
        ? DateTime.now().difference(workStartedTs.toDate()).inMinutes
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Card header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _ProfileAvatar(uid: expertId, name: expertName, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(expertName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1A1A2E))),
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                            apptTime.isNotEmpty
                                ? '$apptStr · $apptTime'
                                : apptStr,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8))),
                      ]),
                    ],
                  ),
                ),
                _StatusBadge(status),
              ],
            ),
          ),

          // ── Step tracker (active bookings) ───────────────────────────
          if (isActive || status == 'expert_completed') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BookingStepIndicator(currentStep: stepIndex),
            ),
            const SizedBox(height: 12),
          ],

          // ── "On the way" live signal ──────────────────────────────────
          if (expertOnWay && workStartedTs == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6)
                                .withValues(alpha: _pulse.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Live',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3B82F6))),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('המומחה בדרך אליך',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E40AF))),
                      ),
                    ]),
                    if (expertLat != null && expertLng != null) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse(
                              'https://maps.google.com/?q=$expertLat,$expertLng'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_on_rounded,
                                  color: Colors.white, size: 15),
                              SizedBox(width: 6),
                              Text('צפה במומחה על המפה 📍',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ── "In progress" timer ───────────────────────────────────────
          if (workStartedTs != null && status == 'paid_escrow') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Icon(Icons.construction_rounded,
                        size: 16,
                        color: const Color(0xFF16A34A)
                            .withValues(alpha: 0.5 + _pulse.value * 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'העבודה החלה לפני $workMinutes דקות',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D)),
                  ),
                ]),
              ),
            ),
          ],

          // ── Amount strip ─────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.lock_rounded,
                      size: 14, color: Color(0xFF6366F1)),
                  const SizedBox(width: 5),
                  Text(
                    isActive ? 'בנאמנות' : 'סכום',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ]),
                Text(
                  '₪${amount.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isCompleted
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF1A1A2E)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Action buttons ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              children: [

                // expert_completed → release payment
                if (status == 'expert_completed') ...[
                  _PrimaryButton(
                    label: 'אשר ושחרר תשלום',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () => widget.onCompleteJob(amount),
                  ),
                  const SizedBox(height: 8),
                  _SecondaryButton(
                    label: 'יש בעיה — פתח מחלוקת',
                    icon: Icons.report_outlined,
                    color: Colors.red,
                    onPressed: widget.onDispute,
                  ),
                ],

                // paid_escrow → cancel only (contact via sticky bar below)
                if (status == 'paid_escrow') ...[
                  _QuickActionChip(
                    icon: Icons.cancel_outlined,
                    label: 'בטל הזמנה',
                    color: const Color(0xFFFEF2F2),
                    iconColor: Colors.red,
                    onPressed: () => widget.onCancel(amount),
                  ),
                ],

                // completed → FEEDBACK CARD ────────────────────────────
                if (isCompleted) ...[
                  if (!isReviewed) ...[
                    // Inline feedback card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text('איך היה השירות?',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              5,
                              (i) => GestureDetector(
                                onTap: widget.onRate,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Icon(Icons.star_rounded,
                                      size: 34,
                                      color: Colors.white
                                          .withValues(alpha: 0.45 + i * 0.11)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: widget.onRate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('שלח ביקורת ⭐',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF6366F1))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Quick Tip row
                    Row(children: [
                      const Icon(Icons.volunteer_activism_rounded,
                          size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 5),
                      const Text('שלח טיפ:',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      for (final tip in [10.0, 20.0, 50.0])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _sendTip(context, tip),
                            child: Container(
                              margin: const EdgeInsetsDirectional.only(end: 6),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFFBBF24),
                                    width: 1),
                              ),
                              child: Text(
                                '₪${tip.toStringAsFixed(0)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E)),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 10),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 14, color: Color(0xFF16A34A)),
                            SizedBox(width: 6),
                            Text('ביקורת נשלחה — תודה!',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF16A34A))),
                          ]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _PrimaryButton(
                    label: 'הזמן שוב את $expertName',
                    icon: Icons.replay_rounded,
                    color: const Color(0xFF6366F1),
                    onPressed: widget.onRebook,
                  ),
                  const SizedBox(height: 8),
                  _QuickActionChip(
                    icon: Icons.receipt_long_rounded,
                    label: 'קבלה',
                    onPressed: widget.onReceipt,
                  ),
                ],
              ],
            ),
          ),

          // ── Direct Contact Bar (active bookings) ───────────────────
          if (isActive) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24)),
                border: Border(
                    top: BorderSide(color: Colors.grey.shade100, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: expertPhone.isNotEmpty
                          ? () => launchUrl(
                              Uri.parse('tel:$expertPhone'),
                              mode: LaunchMode.externalApplication)
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExpertProfileScreen(
                                    expertId: expertId,
                                    expertName: expertName,
                                  ),
                                ),
                              ),
                      borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_rounded,
                                size: 16,
                                color: expertPhone.isNotEmpty
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Text('📞 התקשר למומחה',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: expertPhone.isNotEmpty
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                      width: 1,
                      height: 30,
                      color: Colors.grey.shade200),
                  Expanded(
                    child: InkWell(
                      onTap: chatRoomId.isNotEmpty
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    receiverId: expertId,
                                    receiverName: expertName,
                                  ),
                                ),
                              )
                          : null,
                      borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color: chatRoomId.isNotEmpty
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Text('💬 צ\'אט מהיר',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: chatRoomId.isNotEmpty
                                        ? const Color(0xFF6366F1)
                                        : const Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Footer: details link (non-active) ─────────────────────
          if (!isActive) ...[
            InkWell(
              onTap: widget.onDetails,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(24)),
                  border: Border(
                      top: BorderSide(
                          color: Colors.grey.shade100, width: 1)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('פרטי הזמנה',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500)),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Booking step indicator (Uber-style horizontal tracker) ─────────────────

class _BookingStepIndicator extends StatelessWidget {
  final int currentStep; // 0–3

  const _BookingStepIndicator({required this.currentStep});

  static const _steps = ['התקבלה', 'בדרך', 'בעבודה', 'הושלם'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final filled = i ~/ 2 < currentStep;
          return Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: filled
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final step     = i ~/ 2;
        final isActive = step == currentStep;
        final isDone   = step < currentStep;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width:  isActive ? 30 : 22,
              height: isActive ? 30 : 22,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF6366F1)
                    : isActive
                        ? Colors.white
                        : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
                border: isActive
                    ? Border.all(
                        color: const Color(0xFF6366F1), width: 2.5)
                    : null,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 12)
                    : isActive
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6366F1),
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _steps[step],
              style: TextStyle(
                  fontSize: 9,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? const Color(0xFF6366F1)
                      : isDone
                          ? const Color(0xFF6366F1).withValues(alpha: 0.7)
                          : const Color(0xFF94A3B8)),
            ),
          ],
        );
      }),
    );
  }
}

// ── Expert job card ────────────────────────────────────────────────────────

class _ExpertJobCard extends StatefulWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final void Function(String jobId, String chatRoomId) onMarkDone;
  final void Function(String jobId) onCancel;
  final VoidCallback onDetails;
  final VoidCallback onReceipt;
  final VoidCallback? onRate;

  const _ExpertJobCard({
    super.key,
    required this.job,
    required this.jobId,
    required this.onMarkDone,
    required this.onCancel,
    required this.onDetails,
    required this.onReceipt,
    this.onRate,
  });

  @override
  State<_ExpertJobCard> createState() => _ExpertJobCardState();
}

class _ExpertJobCardState extends State<_ExpertJobCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;
  Timer? _workTimer;
  bool _startingWork = false;

  static const _terminalStatuses = {
    'cancelled', 'cancelled_with_penalty', 'refunded',
    'split_resolved', 'completed',
  };

  // Statuses that get the lightweight "cancelled" card.
  // 'completed' is intentionally excluded — completed jobs need the full card
  // so the provider can see and tap the "Leave review" button.
  static const _cancelledStatuses = {
    'cancelled', 'cancelled_with_penalty', 'refunded', 'split_resolved',
  };

  bool get _isTerminal =>
      _terminalStatuses.contains(widget.job['status'] as String? ?? '');

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Only animate for live active jobs — terminal cards don't need the ticker.
    if (!_isTerminal) {
      _pulseCtrl.repeat(reverse: true);
      _workTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _workTimer?.cancel();
    super.dispose();
  }

  Future<void> _markWorkStarted() async {
    setState(() => _startingWork = true);
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'workStartedAt': FieldValue.serverTimestamp(),
        'expertOnWay':   false,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('שגיאה: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _startingWork = false);
    }
  }

  Future<void> _navigateToJob(String? lat, String? lng, String address) async {
    Uri uri;
    if (lat != null && lng != null) {
      // Try Waze first (field workers prefer it), fallback to Google Maps URL
      uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    } else if (address.isNotEmpty) {
      final enc = Uri.encodeComponent(address);
      uri = Uri.parse('https://maps.google.com/?q=$enc');
    } else {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final job    = widget.job;
    final status = job['status'] as String? ?? '';

    // ── Guard: render a lightweight read-only card for terminal states ──────
    // This prevents any crash caused by null fields that active-only code paths
    // expect, and stops the animation controller from ticking needlessly.
    if (_cancelledStatuses.contains(status)) {
      final customerName = job['customerName'] as String? ?? 'לקוח';
      final customerId   = job['customerId']   as String? ?? '';
      final amount = ((job['netAmountForExpert'] ??
                  job['totalPaidByCustomer'] ??
                  job['totalAmount'] ?? 0.0) as num)
              .toDouble();
      DateTime? apptDate;
      if (job['appointmentDate'] is Timestamp) {
        apptDate = (job['appointmentDate'] as Timestamp).toDate();
      }
      final dateStr = apptDate != null
          ? DateFormat('dd/MM/yy').format(apptDate)
          : '';
      // Status-specific label
      const cancelledBg = Color(0xFFFFF5F5);
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cancelledBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _ProfileAvatar(uid: customerId, name: customerName, size: 44),
          title: Text(customerName,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Color(0xFF1A1A2E))),
          subtitle: Text(
            [
              if (dateStr.isNotEmpty) dateStr,
              if (amount > 0) '₪${amount.toStringAsFixed(0)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusBadge(status),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onDetails,
                child: const Icon(Icons.info_outline_rounded,
                    size: 18, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      );
    }
    // ────────────────────────────────────────────────────────────────────────

    final customerId   = job['customerId']   as String? ?? '';
    final customerName = job['customerName'] as String? ?? 'לקוח';
    final customerPhone = job['customerPhone'] as String? ?? '';
    final chatRoomId   = job['chatRoomId']   as String? ?? '';
    final address      = job['location']     as String? ?? '';
    final clientLat    = (job['clientLat'] as num?)?.toDouble().toString();
    final clientLng    = (job['clientLng'] as num?)?.toDouble().toString();
    final netAmount    = (job['netAmountForExpert'] ??
            job['totalPaidByCustomer'] ??
            job['totalAmount'] ??
            0.0)
        .toDouble();
    final workStartedTs = job['workStartedAt'] as Timestamp?;
    final workMinutes   = workStartedTs != null
        ? DateTime.now().difference(workStartedTs.toDate()).inMinutes
        : 0;

    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptStr  = apptDate != null
        ? DateFormat('dd/MM/yy').format(apptDate)
        : (() {
            if (job['createdAt'] is Timestamp) {
              return DateFormat('dd/MM/yy')
                  .format((job['createdAt'] as Timestamp).toDate());
            }
            return 'תאריך לא ידוע';
          })();
    final apptTime = job['appointmentTime'] as String? ?? '';

    final isPending   = status == 'paid_escrow';
    final isWaiting   = status == 'expert_completed';
    final isCompleted = status == 'completed';
    final isActive    = isPending || isWaiting;
    final hasNav      = address.isNotEmpty || (clientLat != null && clientLng != null);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => showCustomerProfileSheet(
                    context, customerId, customerName),
                child: _ProfileAvatar(
                    uid: customerId, name: customerName, size: 50),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => showCustomerProfileSheet(
                      context, customerId, customerName),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1A1A2E))),
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                            apptTime.isNotEmpty
                                ? '$apptStr · $apptTime'
                                : apptStr,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8))),
                      ]),
                    ],
                  ),
                ),
              ),
              _StatusBadge(status),
            ]),
          ),

          // ── Client address + phone row ──────────────────────────────
          if (address.isNotEmpty || customerPhone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: Color(0xFF6366F1)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(address,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF475569))),
                        ),
                      ]),
                    if (address.isNotEmpty && customerPhone.isNotEmpty)
                      const SizedBox(height: 4),
                    if (customerPhone.isNotEmpty)
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('tel:$customerPhone'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Row(children: [
                          const Icon(Icons.phone_rounded,
                              size: 13, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Text(customerPhone,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Net amount strip ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCompleted
                  ? const Color(0xFFF0FFF4)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: isCompleted
                  ? Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.savings_rounded,
                    size: isCompleted ? 18 : 14,
                    color: isCompleted
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isCompleted ? 'סה"כ הרווח' : 'הרווח הצפוי',
                    style: TextStyle(
                      fontSize: isCompleted ? 13 : 12,
                      fontWeight: isCompleted
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isCompleted
                          ? const Color(0xFF15803D)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ]),
                Text(
                  '₪${netAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isCompleted ? 20 : 16,
                    color: isCompleted
                        ? const Color(0xFF15803D)
                        : const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),

          // ── Work-in-progress timer ────────────────────────────────
          if (workStartedTs != null && isPending) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Icon(Icons.construction_rounded,
                        size: 14,
                        color: const Color(0xFF16A34A)
                            .withValues(alpha: 0.5 + _pulse.value * 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text('עבודה החלה לפני $workMinutes דקות',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF15803D))),
                ]),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Actions ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              children: [

                // pending: navigate + start work + mark done
                if (isPending) ...[

                  // Navigate to Job button
                  if (hasNav) ...[
                    _PrimaryButton(
                      label: 'נווט לעבודה 🚗',
                      icon: Icons.directions_car_rounded,
                      color: const Color(0xFF0F172A),
                      onPressed: () =>
                          _navigateToJob(clientLat, clientLng, address),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Start Work button (only if not yet started)
                  if (workStartedTs == null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          shadowColor: const Color(0xFF6366F1)
                              .withValues(alpha: 0.4),
                        ),
                        icon: _startingWork
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.handyman_rounded, size: 20),
                        label: const Text('הגעתי — התחל עבודה 🛠️',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        onPressed:
                            _startingWork ? null : _markWorkStarted,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Mark done (after work started)
                  _PrimaryButton(
                    label: 'סיימתי את העבודה',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () =>
                        widget.onMarkDone(widget.jobId, chatRoomId),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _QuickActionChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'צ׳אט עם לקוח',
                        onPressed: chatRoomId.isNotEmpty
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      receiverId: customerId,
                                      receiverName: customerName,
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickActionChip(
                        icon: Icons.cancel_outlined,
                        label: 'בטל הזמנה',
                        color: const Color(0xFFFEF2F2),
                        iconColor: Colors.red,
                        onPressed: () => widget.onCancel(widget.jobId),
                      ),
                    ),
                  ]),
                ],

                // waiting for client release
                if (isWaiting) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_top_rounded,
                              size: 15, color: Color(0xFF3B82F6)),
                          SizedBox(width: 6),
                          Text('ממתין לאישור הלקוח',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF3B82F6),
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                ],

                // completed: receipt + provider review button
                if (isCompleted) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, size: 20),
                      label: const Text('הצג קבלה',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: widget.onReceipt,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 7-day double-blind review window.
                  // completedAt is written by _handleCompleteJob; fall back to
                  // createdAt so old jobs that pre-date this field still work.
                  Builder(builder: (ctx) {
                    // Use `tryCast` pattern instead of `as Timestamp?` —
                    // a serverTimestamp sentinel (FieldValue) that hasn't
                    // resolved yet is not a Timestamp and would throw _CastError.
                    Timestamp? toTs(dynamic v) => v is Timestamp ? v : null;
                    final completedTs =
                        toTs(job['completedAt']) ?? toTs(job['createdAt']);
                    final windowOpen = completedTs == null ||
                        DateTime.now()
                                .difference(completedTs.toDate())
                                .inDays <
                            7;
                    final reviewed = job['providerReviewDone'] == true;

                    if (reviewed) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FFF4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 14, color: Color(0xFF16A34A)),
                            SizedBox(width: 6),
                            Text('ביקורת נשלחה — תודה!',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF16A34A))),
                          ],
                        ),
                      );
                    }
                    if (windowOpen) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.star_rounded, size: 20),
                          label: const Text('שתף חוות דעת ⭐',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          onPressed: widget.onRate,
                        ),
                      );
                    }
                    // Window expired — provider did not review within 7 days
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_clock_rounded,
                              size: 14, color: Color(0xFF94A3B8)),
                          SizedBox(width: 6),
                          Text('חלון הביקורת פג (7 ימים)',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8))),
                        ],
                      ),
                    );
                  }),
                ],

                // other statuses (cancelled / disputed)
                if (!isActive && !isCompleted) ...[
                  _StatusBadge(status),
                ],
              ],
            ),
          ),

          // ── Footer ───────────────────────────────────────────────────
          InkWell(
            onTap: widget.onDetails,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(
                    top: BorderSide(color: Colors.grey.shade100, width: 1)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('פרטי הזמנה',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500)),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Expert earnings summary bar ────────────────────────────────────────────

class _ExpertEarningsSummary extends StatelessWidget {
  final double expectedEarnings;
  final int    activeCount;

  const _ExpertEarningsSummary({
    required this.expectedEarnings,
    required this.activeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('סה"כ רווח צפוי',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              Text(
                '₪${expectedEarnings.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$activeCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const Text('הזמנות',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ]),
    );
  }
}

// ── Striped blocked day cell (calendar) ────────────────────────────────────

class _StripedBlockedDay extends StatelessWidget {
  final DateTime day;
  final bool     isSelected;

  const _StripedBlockedDay({required this.day, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.7), width: 1.5),
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _DiagonalStripesPainter(),
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: isSelected ? Colors.redAccent : Colors.red[700],
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagonalStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.12)
      ..strokeWidth = 3;
    const step = 6.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Shared button widgets ──────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: onPressed,
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(double.infinity, 44),
          side: BorderSide(color: color.withValues(alpha: 0.40)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        onPressed: onPressed,
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback? onPressed;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    this.color = const Color(0xFFEEF2FF),
    this.iconColor = const Color(0xFF6366F1),
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: onPressed == null
                ? const Color(0xFFF8FAFC)
                : color,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: onPressed == null
                    ? const Color(0xFF94A3B8)
                    : iconColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: onPressed == null
                        ? const Color(0xFF94A3B8)
                        : iconColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _CustomerProfileSheet, _CustomerRatingRow, and showCustomerProfileSheet
// are defined in lib/widgets/customer_profile_sheet.dart (shared with
// opportunities_screen.dart).
