import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class ExpertProfileScreen extends StatefulWidget {
  final String expertId;
  final String expertName;

  const ExpertProfileScreen({super.key, required this.expertId, required this.expertName});

  @override
  State<ExpertProfileScreen> createState() => _ExpertProfileScreenState();
}

class _ExpertProfileScreenState extends State<ExpertProfileScreen> {
  bool _isProcessing = false;

  String _getChatRoomId(String uid1, String uid2) {
    List<String> ids = [uid1, uid2];
    ids.sort();
    return ids.join("_");
  }

  Future<void> _processEscrowPayment(BuildContext context, double totalPrice) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final firestore = FirebaseFirestore.instance;
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
    final String chatRoomId = _getChatRoomId(currentUserId, widget.expertId);

    double commission = totalPrice * 0.10;
    double expertNetEarnings = totalPrice - commission;

    try {
      await firestore.runTransaction((transaction) async {
        DocumentReference customerRef = firestore.collection('users').doc(currentUserId);
        DocumentSnapshot customerSnap = await transaction.get(customerRef);
        double currentBalance = (customerSnap['balance'] ?? 0.0).toDouble();

        if (currentBalance < totalPrice) {
          throw "אין מספיק יתרה בארנק לביצוע ההזמנה";
        }

        DocumentReference jobRef = firestore.collection('jobs').doc();
        transaction.set(jobRef, {
          'jobId': jobRef.id,
          'chatRoomId': chatRoomId,
          'customerId': currentUserId,
          'customerName': customerSnap['name'] ?? "",
          'expertId': widget.expertId,
          'expertName': widget.expertName,
          'totalPaidByCustomer': totalPrice,
          'commissionAmount': commission,
          'netAmountForExpert': expertNetEarnings,
          'status': 'paid_escrow',
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.update(customerRef, {'balance': FieldValue.increment(-totalPrice)});

        transaction.set(firestore.collection('platform_earnings').doc(), {
          'jobId': jobRef.id,
          'amount': commission,
          'sourceExpertId': widget.expertId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending_escrow',
        });

        transaction.set(firestore.collection('transactions').doc(), {
          'userId': currentUserId,
          'amount': -totalPrice,
          'title': "תשלום מאובטח: ${widget.expertName}",
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'escrow'
        });
      });

      // קריאה לפונקציה המתוקנת
      await _sendSystemNotification(chatRoomId, totalPrice, expertNetEarnings, currentUserId);

      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green, 
          content: Text("התשלום הופקד בנאמנות! הודעה נשלחה למומחה.")
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // פונקציה משודרגת - פותרת את בעיית היעלמות הצ'אטים
  Future<void> _sendSystemNotification(String chatRoomId, double total, double net, String currentUserId) async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatRoomId);

    // 1. שליחת ההודעה לתוך תת-האוסף messages
    await chatRef.collection('messages').add({
      'senderId': 'system',
      'message': "💰 הזמנה חדשה הופקדה בנאמנות!\nסכום שיעבור אליך בסיום: ₪$net",
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 2. עדכון מסמך הצ'אט הראשי - כולל שדה users כדי שלא ייעלם מהרשימה
    await chatRef.set({
      'lastMessage': "💰 הזמנה חדשה על סך ₪$total",
      'lastMessageTime': FieldValue.serverTimestamp(),
      'users': [currentUserId, widget.expertId], // קריטי כדי שהצ'אט יופיע ברשימה
      'unreadCount_${widget.expertId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(widget.expertId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(widget.expertName, style: const TextStyle(fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                  background: (data['profileImage'] != null && data['profileImage'] != "") 
                      ? Image.network(data['profileImage'], fit: BoxFit.cover)
                      : Container(color: Colors.blueGrey),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(data),
                      const SizedBox(height: 25),
                      const Text("על המומחה", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(data['aboutMe'] ?? "מומחה מוסמך בקהילת AnySkill.", style: const TextStyle(fontSize: 16, height: 1.5)),
                      const SizedBox(height: 30),
                      _buildActionButtons(context, data),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(Map<String, dynamic> data) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              Text(" ${data['rating'] ?? '5.0'}", style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            Text(data['serviceType'] ?? "נותן שירות", style: const TextStyle(color: Colors.grey)),
          ],
        ),
        Text("₪${data['pricePerHour'] ?? '250'} / שעה", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> data) {
    return Column(
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
          onPressed: _isProcessing ? null : () => _showBookingSummary(context, data),
          child: _isProcessing 
              ? const CircularProgressIndicator(color: Colors.white) 
              : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.security, color: Colors.amber), SizedBox(width: 10), Text("הזמן שירות מאובטח (Escrow)", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))]),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 55), side: const BorderSide(color: Colors.blue), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(receiverId: widget.expertId, receiverName: widget.expertName))),
          child: const Text("שלח הודעה לבירור"),
        ),
      ],
    );
  }

  void _showBookingSummary(BuildContext context, Map<String, dynamic> data) {
    double price = (data['pricePerHour'] ?? 250).toDouble();
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25.0), 
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            const Text("סיכום הזמנה מאובטחת", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), 
            const Divider(height: 30), 
            _summaryRow("מחיר השירות", "₪$price"), 
            _summaryRow("הגנת הקונה AnySkill", "כלול במחיר", isGreen: true), 
            const Divider(), 
            _summaryRow("סה\"כ לתשלום (יוקפא בנאמנות)", "₪$price", isBold: true), 
            const SizedBox(height: 30), 
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 55)), 
              onPressed: () => _processEscrowPayment(context, price), 
              child: const Text("אשר תשלום והקפא כסף", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold))
            ), 
            const SizedBox(height: 15)
          ]
        )
      )
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
        children: [
          Text(label, style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)), 
          Text(value, style: TextStyle(fontSize: 16, color: isGreen ? Colors.green : Colors.black, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))
        ]
      )
    );
  }
}