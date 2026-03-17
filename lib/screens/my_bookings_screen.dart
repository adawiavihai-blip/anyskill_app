// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'chat_modules/payment_module.dart';
import '../services/payment_service.dart';
import '../services/cancellation_policy_service.dart';
import '../widgets/receipt_sheet.dart';
import '../l10n/app_localizations.dart';
import 'expert_profile_screen.dart';
import 'chat_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const MyBookingsScreen({super.key, this.onGoToSearch});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _isProvider    = false;
  bool _providerLoaded = false;
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
  bool _calendarSaving = false;

  // ── Stable streams ─────────────────────────────────────────────────────────
  late final Stream<QuerySnapshot> _expertStream;
  late final Stream<QuerySnapshot> _customerStream;

  // ── Status buckets ─────────────────────────────────────────────────────────
  static const _activeStatuses  = {'paid_escrow', 'expert_completed', 'disputed'};
  static const _historyStatuses = {
    'completed', 'cancelled', 'refunded', 'split_resolved', 'cancelled_with_penalty',
  };

  @override
  void initState() {
    super.initState();
    _expertStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('expertId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
    _customerStream = FirebaseFirestore.instance
        .collection('jobs')
        .where('customerId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
    _loadProviderStatus();
    _loadUnavailableDates();
  }

  Future<void> _loadProviderStatus() async {
    if (currentUserId.isEmpty) {
      setState(() => _providerLoaded = true);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final data = doc.data() ?? {};
      if (mounted) {
        setState(() {
          _isProvider     = data['isProvider'] == true;
          _providerLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _providerLoaded = true);
    }
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
      _showRatingDialog(context, jobData['expertId'] ?? '', jobId);
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobId)
          .update({
        'status': 'expert_completed',
        'expertCompletedAt': FieldValue.serverTimestamp(),
      });

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

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.green,
              content: Text(strMarkedDone)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('שגיאה: $e')),
        );
      }
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await PaymentModule.cancelWithPolicy(
          jobId: jobId, cancelledBy: 'customer');
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(hasPenalty
              ? 'ההזמנה בוטלה — ₪${refund.toStringAsFixed(0)} הוחזרו לארנק'
              : 'ההזמנה בוטלה — ₪${amount.toStringAsFixed(0)} הוחזרו לארנק'),
        ));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text('שגיאה בביטול: $e')));
      }
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await PaymentModule.cancelWithPolicy(
          jobId: jobId, cancelledBy: 'provider');
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('ההזמנה בוטלה — הלקוח יקבל החזר מלא'),
        ));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text('שגיאה בביטול: $e')));
      }
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

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status': 'disputed',
      'disputeReason': reasonCtrl.text.trim(),
      'disputeOpenedAt': FieldValue.serverTimestamp(),
    });

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
  void _showRatingDialog(
      BuildContext context, String expertId, String jobId) {
    double selectedRating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('איך היה השירות?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                      size: 35,
                    ),
                    onPressed: () =>
                        setDialogState(() => selectedRating = index + 1.0),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 3,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'ספר על החוויה שלך... (אופציונלי)',
                  hintStyle:
                      const TextStyle(color: Colors.grey, fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid ?? '';
                  final userDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .get();
                  final reviewerName =
                      userDoc.data()?['name'] ?? 'לקוח';
                  try {
                    await PaymentService.submitReview(
                      expertId: expertId,
                      reviewerId: uid,
                      rating: selectedRating,
                      comment: commentController.text.trim(),
                      reviewerName: reviewerName,
                    );
                    await FirebaseFirestore.instance
                        .collection('jobs')
                        .doc(jobId)
                        .update({'isReviewed': true});
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('שגיאה בשליחת הביקורת: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('שלח ביקורת',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      length: 2,
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
                    ? const [Tab(text: 'יומן'), Tab(text: 'משימות שלי')]
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
                  _KeepAlivePage(child: _buildCalendarView()),
                  _KeepAlivePage(child: _buildProviderTasksTab()),
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
    return StreamBuilder<QuerySnapshot>(
      stream: _customerStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _BookingsShimmer();
        }
        if (snapshot.hasError) {
          return Center(child: Text('שגיאה: ${snapshot.error}'));
        }

        final all = snapshot.data?.docs ?? [];
        final filtered = all.where((d) {
          final status =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return statusFilter.contains(status);
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
              isExpert: false,
              isHistory: statusFilter == _historyStatuses);
        }

        return _buildGroupedList(filtered, isExpert: false);
      },
    );
  }

  // ── Provider tasks list ────────────────────────────────────────────────────
  Widget _buildProviderTasksTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _expertStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _BookingsShimmer();
        }
        if (snapshot.hasError) {
          return Center(child: Text('שגיאה: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(isExpert: true, isHistory: false);
        }

        return _buildGroupedList(docs, isExpert: true);
      },
    );
  }

  // ── Grouped list ───────────────────────────────────────────────────────────
  Widget _buildGroupedList(List<QueryDocumentSnapshot> docs,
      {required bool isExpert}) {
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
                      onRate: () => _showRatingDialog(
                          context,
                          (doc.data() as Map<String, dynamic>)['expertId'] ??
                              '',
                          doc.id),
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

  // ── Calendar view (provider availability) ─────────────────────────────────
  Widget _buildCalendarView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('ניהול זמינות',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'לחץ על תאריך כדי לסמן אותו כחסום. לחץ שוב להסרה.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10)
              ],
            ),
            child: TableCalendar(
              firstDay: DateTime.now(),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _calendarFocusedDay,
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {
                CalendarFormat.month: 'חודש'
              },
              startingDayOfWeek: StartingDayOfWeek.sunday,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
                todayDecoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.3),
                    shape: BoxShape.circle),
                selectedTextStyle:
                    const TextStyle(color: Colors.white),
              ),
              selectedDayPredicate: (day) {
                final normalized =
                    DateTime.utc(day.year, day.month, day.day);
                return _unavailableDates.contains(normalized);
              },
              onDaySelected: (selectedDay, focusedDay) {
                final normalized = DateTime.utc(
                    selectedDay.year, selectedDay.month, selectedDay.day);
                setState(() {
                  if (_unavailableDates.contains(normalized)) {
                    _unavailableDates.remove(normalized);
                  } else {
                    _unavailableDates.add(normalized);
                  }
                  _calendarFocusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() => _calendarFocusedDay = focusedDay);
              },
            ),
          ),
          if (_unavailableDates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: (_unavailableDates.toList()..sort())
                  .map((d) => Chip(
                        label: Text(
                            '${d.day}/${d.month}/${d.year}',
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.red[50],
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(
                            () => _unavailableDates.remove(d)),
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
                  child: const Text('שמור שינויים',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(
      {required bool isExpert, required bool isHistory}) {
    final icon   = isHistory ? Icons.history_rounded : Icons.work_outline;
    final title  = isExpert
        ? 'אין משימות עדיין'
        : isHistory
            ? 'אין היסטוריית הזמנות'
            : 'אין הזמנות פעילות';
    final subtitle = isExpert
        ? 'הזמנות מלקוחות יופיעו כאן. ודא שהפרופיל שלך מעודכן.'
        : isHistory
            ? 'הזמנות שהושלמו יופיעו כאן.'
            : 'הזמן מומחה ותראה את ההזמנה שלך כאן.';

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
                label: const Text('חפש מומחה',
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

// ── Customer booking card ──────────────────────────────────────────────────

class _CustomerBookingCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final status     = job['status'] as String? ?? '';
    final expertId   = job['expertId']   as String? ?? '';
    final expertName = job['expertName'] as String? ?? 'מומחה';
    final amount     = (job['totalAmount'] ??
            job['totalPaidByCustomer'] ??
            job['amount'] ??
            0.0)
        .toDouble();

    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptStr = apptDate != null
        ? DateFormat('dd/MM/yy').format(apptDate)
        : 'טרם נקבע';
    final apptTime = job['appointmentTime'] as String? ?? '';

    final chatRoomId = job['chatRoomId'] as String? ?? '';
    final isCompleted = status == 'completed';
    final isActive    = status == 'paid_escrow' || status == 'expert_completed';
    final isReviewed  = job['isReviewed'] == true;

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

          // ── Amount strip ────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

          // ── Action buttons ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              children: [
                // expert_completed → release payment (primary CTA)
                if (status == 'expert_completed') ...[
                  _PrimaryButton(
                    label: 'אשר ושחרר תשלום',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () => onCompleteJob(amount),
                  ),
                  const SizedBox(height: 8),
                  _SecondaryButton(
                    label: 'יש בעיה — פתח מחלוקת',
                    icon: Icons.report_outlined,
                    color: Colors.red,
                    onPressed: onDispute,
                  ),
                ],

                // paid_escrow → quick-chat + cancel
                if (status == 'paid_escrow') ...[
                  Row(children: [
                    Expanded(
                      child: _QuickActionChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'צ׳אט מהיר',
                        onPressed: chatRoomId.isNotEmpty
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickActionChip(
                        icon: Icons.cancel_outlined,
                        label: 'בטל הזמנה',
                        color: const Color(0xFFFEF2F2),
                        iconColor: Colors.red,
                        onPressed: () => onCancel(amount),
                      ),
                    ),
                  ]),
                ],

                // completed → rebook (primary CTA) + receipt + rate
                if (isCompleted) ...[
                  _PrimaryButton(
                    label: 'הזמן שוב את $expertName',
                    icon: Icons.replay_rounded,
                    color: const Color(0xFF6366F1),
                    onPressed: onRebook,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _QuickActionChip(
                        icon: Icons.receipt_long_rounded,
                        label: 'קבלה',
                        onPressed: onReceipt,
                      ),
                    ),
                    if (!isReviewed) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickActionChip(
                          icon: Icons.star_outline_rounded,
                          label: 'דרג',
                          color: const Color(0xFFFFFBEB),
                          iconColor: Colors.amber,
                          onPressed: onRate,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 8),
                      const Expanded(
                        child: _QuickActionChip(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'ביקורת נשלחה',
                          color: Color(0xFFF0FFF4),
                          iconColor: Color(0xFF16A34A),
                          onPressed: null,
                        ),
                      ),
                    ],
                  ]),
                ],
              ],
            ),
          ),

          // ── Footer: details link ────────────────────────────────────
          InkWell(
            onTap: onDetails,
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
      ),
    );
  }
}

