// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../chat_modules/payment_module.dart';
import '../../services/cancellation_policy_service.dart';
import '../../widgets/receipt_sheet.dart';
import '../../l10n/app_localizations.dart';
import '../review_screen.dart';

/// Static utility class containing all booking business-logic actions.
///
/// Extracted from my_bookings_screen.dart — each method is a standalone
/// async action that takes its required context and data as parameters.
class BookingActions {
  BookingActions._(); // prevent instantiation

  // ── Loading overlay helpers ─────────────────────────────────────────────
  static BuildContext? _loadingDialogCtx;

  static void _showLoadingOverlay(BuildContext context) {
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

  static void _hideLoadingOverlay() {
    debugPrint('QA: Dismissing loading dialog');
    final ctx = _loadingDialogCtx;
    _loadingDialogCtx = null;
    if (ctx != null && ctx.mounted && Navigator.canPop(ctx)) {
      Navigator.of(ctx).pop();
    }
  }

  // ── Customer release escrow ─────────────────────────────────────────────
  static Future<void> handleCompleteJob(
    BuildContext context,
    String jobId,
    Map<String, dynamic> jobData,
    double amount,
  ) async {
    // Capture l10n before any await (async-gap safety).
    final l10n = AppLocalizations.of(context);

    _showLoadingOverlay(context);

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
      // dismissing the overlay and showing success.
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
          // Stamp completedAt so the 7-day review window can be calculated.
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
      debugPrint('QA: Unexpected error in handleCompleteJob: $e');
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
            jobId: jobId,
            revieweeId: jobData['expertId']?.toString() ?? '',
            revieweeName: jobData['expertName']?.toString() ?? 'מומחה',
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

  // ── Expert mark done ──────────────────────────────────────────────────
  static Future<void> markJobDone(
    BuildContext context,
    String jobId,
    String chatRoomId,
  ) async {
    final strMarkedDone = AppLocalizations.of(context).markedDoneSuccess;
    // CRITICAL: use rootNavigator: true.
    // showDialog() pushes to the ROOT navigator (its default useRootNavigator=true).
    // The app wraps tabs in _nestedTab() nested navigators, so Navigator.of(context)
    // without rootNavigator would get the NESTED navigator — pop() would then
    // pop the wrong route and leave the loading dialog open forever ("freeze").
    final nav = Navigator.of(context, rootNavigator: true);
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
      if (nav.canPop()) nav.pop();
    }
  }

  // ── Customer cancel ───────────────────────────────────────────────────
  static Future<void> cancelBooking(
    BuildContext context,
    String jobId,
    Map<String, dynamic> job,
    double amount,
  ) async {
    final penalty = CancellationPolicyService.penaltyAmountFor(job);
    final hasPenalty = penalty > 0;
    final refund = amount - penalty;
    final policy = job['cancellationPolicy'] as String? ?? 'flexible';

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

    final nav = Navigator.of(context, rootNavigator: true);
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

  // ── Provider cancel ───────────────────────────────────────────────────
  static Future<void> providerCancelBooking(
    BuildContext context,
    String jobId,
    Map<String, dynamic> job,
  ) async {
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

    final nav = Navigator.of(context, rootNavigator: true);
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

  // ── Open dispute ──────────────────────────────────────────────────────
  static Future<void> openDispute(
    BuildContext context,
    String jobId,
  ) async {
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

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final reason = reasonCtrl.text.trim();

    await FirebaseFirestore.instance.collection('jobs').doc(jobId).update({
      'status': 'disputed',
      'disputeReason': reason,
      'disputeOpenedAt': FieldValue.serverTimestamp(),
      'disputerId': uid,
    });

    // ── Activity log → Admin Live Feed ───────────────────────────────
    FirebaseFirestore.instance.collection('activity_log').add({
      'type': 'new_dispute',
      'title': '⚖️ מחלוקת חדשה נפתחה',
      'detail': reason.isNotEmpty ? reason : '(ללא פירוט)',
      'jobId': jobId,
      'disputerId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'priority': 'high',
      'expireAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30))),
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

  // ── Job details bottom sheet ──────────────────────────────────────────
  static void showJobDetailsSheet(
    BuildContext context,
    Map<String, dynamic> job,
    String jobId,
  ) {
    final status = job['status'] ?? '';
    const statusLabels = {
      'paid_escrow': 'ממתין לסיום',
      'expert_completed': 'ממתין לאישור',
      'completed': 'הושלם',
      'cancelled': 'בוטל',
      'disputed': 'במחלוקת',
      'split_resolved': 'נפתר — פשרה',
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

  static Widget _detailRow(IconData icon, String label, String value) {
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

  // ── Receipt helper ────────────────────────────────────────────────────
  static Future<void> showReceiptFor(
    BuildContext context,
    Map<String, dynamic> job,
  ) async {
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
}
