// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin tab for managing Academy courses. Self-contained.
class AdminAcademyManagementTab extends StatelessWidget {
  const AdminAcademyManagementTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('courses')
          .orderBy('order')
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('שגיאה בטעינת קורסים',
              style: TextStyle(color: Colors.grey[500])));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ── Summary card
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_rounded, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${docs.length} קורסים פעילים',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const Text('AnySkill Academy',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            // ── Course list
            if (docs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('אין קורסים עדיין. הוסף קורסים ל-Firestore בקולקציית courses.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
                ),
              )
            else
              ...docs.map((doc) {
                final d           = doc.data() as Map<String, dynamic>? ?? {};
                final title       = d['title']?.toString()       ?? '—';
                final category    = d['category']?.toString()    ?? '';
                final duration    = d['duration']?.toString()    ?? '';
                final order       = (d['order'] as num? ?? 0).toInt();
                final xpReward    = (d['xpReward'] as num? ?? 200).toInt();
                final quizCount   = (d['quizQuestions'] as List? ?? []).length;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('#$order',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (category.isNotEmpty)
                                  _miniChip(category, const Color(0xFF6366F1)),
                                if (duration.isNotEmpty)
                                  _miniChip('⏱ $duration', Colors.teal),
                                _miniChip('+$xpReward XP', Colors.amber.shade700),
                                _miniChip('$quizCount שאלות', Colors.grey.shade600),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 20),
                        tooltip: 'מחק קורס',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('מחיקת קורס'),
                              content: Text('למחוק את הקורס "$title"?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('ביטול')),
                                TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('מחק',
                                        style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance
                                .collection('courses')
                                .doc(doc.id)
                                .delete();
                          }
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  static Widget _miniChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}
