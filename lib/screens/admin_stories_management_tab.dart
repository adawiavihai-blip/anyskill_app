// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Admin tab for managing Skills Stories. Self-contained.
class AdminStoriesManagementTab extends StatelessWidget {
  const AdminStoriesManagementTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('שגיאה בטעינת סטוריז',
              style: TextStyle(color: Colors.grey[500])));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded, size: 52, color: Colors.grey),
                SizedBox(height: 12),
                Text('אין סטוריז פעילים כרגע',
                    style: TextStyle(color: Colors.grey, fontSize: 15)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>? ?? {};
            final uid          = docs[i].id;
            final name         = d['providerName']?.toString()   ?? uid;
            final serviceType  = d['serviceType']?.toString()    ?? '';
            final videoUrl     = d['videoUrl']?.toString()       ?? '';
            final ts           = d['timestamp'];
            final timeStr      = ts is Timestamp
                ? DateFormat('dd/MM HH:mm').format(ts.toDate())
                : '—';
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFFEF3C7),
                  backgroundImage: (d['providerAvatar']?.toString() ?? '').startsWith('http')
                      ? NetworkImage(d['providerAvatar'] as String)
                      : null,
                  child: (d['providerAvatar']?.toString() ?? '').startsWith('http')
                      ? null
                      : const Icon(Icons.person, color: Color(0xFFD97706)),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (serviceType.isNotEmpty) Text(serviceType,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1))),
                    Text(timeStr,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (videoUrl.isNotEmpty)
                      Text('📹 ${videoUrl.substring(0, videoUrl.length.clamp(0, 50))}…',
                          style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 22),
                  tooltip: 'מחק סטורי',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('מחיקת סטורי'),
                        content: Text('למחוק את הסטורי של $name?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false),
                              child: const Text('ביטול')),
                          TextButton(onPressed: () => Navigator.pop(context, true),
                              child: const Text('מחק', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseFirestore.instance
                          .collection('stories')
                          .doc(uid)
                          .delete();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🗑️ הסטורי נמחק'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
