// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/bookings/booking_shared_widgets.dart';
import '../../widgets/bookings/expert_job_card.dart';
import '../review_screen.dart';

/// Provider active-tasks tab — shows only jobs with active statuses.
///
/// Extracted from my_bookings_screen.dart. Receives the expert Firestore
/// stream and business-logic callbacks from the parent screen.
class ProviderTasksTab extends StatefulWidget {
  final Stream<QuerySnapshot> expertStream;
  final String currentUserId;
  final bool isAdmin;
  final void Function(BuildContext context, String jobId, String chatRoomId)
      onMarkDone;
  final void Function(
          BuildContext context, String jobId, Map<String, dynamic> jobData)
      onProviderCancel;
  final void Function(
          BuildContext context, Map<String, dynamic> job, String jobId)
      onShowDetails;
  final void Function(BuildContext context, Map<String, dynamic> job)
      onShowReceipt;
  final VoidCallback? onGoToSearch;

  const ProviderTasksTab({
    super.key,
    required this.expertStream,
    required this.currentUserId,
    required this.isAdmin,
    required this.onMarkDone,
    required this.onProviderCancel,
    required this.onShowDetails,
    required this.onShowReceipt,
    this.onGoToSearch,
  });

  @override
  State<ProviderTasksTab> createState() => _ProviderTasksTabState();
}

class _ProviderTasksTabState extends State<ProviderTasksTab> {
  bool _tasksTimedOut = false;
  Timer? _tasksTimeoutTimer;
  bool _tasksFirstSnapshotReceived = false;

