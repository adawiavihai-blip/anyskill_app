import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'chat_modules/payment_module.dart';
import '../services/payment_service.dart';
import '../services/cancellation_policy_service.dart';
import '../widgets/receipt_sheet.dart';
import 'expert_profile_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const MyBookingsScreen({super.key, this.onGoToSearch});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _isExpertView = false;
  bool _isCalendarView = false;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

  // ── Calendar / availability state ─────────────────────────────────────────
  Set<DateTime> _unavailableDates = {};
  DateTime _calendarFocusedDay = DateTime.now();
  bool _calendarSaving = false;

  // ── Stable streams (initialized once — avoids StreamBuilder re-subscribing
  //    on every setState, which caused a spinner flash after status changes) ──
  late final Stream<QuerySnapshot> _expertStream;
  late final Stream<QuerySnapshot> _customerStream;

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
    _loadUnavailableDates();
  }

  Future<void> _loadUnavailableDates() async {
    if (currentUserId.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(currentUserId).get();
    final List<dynamic> raw = (doc.data()?['unavailableDates'] as List<dynamic>?) ?? [];
    if (mounted) {
      setState(() {
        // תואם לפורמט של edit_profile_screen — ISO string ('YYYY-MM-DD')
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
      // שומר כ-ISO strings בדיוק כמו edit_profile_screen
      final isoStrings = _unavailableDates
          .map((d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}')
          .toList();
      await FirebaseFirestore.instance.collection('users').doc(currentUserId).update({
        'unavailableDates': isoStrings,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("הזמינות עודכנה בהצלחה")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text("שגיאה בשמירה: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _calendarSaving = false);
    }
  }

  // ── Customer: release escrow after expert marks done ─────────────────────
  Future<void> _handleCompleteJob(
      BuildContext context, String jobId, Map<String, dynamic> jobData, double amount) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    final error = await PaymentModule.releaseEscrowFundsWithError(
      jobId: jobId,
      expertId: jobData['expertId'] ?? "",
      expertName: jobData['expertName'] ?? "מומחה",
      customerName: jobData['customerName'] ?? "לקוח",
      totalAmount: amount,
    );

    if (context.mounted) Navigator.pop(context);

    if (error == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("העבודה הושלמה והתשלום שוחרר!")),
        );
        _showRatingDialog(context, jobData['expertId'], jobId);
      }
    } else {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("שגיאה בשחרור התשלום"),
            content: SelectableText(error),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("סגור"))],
          ),
        );
      }
    }
  }

  // ── Expert: mark job as done ──────────────────────────────────────────────
  Future<void> _markJobDone(BuildContext context, String jobId, String chatRoomId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
        'status': 'expert_completed',
        'expertCompletedAt': FieldValue.serverTimestamp(),
      });

      if (chatRoomId.isNotEmpty) {
        final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
        await chatRef.collection('messages').add({
          'senderId': 'system',
          'message': '✅ המומחה סיים את העבודה! לחץ על "אשר ושחרר" כדי לשחרר את התשלום.',
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
          const SnackBar(
              backgroundColor: Colors.green,
              content: Text("סומן כהושלם! הלקוח יאשר את שחרור התשלום.")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text("שגיאה: $e")),
        );
      }
    }
  }

  // ── Customer: cancel booking (policy-aware, only while paid_escrow) ─────
  Future<void> _cancelBooking(
      BuildContext context, String jobId, Map<String, dynamic> job, double amount) async {
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
            Icon(hasPenalty ? Icons.warning_amber_rounded : Icons.cancel_outlined,
                color: hasPenalty ? Colors.orange : Colors.red, size: 22),
            const SizedBox(width: 8),
            const Text("ביטול הזמנה",
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "אזהרה: חלון הביטול החינמי עבר.\n"
                      "לפי מדיניות ${CancellationPolicyService.label(policy)}, "
                      "ביטול כעת יגרור קנס של "
                      "₪${penalty.toStringAsFixed(0)}.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.deepOrange),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "תקבל בחזרה: ₪${refund.toStringAsFixed(0)}\n"
                    "ישולם למומחה: ₪${penalty.toStringAsFixed(0)} (בניכוי עמלה)",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              )
            : Text(
                "האם לבטל את ההזמנה?\n₪${amount.toStringAsFixed(0)} יוחזרו לארנק שלך.",
                textAlign: TextAlign.center,
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("לא, חזור"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: hasPenalty ? Colors.orange : Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
                hasPenalty ? "כן, בטל (קנס ₪${penalty.toStringAsFixed(0)})" : "כן, בטל",
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
        jobId: jobId,
        cancelledBy: 'customer',
      );
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(hasPenalty
              ? "ההזמנה בוטלה — ₪${refund.toStringAsFixed(0)} הוחזרו לארנק"
              : "ההזמנה בוטלה — ₪${amount.toStringAsFixed(0)} הוחזרו לארנק"),
        ));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text("שגיאה בביטול: $e"),
        ));
      }
    }
  }

  // ── Provider: cancel booking (full refund to customer + XP penalty) ───────
  Future<void> _providerCancelBooking(
      BuildContext context, String jobId, Map<String, dynamic> job) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text("ביטול מצד הספק",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "ביטול מצד הספק מחזיר ללקוח 100% מהסכום\n"
          "ויפחית XP מהפרופיל שלך.\n\n"
          "האם להמשיך?",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("לא, חזור"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text("כן, בטל",
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
        jobId: jobId,
        cancelledBy: 'provider',
      );
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          content: Text("ההזמנה בוטלה — הלקוח יקבל החזר מלא"),
        ));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text("שגיאה בביטול: $e"),
        ));
      }
    }
  }

  // ── Customer: open dispute (only after expert marks done) ─────────────────
  Future<void> _openDispute(BuildContext context, String jobId) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("פתיחת מחלוקת", textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "תאר מה הבעיה עם השירות שניתן. הצוות שלנו יבדוק ויחליט תוך 48 שעות.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: "תאר את הבעיה...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("בטל"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(c, true);
            },
            child: const Text("שלח מחלוקת", style: TextStyle(color: Colors.white)),
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
          content: Text("המחלוקת נפתחה — הצוות יצור קשר תוך 48 שעות"),
        ),
      );
    }
  }

  // ── Rating dialog (called after customer releases payment) ────────────────
  void _showRatingDialog(BuildContext context, String expertId, String jobId) {
    double selectedRating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("איך היה השירות?",
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
                      index < selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 35,
                    ),
                    onPressed: () => setDialogState(() => selectedRating = index + 1.0),
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
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final userDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .get();
                  final reviewerName = userDoc.data()?['name'] ?? 'לקוח';
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
                          content: Text("שגיאה בשליחת הביקורת: $e"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text("שלח ביקורת", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Job details bottom sheet ──────────────────────────────────────────────
  void _showJobDetailsSheet(BuildContext context, Map<String, dynamic> job, String jobId) {
    final status = job['status'] ?? '';
    const statusLabels = {
      'paid_escrow':      'ממתין לסיום',
      'expert_completed': 'ממתין לאישור',
      'completed':        'הושלם',
      'cancelled':        'בוטל',
      'disputed':              'במחלוקת',
      'split_resolved':        'נפתר — פשרה',
      'cancelled_with_penalty': 'בוטל (קנס)',
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
            const Text("פרטי הזמנה",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _detailRow(Icons.tag, "מזהה הזמנה", jobId),
            _detailRow(Icons.person_outline, "מומחה", job['expertName'] ?? '—'),
            _detailRow(Icons.person_2_outlined, "לקוח", job['customerName'] ?? '—'),
            _detailRow(Icons.info_outline, "סטטוס", statusLabels[status] ?? status),
            _detailRow(Icons.attach_money, "סכום",
                "₪${(job['totalAmount'] ?? job['totalPaidByCustomer'] ?? 0).toStringAsFixed(0)}"),
            if (job['appointmentDate'] != null)
              _detailRow(Icons.calendar_today, "תאריך",
                  DateFormat('dd/MM/yyyy')
                      .format((job['appointmentDate'] as Timestamp).toDate())),
            if ((job['appointmentTime'] ?? '').toString().isNotEmpty)
              _detailRow(Icons.access_time, "שעה", job['appointmentTime']),
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
          Text("$label: ",
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("הזמנות",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildToggle(),
          Expanded(child: _isCalendarView ? _buildCalendarView() : _buildList()),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          _toggleButton(
            label: "הזמנות שלי",
            active: !_isExpertView && !_isCalendarView,
            onTap: () => setState(() { _isExpertView = false; _isCalendarView = false; }),
          ),
          const SizedBox(width: 8),
          _toggleButton(
            label: "משימות שלי",
            active: _isExpertView && !_isCalendarView,
            onTap: () => setState(() { _isExpertView = true; _isCalendarView = false; }),
          ),
          const SizedBox(width: 8),
          _toggleButton(
            label: "יומן",
            active: _isCalendarView,
            onTap: () => setState(() => _isCalendarView = true),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({required String label, required bool active, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text("ניהול זמינות", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            "לחץ על תאריך כדי לסמן אותו כחסום. לחץ שוב להסרה.",
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
            ),
            child: TableCalendar(
              firstDay: DateTime.now(),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _calendarFocusedDay,
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {CalendarFormat.month: 'חודש'},
              startingDayOfWeek: StartingDayOfWeek.sunday,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(color: Colors.white),
              ),
              selectedDayPredicate: (day) {
                final normalized = DateTime.utc(day.year, day.month, day.day);
                return _unavailableDates.contains(normalized);
              },
              onDaySelected: (selectedDay, focusedDay) {
                final normalized = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
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
              children: (_unavailableDates.toList()..sort()).map((d) => Chip(
                label: Text('${d.day}/${d.month}/${d.year}', style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.red[50],
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => setState(() => _unavailableDates.remove(d)),
              )).toList(),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("שמור שינויים", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _isExpertView ? _expertStream : _customerStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.black));
        }
        if (snapshot.hasError) return Center(child: Text("שגיאה: ${snapshot.error}"));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final jobDoc = snapshot.data!.docs[index];
            final job = jobDoc.data() as Map<String, dynamic>;
            return _isExpertView
                ? _buildExpertJobCard(context, job, jobDoc.id)
                : _buildCustomerBookingCard(context, job, jobDoc.id);
          },
        );
      },
    );
  }

  // ── Customer card ─────────────────────────────────────────────────────────
  Widget _buildCustomerBookingCard(
      BuildContext context, Map<String, dynamic> job, String jobId) {
    DateTime? date;
    if (job['appointmentDate'] is Timestamp) {
      date = (job['appointmentDate'] as Timestamp).toDate();
    }
    final formattedDate =
        date != null ? DateFormat('dd/MM/yyyy').format(date) : "טרם נקבע";
    final status = job['status'] ?? "";
    final amount =
        (job['totalAmount'] ?? job['totalPaidByCustomer'] ?? job['amount'] ?? 0.0)
            .toDouble();

    return _jobCard(
      onDetailsTap: () => _showJobDetailsSheet(context, job, jobId),
      header: ListTile(
        title: Text(job['expertName'] ?? "מומחה",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("$formattedDate | ${job['appointmentTime'] ?? ''}"),
        trailing: _buildStatusChip(status),
      ),
      actions: [
        if (status == 'expert_completed') ...[
          _fullButton(
            label: "אישור ביצוע ושחרור תשלום",
            color: Colors.black,
            onPressed: () => _handleCompleteJob(context, jobId, job, amount),
          ),
          _outlinedButton(
            icon: Icons.report_outlined,
            iconColor: Colors.red,
            label: "פתח מחלוקת — יש בעיה",
            borderColor: Colors.red.shade200,
            onPressed: () => _openDispute(context, jobId),
          ),
        ],
        if (status == 'paid_escrow') ...[
          _infoRow(Icons.hourglass_top, Colors.orange, "ממתין לסיום מהמומחה"),
          _outlinedButton(
            icon: Icons.cancel_outlined,
            iconColor: Colors.red,
            label: "ביטול הזמנה (החזר כספי)",
            borderColor: Colors.red.shade200,
            onPressed: () => _cancelBooking(context, jobId, job, amount),
          ),
        ],
        if (status == 'completed' && !(job['isReviewed'] ?? false))
          _outlinedButton(
            icon: Icons.star_outline,
            iconColor: Colors.amber,
            label: "דרג את השירות",
            borderColor: Colors.amber,
            onPressed: () => _showRatingDialog(context, job['expertId'] ?? '', jobId),
          ),
        if (status == 'completed' && (job['isReviewed'] ?? false))
          _infoRow(Icons.check_circle_outline, Colors.green, "ביקורת נשלחה"),
        // ── Receipt + rebook (completed only) ────────────────────────────
        if (status == 'completed') ...[
          _receiptButton(context, job),
          _rebookButton(context, job),
        ],
      ],
      footer: Text("₪$amount",
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
    );
  }

  // ── Expert card ───────────────────────────────────────────────────────────
  Widget _buildExpertJobCard(
      BuildContext context, Map<String, dynamic> job, String jobId) {
    DateTime? date;
    if (job['createdAt'] is Timestamp) {
      date = (job['createdAt'] as Timestamp).toDate();
    }
    final formattedDate =
        date != null ? DateFormat('dd/MM/yyyy').format(date) : "תאריך לא ידוע";
    final status = job['status'] ?? "";
    final netAmount =
        (job['netAmountForExpert'] ?? job['totalPaidByCustomer'] ?? job['totalAmount'] ?? 0.0)
            .toDouble();
    final chatRoomId = job['chatRoomId'] ?? '';

    return _jobCard(
      onDetailsTap: () => _showJobDetailsSheet(context, job, jobId),
      header: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFF0F0F0),
          child: Icon(Icons.person, color: Colors.grey),
        ),
        title: Text(job['customerName'] ?? "לקוח",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("נוצר ב-$formattedDate"),
        trailing: _buildStatusChip(status),
      ),
      actions: [
        if (status == 'paid_escrow') ...[
          _fullButton(
            label: "סיימתי את העבודה",
            color: Colors.green,
            icon: Icons.check_circle_outline,
            onPressed: () => _markJobDone(context, jobId, chatRoomId),
          ),
          _outlinedButton(
            icon: Icons.cancel_outlined,
            iconColor: Colors.red,
            label: "בטל הזמנה (החזר ללקוח)",
            borderColor: Colors.red.shade200,
            onPressed: () => _providerCancelBooking(context, jobId, job),
          ),
        ],
        if (status == 'expert_completed')
          _infoRow(Icons.hourglass_top, Colors.blue, "ממתין לאישור הלקוח"),
        if (status == 'completed') ...[
          _infoRow(Icons.check_circle, Colors.green, "הושלם — התשלום שוחרר"),
          _receiptButton(context, job),
        ],
      ],
      footer: Text("נטו: ₪${netAmount.toStringAsFixed(0)}",
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
    );
  }

  // ── One-click rebook button ───────────────────────────────────────────────
  Widget _rebookButton(BuildContext context, Map<String, dynamic> job) {
    final expertId   = (job['expertId']   ?? '') as String;
    final expertName = (job['expertName'] ?? 'מומחה') as String;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF0F0FF),
          foregroundColor: const Color(0xFF6366F1),
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF6366F1), width: 1),
          ),
        ),
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: Text(
          'הזמן שוב את $expertName',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExpertProfileScreen(expertId: expertId, expertName: expertName),
          ),
        ),
      ),
    );
  }

  // ── Digital receipt button ────────────────────────────────────────────────
  Widget _receiptButton(BuildContext context, Map<String, dynamic> job) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A1A2E),
          minimumSize: const Size(double.infinity, 44),
          side: BorderSide(color: Colors.grey.shade300),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.receipt_long_rounded, size: 17),
        label: const Text("הצג קבלה",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        onPressed: () async {
          // Fetch provider's taxId for the receipt
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
        },
      ),
    );
  }

  // ── Shared card shell ─────────────────────────────────────────────────────
  Widget _jobCard({
    required Widget header,
    required List<Widget> actions,
    required Widget footer,
    VoidCallback? onDetailsTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          header,
          ...actions,
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                footer,
                GestureDetector(
                  onTap: onDetailsTap,
                  child: const Text("פרטים >",
                      style: TextStyle(
                          color: Colors.black,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fullButton(
      {required String label,
      required Color color,
      IconData? icon,
      required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
        icon: icon != null ? Icon(icon, color: Colors.white) : const SizedBox.shrink(),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _outlinedButton(
      {required IconData icon,
      required Color iconColor,
      required String label,
      required Color borderColor,
      required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            side: BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
        icon: Icon(icon, color: iconColor),
        label: Text(label, style: const TextStyle(color: Colors.black)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    const map = {
      'completed':        (Colors.green,  "הושלם"),
      'expert_completed': (Colors.blue,   "ממתין לאישור"),
      'paid_escrow':      (Colors.orange, "בנאמנות"),
      'cancelled':        (Colors.red,    "בוטל"),
      'disputed':         (Colors.red,    "במחלוקת"),
      'refunded':              (Colors.teal,   "הוחזר"),
      'split_resolved':        (Colors.purple, "פשרה"),
      'cancelled_with_penalty': (Colors.deepOrange, "בוטל+קנס"),
    };
    final (color, text) = map[status] ?? (Colors.grey, "בטיפול");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isExpertView ? Icons.work_outline : Icons.calendar_today_outlined,
                size: 56,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isExpertView ? "אין משימות עדיין" : "אין הזמנות עדיין",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              _isExpertView
                  ? "הזמנות מלקוחות יופיעו כאן. ודא שהפרופיל שלך מעודכן עם תחום ומחיר."
                  : "הזמן מומחה והשירות יופיע כאן לאחר מכן",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 28),
            if (!_isExpertView)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text("חפש מומחה", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: widget.onGoToSearch,
              ),
          ],
        ),
      ),
    );
  }
}
