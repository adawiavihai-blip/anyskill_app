import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin tab showing Chat Guard bypass attempts and active patterns. Self-contained.
class AdminChatGuardTab extends StatelessWidget {
  const AdminChatGuardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('activity_log')
          .where('type', isEqualTo: 'bypass_attempt')
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: Colors.white, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chat Guard — פעיל',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${docs.length} ניסיונות עקיפה זוהו',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Active patterns
            const Text(
              'פטרנים פעילים',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                '📵 טלפון ישראלי', '💬 וואטסאפ', '💵 מזומן',
                '🔗 wa.me', '📞 טלפון', '💳 ביט',
                '🌐 Outside App', '💸 Cash',
              ].map((label) => Chip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color(0xFFEDE9FE),
                side: const BorderSide(color: Color(0xFF7C3AED), width: 0.5),
              )).toList(),
            ),
            const SizedBox(height: 24),

            // ── Bypass attempts log
            const Text(
              'ניסיונות עקיפה אחרונים',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),

            if (docs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'אין ניסיונות עקיפה עדיין ✅',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final d         = doc.data() as Map<String, dynamic>;
                final userId    = (d['userId']    as String?) ?? '—';
                final flagType  = (d['flagType']  as String?) ?? '—';
                final attempts  = (d['attemptCount'] as num?)?.toInt() ?? 1;
                final ts        = d['timestamp'];
                String timeStr  = '';
                if (ts != null) {
                  try {
                    final dt = (ts as dynamic).toDate() as DateTime;
                    timeStr  = '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2,'0')}';
                  } catch (_) {}
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: attempts >= 3
                      ? const Color(0xFFFFF1F2)
                      : const Color(0xFFFAF5FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: attempts >= 3
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFDDD6FE),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: attempts >= 3
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF7C3AED),
                      child: Text(
                        '$attempts',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      userId.length > 20 ? '${userId.substring(0, 20)}…' : userId,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '$flagType  •  $timeStr',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    trailing: attempts >= 3
                        ? const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18)
                        : null,
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
