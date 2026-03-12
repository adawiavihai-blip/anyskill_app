import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('notifications')
      .where('userId', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();

  Future<void> _markAllRead() async {
    final batch = FirebaseFirestore.instance.batch();
    final unread = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: _uid)
        .where('isRead', isEqualTo: false)
        .get();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> _markRead(String docId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(docId)
        .update({'isRead': true});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text("התראות", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text("נקה הכל", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmpty();
          }

          final docs = snapshot.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final n = doc.data() as Map<String, dynamic>;
              final isRead = n['isRead'] ?? false;
              final title = n['title'] ?? '';
              final body = n['body'] ?? '';
              final type = n['type'] ?? 'general';
              final ts = (n['createdAt'] as Timestamp?)?.toDate();

              return InkWell(
                onTap: () => _markRead(doc.id),
                child: Container(
                  color: isRead ? Colors.white : Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NotifIcon(type: type),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (!isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              body,
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (ts != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(ts),
                                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק\'';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    return DateFormat('dd/MM HH:mm').format(dt);
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
            child: Icon(Icons.notifications_none_outlined, size: 56, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          const Text("אין התראות עדיין",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Text("פעולות בחשבון שלך יופיעו כאן",
              style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }
}

class _NotifIcon extends StatelessWidget {
  final String type;
  const _NotifIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'new_booking'  => (Icons.calendar_today_rounded, Colors.purple),
      'job_status'   => (Icons.check_circle_outline,   Colors.green),
      'chat'         => (Icons.chat_bubble_outline,    Colors.blue),
      _              => (Icons.notifications_outlined,  Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

// ── Static helper: stream unread count for a given uid ─────────────────────
class NotificationBadge extends StatelessWidget {
  final Widget child;
  const NotificationBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Badge(
          label: Text(count.toString()),
          isLabelVisible: count > 0,
          child: child,
        );
      },
    );
  }
}
