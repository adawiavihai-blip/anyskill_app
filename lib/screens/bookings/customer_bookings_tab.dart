// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/anyskill_logo.dart';
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

class _CustomerBookingsTabState extends State<CustomerBookingsTab>
    with AutomaticKeepAliveClientMixin {
  // Three independent timeouts — primary jobs stream, tx fallback,
  // tx fallback's own fallback (no-orderBy variant). 3s each so the
  // user never sits on a spinner longer than ~6s total worst case
  // (compared to the prior 6s + infinite nested spinners).
  bool _timedOut = false;
  bool _txTimedOut = false;
  bool _txAltTimedOut = false;
  Timer? _timeoutTimer;
  Timer? _txTimeoutTimer;
  Timer? _txAltTimeoutTimer;

  /// Cached snapshots so transient re-emits don't blink the list out.
  QuerySnapshot? _lastJobsSnap;
  QuerySnapshot? _lastTxSnap;
  QuerySnapshot? _lastTxAltSnap;

  /// Pre-warmed transactions streams so the fallback paths don't pay
  /// a fresh subscription delay when first reached.
  late final Stream<QuerySnapshot> _txStream;
  late final Stream<QuerySnapshot> _txAltStream;

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
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 3s timeout — bumped down from 6s after רועי צברי report
    // (2026-05-14: history tab stuck on spinning circle). After 3s
    // we fall through to whatever we have + the transaction fallback.
    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_timedOut) setState(() => _timedOut = true);
    });
    _txTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_txTimedOut) setState(() => _txTimedOut = true);
    });
    _txAltTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_txAltTimedOut) setState(() => _txAltTimedOut = true);
    });
    // Pre-warm both transaction streams so they have time to emit by
    // the time the fallback paths read them. Saves subscription delay.
    _txStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('senderId', isEqualTo: widget.currentUserId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
    _txAltStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('senderId', isEqualTo: widget.currentUserId)
        .limit(50)
        .snapshots();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _txTimeoutTimer?.cancel();
    _txAltTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAlive contract
    return StreamBuilder<QuerySnapshot>(
      stream: widget.customerStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[Customer${widget.isHistory ? "History" : "Active"}] '
              'STREAM ERROR: ${snapshot.error}');
          // Don't return error scaffold here — fall through to the
          // transaction fallback so a flaky `jobs` stream doesn't
          // break the whole tab. The fallback has its own timeout.
        }
        if (snapshot.hasData) _lastJobsSnap = snapshot.data;
        final activeSnap = snapshot.data ?? _lastJobsSnap;
        // Only show shimmer during the first 3s. After timeout, fall
        // through to the transaction fallback with whatever we have.
        if (activeSnap == null && !_timedOut && !snapshot.hasError) {
          return const BookingsShimmer();
        }

        final all = activeSnap?.docs ?? const [];
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
          // For HISTORY, include jobs with no status too — legacy
          // bookings without a status field were silently dropped
          // before (2026-05-14 fix after user report).
          if (widget.isHistory) {
            return !_activeStatuses.contains(status);
          }
          // For ACTIVE, only show jobs with a known active status.
          if (status.isEmpty) return false;
          return _activeStatuses.contains(status);
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
  ///
  /// Pre-warmed streams (set up in initState) + 3s timeouts on BOTH the
  /// orderBy variant AND the no-orderBy variant ensure the user never
  /// sees infinite spinners (the bug that left רועי צברי stuck on the
  /// history tab — 2026-05-14).
  Widget _buildTransactionFallbackHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: _txStream,
      builder: (context, txSnap) {
        if (txSnap.hasError) {
          debugPrint(
              '[CustomerHistory] Transaction fallback error: ${txSnap.error}');
          // Likely missing composite index — fall through to alt stream.
        }
        if (txSnap.hasData) _lastTxSnap = txSnap.data;
        final activeTxSnap = txSnap.data ?? _lastTxSnap;
        if (activeTxSnap == null && !_txTimedOut && !txSnap.hasError) {
          return const BookingsShimmer();
        }

        // Primary stream returned data — render it.
        if (activeTxSnap != null && activeTxSnap.docs.isNotEmpty) {
          return _buildTransactionList(activeTxSnap.docs);
        }

        // Either timeout fired OR primary stream returned empty.
        // Try the no-orderBy variant (handles missing composite index).
        return StreamBuilder<QuerySnapshot>(
          stream: _txAltStream,
          builder: (context, txSnap2) {
            if (txSnap2.hasData) _lastTxAltSnap = txSnap2.data;
            final activeAltSnap = txSnap2.data ?? _lastTxAltSnap;
            if (activeAltSnap == null && !_txAltTimedOut) {
              return const BookingsShimmer();
            }
            final docs = activeAltSnap?.docs ?? const [];
            if (docs.isEmpty) return _buildEmptyState();
            return _buildTransactionList(docs);
          },
        );
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
                                  d['expertName']?.toString() ?? 'נותן שירות',
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
                                    'נותן שירות',
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
    if (widget.isHistory) {
      return _buildHistoryEmptyState();
    }
    return _buildActiveEmptyState();
  }

  /// History empty-state — message + AnySkill logo below, per product copy.
  Widget _buildHistoryEmptyState() {
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
            const Text(
              'כרגע אין היסטוריית הזמנות',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 8),
            const Text(
              'רק לאחר סיום הזמנה יופיע כאן ההיסטוריה',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 32),
            // AnySkill brand logo below the message — per product copy.
            const Opacity(
              opacity: 0.85,
              child: AnySkillBrandIcon(size: 72),
            ),
          ],
        ),
      ),
    );
  }

  /// Active-tab empty-state — kept exactly as today (CTA to search).
  Widget _buildActiveEmptyState() {
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
              child: const Icon(Icons.home_repair_service_rounded,
                  size: 54, color: Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            const Text('צריכים שירות? כל מה שתצטרכו תמצאו כאן',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text('אל תתפשר על פחות מהטוב ביותר. בוא נתחיל?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Color(0xFF94A3B8))),
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
        ),
      ),
    );
  }
}
