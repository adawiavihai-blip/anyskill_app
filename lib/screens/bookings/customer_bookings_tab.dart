// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/bookings/booking_shared_widgets.dart';
import '../../widgets/bookings/customer_booking_card.dart';
import '../../widgets/bookings/history_order_card.dart';
import '../../widgets/bookings/transaction_history_card.dart';
import '../expert_profile_screen.dart';
import '../review_screen.dart';

/// Customer bookings tab — shows either active or history bookings.
///
/// Extracted from my_bookings_screen.dart. Receives the customer Firestore
/// stream and business-logic callbacks from the parent screen.
class CustomerBookingsTab extends StatefulWidget {
  final Stream<QuerySnapshot> customerStream;
  final String currentUserId;
  final bool isHistory;
  final void Function(BuildContext context, String jobId,
      Map<String, dynamic> jobData, double amount) onCompleteJob;
  final void Function(BuildContext context, String jobId,
      Map<String, dynamic> jobData, double amount) onCancel;
  final void Function(BuildContext context, String jobId) onDispute;
  final void Function(
          BuildContext context, Map<String, dynamic> job, String jobId)
      onShowDetails;
  final void Function(BuildContext context, Map<String, dynamic> job)
      onShowReceipt;
  final VoidCallback? onGoToSearch;

  const CustomerBookingsTab({
    super.key,
    required this.customerStream,
    required this.currentUserId,
    required this.isHistory,
    required this.onCompleteJob,
    required this.onCancel,
    required this.onDispute,
    required this.onShowDetails,
    required this.onShowReceipt,
    this.onGoToSearch,
  });

  @override
  State<CustomerBookingsTab> createState() => _CustomerBookingsTabState();
}

class _CustomerBookingsTabState extends State<CustomerBookingsTab> {
  bool _timedOut = false;
  Timer? _timeoutTimer;

  static const _activeStatuses = {
    'paid_escrow',
    'expert_completed',
    'disputed',
    'pending',
    'accepted',
    'in_progress',
    'awaiting_payment',
  };

