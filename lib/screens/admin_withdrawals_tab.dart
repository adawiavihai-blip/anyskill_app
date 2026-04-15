// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Admin tab for managing pending withdrawal requests. Self-contained.
class AdminWithdrawalsTab extends StatelessWidget {
  const AdminWithdrawalsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .limit(100)
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

                    _detailRow(Icons.account_balance_outlined, "בנק", w['bankName']),
                    _detailRow(Icons.tag,                       "חשבון", w['accountNumber']),
                    _detailRow(Icons.fork_right,                "סניף", w['branchNumber']),
                    const SizedBox(height: 14),

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

  static Widget _detailRow(IconData icon, String label, dynamic value) {
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
}
