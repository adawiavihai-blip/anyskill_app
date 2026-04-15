import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/bookings/expert_job_card.dart';
import '../../widgets/bookings/transaction_history_card.dart';

/// Provider history tab — shows completed, cancelled, refunded jobs.
///
/// Extracted from my_bookings_screen.dart. Receives the expert Firestore
/// stream and action callbacks from the parent screen.
class ProviderHistoryTab extends StatefulWidget {
  final Stream<QuerySnapshot> expertStream;
  final String currentUserId;
  final void Function(
          BuildContext context, Map<String, dynamic> job, String jobId)
      onShowDetails;
  final void Function(BuildContext context, Map<String, dynamic> job)
      onShowReceipt;
  final void Function(BuildContext context, String jobId, String chatRoomId)
      onMarkDone;
  final void Function(
          BuildContext context, String jobId, Map<String, dynamic> jobData)
      onProviderCancel;
  final VoidCallback? onGoToSearch;

  const ProviderHistoryTab({
    super.key,
    required this.expertStream,
    required this.currentUserId,
    required this.onShowDetails,
    required this.onShowReceipt,
    required this.onMarkDone,
    required this.onProviderCancel,
    this.onGoToSearch,
  });

  @override
  State<ProviderHistoryTab> createState() => _ProviderHistoryTabState();
}

class _ProviderHistoryTabState extends State<ProviderHistoryTab> {
  bool _historyTimedOut = false;
  Timer? _historyTimeoutTimer;

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
    // Start a 6s timeout — if the stream hasn't delivered, show empty state.
    _historyTimeoutTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_historyTimedOut) {
        setState(() => _historyTimedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _historyTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.expertStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[History] Error: ${snapshot.error}');
          return Center(
            child: Text('שגיאה בטעינת היסטוריה',
                style: TextStyle(color: Colors.grey[500])),
          );
        }
        if (!snapshot.hasData && !_historyTimedOut) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        debugPrint('[History] Provider stream: ${docs.length} total docs');

        // Log status distribution for debugging
        if (docs.isNotEmpty) {
          final statusCounts = <String, int>{};
          for (final d in docs) {
            final s = ((d.data() as Map<String, dynamic>)['status'] ?? 'null')
                .toString();
            statusCounts[s] = (statusCounts[s] ?? 0) + 1;
          }
          debugPrint('[History] Provider status distribution: $statusCounts');
        }

        final historyDocs = docs.where((d) {
          final status =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return !_activeStatuses.contains(status) && status.isNotEmpty;
        }).toList()
          ..sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });
        debugPrint(
            '[History] After filter: ${historyDocs.length} history docs');

        if (historyDocs.isEmpty) {
          // Fallback: show transactions when no jobs have terminal status
          return _buildProviderTransactionFallbackHistory();
        }
        return _buildGroupedList(historyDocs);
      },
    );
  }

  /// Fallback for provider history: when `jobs` collection has no terminal-
  /// status docs for this expert, pull from `transactions` (receiverId).
  Widget _buildProviderTransactionFallbackHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('receiverId', isEqualTo: widget.currentUserId)
          .limit(50)
          .snapshots(),
      builder: (context, txSnap) {
        if (txSnap.hasError) {
          debugPrint(
              '[ProviderHistory] Transaction fallback error: ${txSnap.error}');
        }
        if (!txSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = txSnap.data!.docs;
        if (docs.isEmpty) {
          return _buildEmptyState();
        }
        return _buildTransactionList(docs);
      },
    );
  }

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
              ExpertJobCard(
                key: ValueKey(doc.id),
                job: doc.data() as Map<String, dynamic>,
                jobId: doc.id,
                onMarkDone: (jobId, chatRoomId) =>
                    widget.onMarkDone(context, jobId, chatRoomId),
                onCancel: (jobId) => widget.onProviderCancel(
                    context, jobId, doc.data() as Map<String, dynamic>),
                onDetails: () => widget.onShowDetails(
                    context, doc.data() as Map<String, dynamic>, doc.id),
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
              child: const Icon(Icons.history_rounded,
                  size: 54, color: Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            const Text('אין היסטוריית הזמנות',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text('הזמנות שהושלמו יופיעו כאן.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }
}
