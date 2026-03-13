import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SystemWalletScreen extends StatefulWidget {
  const SystemWalletScreen({super.key});

  @override
  State<SystemWalletScreen> createState() => _SystemWalletScreenState();
}

class _SystemWalletScreenState extends State<SystemWalletScreen> {
  final TextEditingController _feeController = TextEditingController();

  @override
  void dispose() {
    _feeController.dispose();
    super.dispose();
  }

  // עדכון עמלה לנתיב המדויק ב-Database
  void _updateFee() {
    if (_feeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("נא להזין מספר")));
      return;
    }

    try {
      double feeValue = double.parse(_feeController.text);
      double feePercent = feeValue / 100;

      FirebaseFirestore.instance
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings')
          .set({
        'feePercentage': feePercent,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.black, content: Text("העמלה עודכנה ל-$feeValue%!", style: const TextStyle(color: Colors.amber)))
      );
      
      _feeController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("נא להזין מספר תקין")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("ניהול כספי מערכת", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildTotalBalanceCard()),
          SliverToBoxAdapter(child: _buildFeeControlPanel()),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 30, 20, 10),
              child: Text("פירוט הכנסות מעמלות (זמן אמת)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
          ),
          _buildTransactionHistory(),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildTotalBalanceCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings')
          .snapshots(),
      builder: (context, snap) {
        double totalFees = 0.0;
        if (snap.hasData && snap.data!.exists) {
          totalFees = (snap.data!.get('totalPlatformBalance') ?? 0.0).toDouble();
        }
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(35),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF000000), Color(0xFF434343)]
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))]
          ),
          child: Column(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: Colors.amber, size: 55),
              const SizedBox(height: 15),
              const Text("יתרה נזילה בארנק המערכת", style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 10),
              FittedBox(
                child: Text("₪${NumberFormat('#,###.##').format(totalFees)}", 
                  style: const TextStyle(color: Colors.amber, fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeeControlPanel() {
    return Container(
      padding: const EdgeInsets.all(22),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, size: 20, color: Colors.amber),
              SizedBox(width: 8),
              Text("קביעת אחוז עמלה גלובלי", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(15)),
                  child: TextField(
                    controller: _feeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: "10", suffixText: "%", border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              ElevatedButton(
                onPressed: _updateFee,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("עדכן", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('platform_earnings')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(60.0),
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 15),
                  const Text("אין עמלות רשומות במערכת", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              var tx = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              DateTime date = (tx['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              double commissionAmount = (tx['amount'] ?? 0.0).toDouble();
              
              // QA: שימוש בשדה התיאור החדש שיצרנו ב-PaymentModule
              String description = tx['description'] ?? "עמלה מעסקה: ${tx['jobId']?.substring(0, 8) ?? 'כללי'}";

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.trending_up, color: Colors.green, size: 24),
                  ),
                  title: Text(
                    description, // כאן יופיע "אביחי ➔ סיגלית"
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("סטטוס: התקבל בהצלחה", style: TextStyle(color: Colors.green[700], fontSize: 12)),
                      Text(DateFormat('dd/MM/yyyy | HH:mm').format(date), style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    ],
                  ),
                  trailing: Text(
                    "+₪${commissionAmount.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              );
            },
            childCount: snapshot.data!.docs.length,
          ),
        );
      },
    );
  }
}