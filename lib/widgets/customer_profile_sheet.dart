import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/review_service.dart';

// ── Public entry point ─────────────────────────────────────────────────────

void showCustomerProfileSheet(
    BuildContext context, String customerId, String customerName) {
  if (customerId.isEmpty) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CustomerProfileSheet(
      customerId: customerId,
      customerName: customerName,
    ),
  );
}

// ── Sheet widget ───────────────────────────────────────────────────────────

class CustomerProfileSheet extends StatelessWidget {
  final String customerId;
  final String customerName;

  const CustomerProfileSheet({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                _CustomerAvatar(uid: customerId, name: customerName, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFF1A1A2E)),
                      ),
                      const SizedBox(height: 4),
                      CustomerRatingRow(customerId: customerId),
                    ],
                  ),
                ),
              ]),
            ),
            const Divider(height: 28, indent: 20, endIndent: 20),
            // reviews list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: ReviewService.streamCustomerReviews(customerId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = (snap.data?.docs ?? [])
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['isPublished'] ==
                          true)
                      .toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_outline_rounded,
                                size: 36, color: Color(0xFF6366F1)),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'לקוח חדש',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF1A1A2E)),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'אין עדיין ביקורות על לקוח זה',
                            style: TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 4, endIndent: 4),
                    itemBuilder: (_, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      final rating =
                          (d['overallRating'] as num?)?.toDouble() ??
                              (d['rating'] as num?)?.toDouble() ??
                              0.0;
                      final comment = d['publicComment'] as String? ??
                          d['comment'] as String? ??
                          '';
                      final reviewerName =
                          d['reviewerName'] as String? ?? 'מומחה';
                      final ts = d['createdAt'] as Timestamp?;
                      final dateStr = ts != null
                          ? DateFormat('dd/MM/yy').format(ts.toDate())
                          : '';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              // reviewer initials bubble
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFFEEF2FF),
                                child: Text(
                                  reviewerName.isNotEmpty
                                      ? reviewerName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6366F1)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  reviewerName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Color(0xFF1A1A2E)),
                                ),
                              ),
                              // star rating
                              Row(children: [
                                const Icon(Icons.star_rounded,
                                    size: 14, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 3),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF1A1A2E)),
                                ),
                              ]),
                              if (dateStr.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ]),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                comment,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF475569),
                                    height: 1.4),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Aggregate rating row (shown in sheet header) ───────────────────────────

class CustomerRatingRow extends StatelessWidget {
  final String customerId;
  const CustomerRatingRow({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .get(),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        final rating = (data['customerRating'] as num?)?.toDouble();
        final count = (data['customerReviewsCount'] as num?)?.toInt() ?? 0;
        if (rating == null || count == 0) {
          return Row(children: const [
            Icon(Icons.person_add_alt_1_rounded,
                size: 13, color: Color(0xFF94A3B8)),
            SizedBox(width: 4),
            Text('לקוח חדש',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ]);
        }
        return Row(children: [
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
          const SizedBox(width: 3),
          Text(
            '${rating.toStringAsFixed(1)} ($count ביקורות)',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E)),
          ),
        ]);
      },
    );
  }
}

// ── Avatar widget (fetches profileImage from Firestore) ────────────────────

class _CustomerAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final double size;

  const _CustomerAvatar(
      {required this.uid, required this.name, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (_, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final url = data['profileImage'] as String?;
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: const Color(0xFFEEF2FF),
          backgroundImage:
              (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
          child: (url == null || url.isEmpty)
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF6366F1)),
                )
              : null,
        );
      },
    );
  }
}
