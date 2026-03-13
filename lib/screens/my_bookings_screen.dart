import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_modules/payment_module.dart';
import '../services/payment_service.dart';

class MyBookingsScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const MyBookingsScreen({super.key, this.onGoToSearch});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _isExpertView = false;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

  // ── Customer: release escrow after expert marks done ─────────────────────
  Future<void> _handleCompleteJob(
      BuildContext context, String jobId, Map<String, dynamic> jobData, double amount) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    bool success = await PaymentModule.releaseEscrowFunds(
      jobId: jobId,
      expertId: jobData['expertId'] ?? "",
      expertName: jobData['expertName'] ?? "מומחה",
      customerName: jobData['customerName'] ?? "לקוח",
      totalAmount: amount,
    );

    if (context.mounted) Navigator.pop(context);

    if (success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("העבודה הושלמה והתשלום שוחרר!")),
        );
        _showRatingDialog(context, jobData['expertId'], jobId);
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.red, content: Text("שגיאה בשחרור התשלום. נסה שוב.")),
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

  // ── Customer: cancel booking (only while paid_escrow) ────────────────────
  Future<void> _cancelBooking(
      BuildContext context, String jobId, Map<String, dynamic> job, double amount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("ביטול הזמנה", textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          "האם לבטל את ההזמנה?\n₪${amount.toStringAsFixed(0)} יוחזרו לארנק שלך.",
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
            child: const Text("כן, בטל", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    final success = await PaymentModule.cancelEscrow(
      jobId: jobId,
      customerId: currentUserId,
      totalAmount: amount,
      chatRoomId: job['chatRoomId'] ?? '',
    );

    if (context.mounted) Navigator.pop(context);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: success ? Colors.green : Colors.red,
        content: Text(success
            ? "ההזמנה בוטלה — ₪${amount.toStringAsFixed(0)} הוחזרו לארנק"
            : "שגיאה בביטול. נסה שוב."),
      ));
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

                  await PaymentService.submitReview(
                    expertId: expertId,
                    rating: selectedRating,
                    comment: commentController.text.trim(),
                    reviewerName: reviewerName,
                  );
                  await FirebaseFirestore.instance
                      .collection('jobs')
                      .doc(jobId)
                      .update({'isReviewed': true});

                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("שלח ביקורת", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
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
          Expanded(child: _buildList()),
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
          _toggleButton(label: "הזמנות שלי", active: !_isExpertView,
              onTap: () => setState(() => _isExpertView = false)),
          const SizedBox(width: 8),
          _toggleButton(label: "משימות שלי", active: _isExpertView,
              onTap: () => setState(() => _isExpertView = true)),
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

  Widget _buildList() {
    final stream = _isExpertView
        ? FirebaseFirestore.instance
            .collection('jobs')
            .where('expertId', isEqualTo: currentUserId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('jobs')
            .where('customerId', isEqualTo: currentUserId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
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
        if (status == 'paid_escrow')
          _fullButton(
            label: "סיימתי את העבודה",
            color: Colors.green,
            icon: Icons.check_circle_outline,
            onPressed: () => _markJobDone(context, jobId, chatRoomId),
          ),
        if (status == 'expert_completed')
          _infoRow(Icons.hourglass_top, Colors.blue, "ממתין לאישור הלקוח"),
        if (status == 'completed')
          _infoRow(Icons.check_circle, Colors.green, "הושלם — התשלום שוחרר"),
      ],
      footer: Text("נטו: ₪${netAmount.toStringAsFixed(0)}",
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
    );
  }

  // ── Shared card shell ─────────────────────────────────────────────────────
  Widget _jobCard({
    required Widget header,
    required List<Widget> actions,
    required Widget footer,
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
                const Text("פרטים >",
                    style: TextStyle(
                        color: Colors.black,
                        decoration: TextDecoration.underline)),
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
      'refunded':         (Colors.teal,   "הוחזר"),
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
