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

class _ProviderHistoryTabState extends State<ProviderHistoryTab>
    with AutomaticKeepAliveClientMixin {
  // Two independent timeouts so neither stream can leave the user
  // staring at a spinner forever (רועי צברי report 2026-05-14: tap
  // History → stuck on spinning circle).
  bool _jobsTimedOut = false;
  bool _txTimedOut = false;
  Timer? _jobsTimer;
  Timer? _txTimer;

  // Cache of last-good snapshots so transient re-emit windows don't
  // bounce the user back to "loading" between stream events.
  QuerySnapshot? _lastJobsSnap;
  QuerySnapshot? _lastTxSnap;

  // §15 Law 15 — one-shot `.get()` fallback for the JOBS query. The
  // parent passes a `.snapshots()` stream; if that listener goes zombie
  // on a cold/stalled WebChannel it can never deliver, leaving the
  // provider's completed jobs invisible (live bug — רועי צברי
  // 2026-05-16: "I did jobs, History tab is empty"). A one-shot `.get()`
  // of the SAME query succeeds even when the stream listener is stuck —
  // it's a separate request. Populated by `_kickJobsGetFallback`.
  List<QueryDocumentSnapshot>? _jobsFallbackDocs;

  // Pre-warmed transactions stream — created in initState so the
  // fallback path can render INSTANTLY when reached, without paying
  // a fresh subscription delay.
  late final Stream<QuerySnapshot> _txStream;

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
  bool get wantKeepAlive => true; // preserve scroll + cached snapshots

  @override
  void initState() {
    super.initState();
    // 3s timeout per stream — bumped DOWN from 6s after user report.
    // After 3s we render whatever we have (which may be the empty state).
    _jobsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_jobsTimedOut) setState(() => _jobsTimedOut = true);
    });
    _txTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_txTimedOut) setState(() => _txTimedOut = true);
    });
    // Pre-warm the transactions stream so it has time to deliver its
    // first event by the time the user actually scrolls into the
    // fallback path. Saved subscription delay = saved spinner time.
    _txStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('receiverId', isEqualTo: widget.currentUserId)
        .limit(50)
        .snapshots();

    // §15 Law 15 — one-shot `.get()` fallback for the jobs query.
    // Tier 1 (1.5s): first attempt. Tier 1.5 (6s): silent retry. If the
    // parent's `.snapshots()` stream already delivered, these no-op.
    if (widget.currentUserId.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 1500),
          () => _kickJobsGetFallback(const Duration(seconds: 6)));
      Future.delayed(const Duration(seconds: 6), () {
        if (_lastJobsSnap == null && _jobsFallbackDocs == null) {
          _kickJobsGetFallback(const Duration(seconds: 8));
        }
      });
    }
  }

  /// Fires a one-shot `.get()` of the SAME query the parent's
  /// `_expertStream` uses (`jobs where expertId == uid`). Used only when
  /// the live `.snapshots()` listener hasn't delivered — covers the
  /// zombie-WebChannel case where the stream never emits.
  Future<void> _kickJobsGetFallback(Duration timeout) async {
    if (!mounted || _lastJobsSnap != null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('expertId', isEqualTo: widget.currentUserId)
          .limit(200)
          .get()
          .timeout(timeout);
      if (!mounted || _lastJobsSnap != null) return;
      setState(() => _jobsFallbackDocs = snap.docs);
      debugPrint(
          '[ProviderHistory] .get() fallback delivered ${snap.docs.length} job doc(s)');
    } catch (e) {
      debugPrint('[ProviderHistory] .get() fallback failed: $e');
    }
  }

  @override
  void dispose() {
    _jobsTimer?.cancel();
    _txTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAlive
    return StreamBuilder<QuerySnapshot>(
      stream: widget.expertStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[History] Error: ${snapshot.error}');
          // Even on error, fall through to the transaction fallback
          // so a flaky `jobs` stream doesn't break the whole tab.
        }
        if (snapshot.hasData) _lastJobsSnap = snapshot.data;
        final activeSnap = snapshot.data ?? _lastJobsSnap;
        // Strict waiting state — only show spinner during the FIRST 3s,
        // AND only while neither the live stream NOR the `.get()`
        // fallback has produced anything. After timeout / fallback,
        // render whatever we have.
        if (activeSnap == null &&
            _jobsFallbackDocs == null &&
            !_jobsTimedOut &&
            !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        // Prefer the live stream; fall back to the one-shot `.get()`
        // docs when the `.snapshots()` listener went zombie.
        final docs = activeSnap?.docs ?? _jobsFallbackDocs ?? const [];
        // 2026-05-14: changed filter to be MORE INCLUSIVE after user
        // report that old completed jobs weren't appearing. Original
        // filter required `status.isNotEmpty` — which dropped any
        // legacy jobs missing a status field. Now: include any job
        // whose status is NOT in the active set (so completed,
        // cancelled, refunded, AND legacy/missing-status jobs all
        // appear in history).
        final historyDocs = docs.where((d) {
          final status =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return !_activeStatuses.contains(status);
        }).toList()
          ..sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

        if (historyDocs.isEmpty) {
          // Fallback: show transactions instead. The fallback has its
          // own 3s timeout so the user never gets stuck on a 2nd
          // spinner if transactions are also slow.
          return _buildProviderTransactionFallbackHistory();
        }
        return _buildGroupedList(historyDocs);
      },
    );
  }

  /// Fallback for provider history: when `jobs` collection has no terminal-
  /// status docs for this expert, pull from `transactions` (receiverId).
  /// Uses pre-warmed `_txStream` + 3s timeout flag — never shows infinite
  /// spinner (the previous bug that left רועי צברי stuck on history tab).
  Widget _buildProviderTransactionFallbackHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: _txStream,
      builder: (context, txSnap) {
        if (txSnap.hasError) {
          debugPrint(
              '[ProviderHistory] Transaction fallback error: ${txSnap.error}');
          // Show empty state on error — never block the page.
          return _buildEmptyState();
        }
        if (txSnap.hasData) _lastTxSnap = txSnap.data;
        final activeTxSnap = txSnap.data ?? _lastTxSnap;
        if (activeTxSnap == null && !_txTimedOut) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = activeTxSnap?.docs ?? const [];
        if (docs.isEmpty) return _buildEmptyState();
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