  /// Tracks job IDs for which we already auto-opened the review popup,
  /// so we don't re-trigger on every stream rebuild.
  final Set<String> _reviewTriggeredFor = {};

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
    // Start the timeout WHEN the tab renders (not in parent initState which
    // races against _providerLoaded). This gives the full 10 seconds for the
    // expert stream to deliver data.
    _tasksTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && !_tasksFirstSnapshotReceived) {
        setState(() => _tasksTimedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _tasksTimeoutTimer?.cancel();
    super.dispose();
  }

  /// Auto-opens ReviewScreen for completed jobs the provider hasn't reviewed.
  /// CRITICAL: Only triggers when the current user IS the expert for this job.
  void _autoTriggerProviderReview(
      BuildContext ctx, List<QueryDocumentSnapshot> docs) {
    // Admins NEVER get auto-review popups.
    if (widget.isAdmin) return;

    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['status'] != 'completed') continue;
      if (d['providerReviewDone'] == true) continue;
      if (d['providerReviewShown'] == true) continue; // already prompted
      if (_reviewTriggeredFor.contains(doc.id)) continue;

      // Require completedAt — proves payment was finalized in Firestore
      final completedAt = d['completedAt'];
      if (completedAt == null) continue;

      // Anti-fraud: only the EXPERT for this job can auto-review
      final jobExpertId = d['expertId']?.toString() ?? '';
      final jobCustomerId = d['customerId']?.toString() ?? '';
      if (jobExpertId != widget.currentUserId) continue;
      if (jobExpertId == jobCustomerId) continue;

      _reviewTriggeredFor.add(doc.id);

      // Mark reviewShown in Firestore IMMEDIATELY to prevent re-trigger
      FirebaseFirestore.instance.collection('jobs').doc(doc.id).update({
        'providerReviewShown': true,
      }).catchError((_) {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => ReviewScreen(
                jobId: doc.id,
                revieweeId: jobCustomerId,
                revieweeName: d['customerName']?.toString() ?? 'לקוח',
                revieweeAvatar: '',
                isClientReview: false,
              ),
            ));
      });
      break; // only one popup at a time
    }
  }

  int _jobTimestamp(QueryDocumentSnapshot d) {
    final ts = (d.data() as Map)['createdAt'];
    return ts is Timestamp ? ts.millisecondsSinceEpoch : 0;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.expertStream,
      builder: (context, snapshot) {
        // ── Error state ─────────────────────────────────────────────────
        if (snapshot.hasError) {
          debugPrint('[Tasks] ERROR: ${snapshot.error}');
          final err = snapshot.error.toString().toLowerCase();
          final isPermission =
              err.contains('permission') || err.contains('insufficient');
          final isIndex = err.contains('index') ||
              err.contains('failed-precondition') ||
              err.contains('requires an index');
          final msg = isPermission
              ? 'אין הרשאה לצפות במשימות. פנה לתמיכה.'
              : isIndex
                  ? 'אינדקס מסד הנתונים עדיין נבנה. נסה שוב בעוד דקה.'
                  : 'חלה שגיאה בטעינת המשימות, אנא נסה שנית.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: Color(0xFFEF4444)),
                  const SizedBox(height: 16),
                  Text(msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF64748B))),
                ],
              ),
            ),
          );
        }

        // ── Waiting for first snapshot ───────────────────────────────────
        if (!snapshot.hasData && !_tasksTimedOut) {
          return const BookingsShimmer();
        }

        final docs = snapshot.data?.docs ?? [];
        _tasksFirstSnapshotReceived = true;
        _tasksTimeoutTimer?.cancel();

        // Debug: log what the stream returned
        debugPrint(
            '[Tasks] expertStream returned ${docs.length} docs for uid=${widget.currentUserId}');
        for (final d in docs) {
          final m = d.data() as Map<String, dynamic>;
          debugPrint('  • job=${d.id} status=${m['status']} '
              'expertId=${m['expertId']} customerId=${m['customerId']}');
        }

        if (docs.isEmpty) {
          debugPrint('[Tasks] EMPTY — showing empty state');
          return _buildEmptyState();
        }

        // ── Auto-trigger review popup for newly completed jobs ──────
        _autoTriggerProviderReview(context, docs);

        return _buildExpertTasksList(docs);
      },
    );
  }

  Widget _buildExpertTasksList(List<QueryDocumentSnapshot> docs) {
    // Sort newest first (no server-side orderBy to avoid composite index).
    final sorted = [...docs]
      ..sort((a, b) => _jobTimestamp(b).compareTo(_jobTimestamp(a)));

    // ACTIVE ONLY — history lives in the dedicated History tab (v9.0.7).
    final activeDocs = sorted
        .where((d) => _activeStatuses.contains(
            (d.data() as Map<String, dynamic>)['status'] as String? ?? ''))
        .toList();

    if (activeDocs.isEmpty) {
      return _buildEmptyState();
    }

    // Sum expected earnings from pending (paid_escrow) jobs
    double todayEarnings = 0;
    for (final doc in activeDocs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['status'] == 'paid_escrow') {
        todayEarnings += ((d['netAmountForExpert'] ??
                    d['totalPaidByCustomer'] ??
                    d['totalAmount'] ??
                    0.0) as num)
                .toDouble();
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        ExpertEarningsSummary(
            expectedEarnings: todayEarnings,
            activeCount: activeDocs
                .where((d) =>
                    (d.data() as Map<String, dynamic>)['status'] ==
                    'paid_escrow')
                .length),
        const SizedBox(height: 16),
        _groupHeader('פעיל', activeDocs.length),
        const SizedBox(height: 10),
        for (final doc in activeDocs)
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
            onReceipt: () =>
                widget.onShowReceipt(context, doc.data() as Map<String, dynamic>),
            onRate: () {
              final d = doc.data() as Map<String, dynamic>;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReviewScreen(
                      jobId: doc.id,
                      revieweeId: d['customerId']?.toString() ?? '',
                      revieweeName: d['customerName']?.toString() ?? 'לקוח',
                      revieweeAvatar: '',
                      isClientReview: false,
                    ),
                  ));
            },
          ),
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
              child: const Icon(Icons.work_outline,
                  size: 54, color: Color(0xFF6366F1)),
            ),
            const SizedBox(height: 20),
            const Text('אין משימות עדיין',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text(
                'הזמנות מלקוחות יופיעו כאן. ודא שהפרופיל שלך מעודכן.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }
}
