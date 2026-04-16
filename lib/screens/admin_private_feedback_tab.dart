import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Admin tab showing reviews that contain private admin-only comments.
/// Self-contained — queries Firestore independently.
class AdminPrivateFeedbackTab extends StatelessWidget {
  const AdminPrivateFeedbackTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('שגיאה בטעינת ביקורות',
              style: TextStyle(color: Colors.grey[500])));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = (snap.data?.docs ?? []).where((doc) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          final msg = d['privateAdminComment']?.toString() ?? '';
          return msg.trim().isNotEmpty;
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 52, color: Colors.grey),
                SizedBox(height: 12),
                Text('אין הודעות פרטיות למנהל',
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
            final reviewerName   = d['reviewerName']?.toString()       ?? '—';
            final privateComment = d['privateAdminComment']?.toString() ?? '';
            final overallRating  = (d['overallRating'] as num?)?.toDouble()
                ?? (d['rating'] as num?)?.toDouble()
                ?? 0.0;
            final isPublished    = d['isPublished'] as bool? ?? true;
            final ts             = d['createdAt'] ?? d['timestamp'];
            final timeStr = ts is Timestamp
                ? DateFormat('dd/MM/yy HH:mm', 'he').format(ts.toDate())
                : '—';
            final isClientReview = d['isClientReview'] as bool? ?? true;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFCD34D)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPublished
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isPublished ? 'פורסם' : 'ממתין',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isPublished
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              overallRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFBBF24)),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.star_rounded,
                                size: 14, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 8),
                            Text(
                              isClientReview ? 'לקוח→מומחה' : 'מומחה→לקוח',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'מאת: $reviewerName',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        privateComment,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF92400E)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeStr,
                      textAlign: TextAlign.right,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
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
}