  @override
  void initState() {
    super.initState();
    // 6s timeout — if the stream hasn't delivered, show empty state.
    _timeoutTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_timedOut) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.customerStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !_timedOut) {
          return const BookingsShimmer();
        }
        if (snapshot.hasError) {
          debugPrint('[Customer${widget.isHistory ? "History" : "Active"}] '
              'STREAM ERROR: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded,
                    size: 40, color: Color(0xFFEF4444)),
                const SizedBox(height: 12),
                const Text(
                    'לא ניתן לטעון את ההזמנות כרגע. אנא נסה שוב.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 14, color: Color(0xFF64748B))),
              ]),
            ),
          );
        }

        final all = snapshot.data?.docs ?? [];
        debugPrint('[Customer${widget.isHistory ? "History" : "Active"}] '
            'Stream returned ${all.length} docs for uid=${widget.currentUserId}');

        // Log all statuses for debugging
        if (widget.isHistory && all.isNotEmpty) {
          final statusCounts = <String, int>{};
          for (final d in all) {
            final s = ((d.data() as Map<String, dynamic>)['status'] ?? 'null')
                .toString();
            statusCounts[s] = (statusCounts[s] ?? 0) + 1;
          }
          debugPrint('[CustomerHistory] Status distribution: $statusCounts');
        }

        final filtered = all.where((d) {
          final status =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          if (status.isEmpty) return false;
          return widget.isHistory
              ? !_activeStatuses.contains(status)
              : _activeStatuses.contains(status);
        }).toList()
          ..sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) {
              return tb.compareTo(ta); // newest first
            }
            return 0;
          });

        // ── If jobs history is empty, fallback to transactions ────────────
        if (filtered.isEmpty && widget.isHistory) {
          return _buildTransactionFallbackHistory();
        }

        if (filtered.isEmpty) {
          return _buildEmptyState();
        }

        return _buildGroupedList(filtered);
      },
    );
  }

  /// Fallback: when `jobs` collection has no history docs for this customer,
  /// pull from `transactions` to show at least a basic list of payments.
  Widget _buildTransactionFallbackHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('senderId', isEqualTo: widget.currentUserId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, txSnap) {
        if (txSnap.hasError) {
          debugPrint(
              '[CustomerHistory] Transaction fallback error: ${txSnap.error}');
        }
        if (!txSnap.hasData) {
          // Try without orderBy (avoids composite index issues)
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('transactions')
                .where('senderId', isEqualTo: widget.currentUserId)
                .limit(50)
                .snapshots(),
            builder: (context, txSnap2) {
              if (!txSnap2.hasData) {
                return _buildEmptyState();
              }
              return _buildTransactionList(txSnap2.data!.docs);
            },
          );
        }
        final docs = txSnap.data!.docs;
        if (docs.isEmpty) {
          return _buildEmptyState();
        }
        return _buildTransactionList(docs);
      },
    );
  }

  /// Renders transaction docs as rich history cards.
  Widget _buildTransactionList(List<QueryDocumentSnapshot> docs) {
    docs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>? ?? {};
      final bData = b.data() as Map<String, dynamic>? ?? {};
      final aTs = aData['timestamp'] as Timestamp?;
      final bTs = bData['timestamp'] as Timestamp?;
      if (aTs == null || bTs == null) return 0;
      return bTs.compareTo(aTs);
    });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: docs.length,
      itemBuilder: (_, i) => TransactionHistoryCard(
          data: docs[i].data() as Map<String, dynamic>? ?? {},
          docId: docs[i].id),
    );
  }

  Widget _buildGroupedList(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    final groups = <String, List<QueryDocumentSnapshot>>{
      'החודש': [],
      'חודש שעבר': [],
      'ישן יותר': [],
    };

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['createdAt'] as Timestamp?;
      final date = ts?.toDate() ?? DateTime(2000);
      if (!date.isBefore(thisMonthStart)) {
        groups['החודש']!.add(doc);
      } else if (!date.isBefore(lastMonthStart)) {
        groups['חודש שעבר']!.add(doc);
      } else {
        groups['ישן יותר']!.add(doc);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        for (final entry in groups.entries)
          if (entry.value.isNotEmpty) ...[
            _groupHeader(entry.key, entry.value.length),
            const SizedBox(height: 10),
            for (final doc in entry.value)
              widget.isHistory
                  ? HistoryOrderCard(
                      key: ValueKey(doc.id),
                      job: doc.data() as Map<String, dynamic>,
                      jobId: doc.id,
                      onReceipt: () => widget.onShowReceipt(
                          context, doc.data() as Map<String, dynamic>),
                    )
                  : CustomerBookingCard(
                      key: ValueKey(doc.id),
                      job: doc.data() as Map<String, dynamic>,
                      jobId: doc.id,
                      currentUserId: widget.currentUserId,
                      onCompleteJob: (amount) => widget.onCompleteJob(
                          context,
                          doc.id,
                          doc.data() as Map<String, dynamic>,
                          amount),
                      onCancel: (amount) => widget.onCancel(
                          context,
                          doc.id,
                          doc.data() as Map<String, dynamic>,
                          amount),
                      onDispute: () =>
                          widget.onDispute(context, doc.id),
                      onRate: () {
                        final d = doc.data() as Map<String, dynamic>;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReviewScreen(
                              jobId: doc.id,
                              revieweeId:
                                  d['expertId']?.toString() ?? '',
                              revieweeName:
                                  d['expertName']?.toString() ?? 'מומחה',
                              revieweeAvatar:
                                  d['expertImage']?.toString() ?? '',
                              isClientReview: true,
                            ),
                          ),
                        );
                      },
                      onDetails: () => widget.onShowDetails(
                          context,
                          doc.data() as Map<String, dynamic>,
                          doc.id),
                      onRebook: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExpertProfileScreen(
                            expertId: (doc.data()
                                    as Map<String, dynamic>)['expertId'] ??
                                '',
                            expertName: (doc.data()
                                        as Map<String, dynamic>)['expertName'] ??
                                    'מומחה',
                          ),
                        ),
                      ),
                      onReceipt: () => widget.onShowReceipt(
                          context, doc.data() as Map<String, dynamic>),
                    ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _groupHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 2),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                letterSpacing: 0.4),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final icon = widget.isHistory
        ? Icons.history_rounded
        : Icons.home_repair_service_rounded;
    final title = widget.isHistory
        ? 'אין היסטוריית הזמנות'
        : 'יש לך משימה? לנו יש את האדם הנכון בשבילה.';
    final subtitle = widget.isHistory
        ? 'הזמנות שהושלמו יופיעו כאן.'
        : 'אל תתפשר על פחות מהטוב ביותר. בוא נתחיל?';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                  color: Color(0xFFEEF2FF), shape: BoxShape.circle),
              child: Icon(icon, size: 54, color: const Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF94A3B8))),
            if (!widget.isHistory) ...[
              const SizedBox(height: 28),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text('הזמן שירות עכשיו',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                onPressed: widget.onGoToSearch,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
