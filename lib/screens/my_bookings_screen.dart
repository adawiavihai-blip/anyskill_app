import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
// QA: וודא שהנתיב תואם למיקום הקובץ payment_module.dart אצלך
import 'chat_modules/payment_module.dart'; 

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  // QA: הוספנו שליחת שמות ל-PaymentModule כדי שההיסטוריה תהיה קריאה
  Future<void> _handleCompleteJob(BuildContext context, String jobId, Map<String, dynamic> jobData, double amount) async {
    // גלגל טעינה
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white))
    );

    // קריאה למודול התשלומים עם כל הנתונים הנדרשים
    bool success = await PaymentModule.releaseEscrowFunds(
      jobId: jobId,
      expertId: jobData['expertId'] ?? "",
      expertName: jobData['expertName'] ?? "מומחה", // שם המאמן
      customerName: jobData['customerName'] ?? "לקוח", // שם הלקוח (אביחי)
      totalAmount: amount,
    );

    if (context.mounted) Navigator.pop(context); // סגירת גלגל טעינה

    if (success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("העבודה הושלמה והתשלום שוחרר!"))
        );
        _showRatingDialog(context, jobData['expertId']);
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.red, content: Text("שגיאה בשחרור התשלום. נסה שוב."))
        );
      }
    }
  }

  void _showRatingDialog(BuildContext context, String expertId) {
    double selectedRating = 5;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("איך היה השירות?", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("דרג את המומחה ב-5 כוכבים"),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(index < selectedRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 35),
                    onPressed: () => setDialogState(() => selectedRating = index + 1.0),
                  );
                }),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('reviews').add({
                    'expertId': expertId,
                    'rating': selectedRating,
                    'createdAt': FieldValue.serverTimestamp(),
                    'customerId': FirebaseAuth.instance.currentUser?.uid,
                  });
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("שלח דירוג", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("ההזמנות שלי", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('jobs')
            .where('customerId', isEqualTo: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.black));
          if (snapshot.hasError) return Center(child: Text("שגיאה: ${snapshot.error}"));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState(context);

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var jobDoc = snapshot.data!.docs[index];
              var job = jobDoc.data() as Map<String, dynamic>;
              return _buildBookingCard(context, job, jobDoc.id);
            },
          );
        },
      ),
    );
  }

  Widget _buildBookingCard(BuildContext context, Map<String, dynamic> job, String jobId) {
    DateTime? date;
    if (job['appointmentDate'] is Timestamp) {
      date = (job['appointmentDate'] as Timestamp).toDate();
    }
    
    String formattedDate = date != null ? DateFormat('dd/MM/yyyy').format(date) : "טרם נקבע";
    String status = job['status'] ?? "";
    double amount = (job['totalAmount'] ?? job['amount'] ?? 0.0).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(job['expertName'] ?? "מומחה", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("$formattedDate | ${job['appointmentTime'] ?? ''}"),
            trailing: _buildStatusChip(status),
          ),
          if (status == 'paid_escrow')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                // QA: שולחים את כל ה-Map של job כדי לשאוב ממנו את השמות
                onPressed: () => _handleCompleteJob(context, jobId, job, amount),
                child: const Text("אישור ביצוע ושחרור תשלום", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("₪$amount", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                const Text("פרטי הזמנה >", style: TextStyle(color: Colors.black, decoration: TextDecoration.underline)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = status == 'completed' ? Colors.green : (status == 'paid_escrow' ? Colors.blue : Colors.orange);
    String text = status == 'completed' ? "הושלם" : (status == 'paid_escrow' ? "בנאמנות" : "בטיפול");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.calendar_today_outlined, size: 80, color: Colors.grey), const SizedBox(height: 20), const Text("אין הזמנות"), const SizedBox(height: 30), OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("חזור"))]));
  }
}