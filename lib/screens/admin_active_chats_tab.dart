import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_chat_view_screen.dart';

/// Admin tab showing active jobs with chat access. Self-contained.
class AdminActiveChatsTab extends StatelessWidget {
  const AdminActiveChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', whereIn: ['paid_escrow', 'disputed', 'expert_completed'])
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('שגיאה בטעינת הזמנות פעילות',
              style: TextStyle(color: Colors.grey[500])));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('אין עבודות פעילות כרגע',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d          = docs[i].data()! as Map<String, dynamic>;
            final status     = d['status'] as String? ?? '';
            final amount     = (d['totalAmount'] as num? ?? 0).toDouble();
            final expertId   = d['expertId']   as String? ?? '';
            final customerId = d['customerId'] as String? ?? '';
            final expertName   = d['expertName']   as String? ?? expertId;
            final customerName = d['customerName'] as String? ?? customerId;

            final ids = [expertId, customerId]..sort();
            final chatRoomId = ids.join('_');

            final isDisputed  = status == 'disputed';
            final statusColor = isDisputed
                ? Colors.red
                : status == 'paid_escrow'
                    ? const Color(0xFF10B981)
                    : Colors.orange;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDisputed
                        ? Colors.red.shade100
                        : Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '₪${amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.build_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(expertName,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 16),
                      const Icon(Icons.person_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(customerName,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDisputed
                            ? Colors.red
                            : const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_rounded,
                          color: Colors.white, size: 16),
                      label: const Text("צפה בצ'אט",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminChatViewScreen(
                            chatRoomId:   chatRoomId,
                            providerName: expertName,
                            customerName: customerName,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
