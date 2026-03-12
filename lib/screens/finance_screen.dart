import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("החשבון שלי", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          var userData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          double balance = (userData['balance'] ?? 0.0).toDouble();

          return Column(
            children: [
              const SizedBox(height: 20),
              _buildBalanceCard(balance),
              const Padding(
                padding: EdgeInsets.all(15),
                child: Align(
                  alignment: Alignment.centerRight, 
                  child: Text("פעולות אחרונות", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                ),
              ),
              Expanded(child: _buildTransactionList(uid)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.all(30),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue[900]!, Colors.blue[600]!]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          const Text("יתרה אישית זמינה", style: TextStyle(color: Colors.white70, fontSize: 16)),
          Text("₪${balance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTransactionList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('transactions')
          .where(Filter.or(Filter('senderId', isEqualTo: uid), Filter('receiverId', isEqualTo: uid)))
          .snapshots(), 
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("שגיאה: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        var docs = snapshot.data!.docs;
        
        if (docs.isEmpty) {
          return const Center(child: Text("אין עדיין פעולות בחשבונך", style: TextStyle(color: Colors.grey)));
        }

        // מיון ידני
        docs.sort((a, b) {
          var dateA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          var dateB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (dateA == null || dateB == null) return 0;
          return dateB.compareTo(dateA);
        });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var tx = docs[index].data() as Map<String, dynamic>;
            bool isSender = tx['senderId'] == uid;
            DateTime? date = (tx['timestamp'] as Timestamp?)?.toDate();

            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 5),
              // כאן היה התיקון: השתמשתי ב-BorderSide במקום ב-Border.all
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15), 
                side: BorderSide(color: Colors.grey[200]!)
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSender ? Colors.red[50] : Colors.green[50],
                  child: Icon(isSender ? Icons.arrow_upward : Icons.arrow_downward, color: isSender ? Colors.red : Colors.green, size: 20),
                ),
                title: Text(
                  isSender ? "שילמת ל-${tx['receiverName']}" : "קיבלת מ-${tx['senderName']}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(date != null ? DateFormat('dd/MM/yyyy HH:mm').format(date) : "מעבד..."),
                trailing: Text(
                  "${isSender ? '-' : '+'} ₪${tx['amount']}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSender ? Colors.red : Colors.green,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}