// ── Expert job card ────────────────────────────────────────────────────────

class _ExpertJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final void Function(String jobId, String chatRoomId) onMarkDone;
  final void Function(String jobId) onCancel;
  final VoidCallback onDetails;
  final VoidCallback onReceipt;

  const _ExpertJobCard({
    super.key,
    required this.job,
    required this.jobId,
    required this.onMarkDone,
    required this.onCancel,
    required this.onDetails,
    required this.onReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final status       = job['status'] as String? ?? '';
    final customerId   = job['customerId']   as String? ?? '';
    final customerName = job['customerName'] as String? ?? 'לקוח';
    final chatRoomId   = job['chatRoomId']   as String? ?? '';
    final netAmount    = (job['netAmountForExpert'] ??
            job['totalPaidByCustomer'] ??
            job['totalAmount'] ??
            0.0)
        .toDouble();

    DateTime? createdDate;
    if (job['createdAt'] is Timestamp) {
      createdDate = (job['createdAt'] as Timestamp).toDate();
    }
    final dateStr = createdDate != null
        ? DateFormat('dd/MM/yy').format(createdDate)
        : 'תאריך לא ידוע';

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _ProfileAvatar(uid: customerId, name: customerName, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1A1A2E))),
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(dateStr,
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

          // ── Net amount strip ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FFF4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [
                  Icon(Icons.savings_rounded,
                      size: 14, color: Color(0xFF16A34A)),
                  SizedBox(width: 5),
                  Text('הרווח שלך',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF16A34A))),
                ]),
                Text('₪${netAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF16A34A))),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Actions ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              children: [
                if (status == 'paid_escrow') ...[
                  _PrimaryButton(
                    label: 'סיימתי את העבודה',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () => onMarkDone(jobId, chatRoomId),
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
                        onPressed: () => onCancel(jobId),
                      ),
                    ),
                  ]),
                ],

                if (status == 'expert_completed') ...[
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

                if (status == 'completed') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FFF4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 15, color: Color(0xFF16A34A)),
                          SizedBox(width: 6),
                          Text('הושלם — התשלום שוחרר',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                  const SizedBox(height: 8),
                  _QuickActionChip(
                    icon: Icons.receipt_long_rounded,
                    label: 'הצג קבלה',
                    onPressed: onReceipt,
                  ),
                ],
              ],
            ),
          ),

          // ── Footer ───────────────────────────────────────────────────
          InkWell(
            onTap: onDetails,
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
