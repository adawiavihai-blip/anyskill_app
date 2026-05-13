// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/cached_readers.dart';
import '../theme/app_theme.dart';
import '../widgets/bookings/booking_shared_widgets.dart';
import '../widgets/receipt_sheet.dart';
import 'expert_profile_screen.dart';
import 'review_screen.dart';
import 'chat_screen.dart';

/// Premium full-detail view for a single completed/active service.
///
/// Pushed from [ServiceHistoryScreen]. Streams the live `jobs/{jobId}` doc so
/// status updates (release escrow, mark completed) reflect instantly. Pulls
/// the linked review (if any) and renders every available field — provider
/// info, schedule, pricing breakdown, timeline, and review — in clean cards.
class ServiceHistoryDetailScreen extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic>? initialJob;

  const ServiceHistoryDetailScreen({
    super.key,
    required this.jobId,
    this.initialJob,
  });

  @override
  State<ServiceHistoryDetailScreen> createState() =>
      _ServiceHistoryDetailScreenState();
}

class _ServiceHistoryDetailScreenState
    extends State<ServiceHistoryDetailScreen> {
  late final Stream<DocumentSnapshot> _jobStream;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _jobStream = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.jobId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _jobStream,
        builder: (context, snap) {
          final job = (snap.data?.data() as Map<String, dynamic>?) ??
              widget.initialJob ??
              {};
          if (job.isEmpty && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (job.isEmpty) {
            return _buildNotFound();
          }
          return _buildContent(job);
        },
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: Brand.textLight),
            const SizedBox(height: 14),
            const Text(
              'השירות לא נמצא',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Brand.textDark),
            ),
            const SizedBox(height: 6),
            const Text(
              'ייתכן שהוא נמחק או שאין לך גישה אליו.',
              style: TextStyle(fontSize: 13, color: Brand.textMuted),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('חזרה'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> job) {
    final status = job['status'] as String? ?? '';
    final amount = ((job['totalAmount'] ??
            job['totalPaidByCustomer'] ??
            0.0) as num)
        .toDouble();

    return CustomScrollView(
      slivers: [
        _buildHeader(job, status, amount),
        SliverToBoxAdapter(child: _buildProviderCard(job)),
        SliverToBoxAdapter(child: _buildServiceInfoCard(job)),
        SliverToBoxAdapter(child: _buildScheduleCard(job)),
        SliverToBoxAdapter(child: _buildPricingCard(job, amount)),
        SliverToBoxAdapter(child: _buildTimelineCard(job)),
        SliverToBoxAdapter(child: _buildReviewSection(job)),
        SliverToBoxAdapter(child: _buildActionsCard(job, status, amount)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Header (gradient + status hero) ────────────────────────────────────
  Widget _buildHeader(
      Map<String, dynamic> job, String status, double amount) {
    final (bg, fg, icon, headline) = _statusVisuals(status);
    DateTime? created;
    if (job['createdAt'] is Timestamp) {
      created = (job['createdAt'] as Timestamp).toDate();
    }
    final createdStr = created == null
        ? ''
        : 'הוזמן ב-${DateFormat('dd/MM/yyyy', 'he').format(created)}';

    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      elevation: 0,
      backgroundColor: bg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [bg, fg],
                ),
              ),
            ),
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₪${amount.toStringAsFixed(0)}  •  $createdStr',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color, IconData, String) _statusVisuals(String status) {
    switch (status) {
      case 'completed':
      case 'split_resolved':
        return (
          const Color(0xFF10B981),
          const Color(0xFF059669),
          Icons.check_circle_outline_rounded,
          'שירות הושלם'
        );
      case 'paid_escrow':
        return (
          const Color(0xFFF97316),
          const Color(0xFFEA580C),
          Icons.lock_outline_rounded,
          'בנאמנות'
        );
      case 'expert_completed':
        return (
          const Color(0xFF3B82F6),
          const Color(0xFF2563EB),
          Icons.hourglass_top_rounded,
          'ממתין לאישור'
        );
      case 'cancelled':
      case 'cancelled_with_penalty':
        return (
          const Color(0xFFEF4444),
          const Color(0xFFDC2626),
          Icons.cancel_outlined,
          'בוטל'
        );
      case 'refunded':
        return (
          const Color(0xFF0D9488),
          const Color(0xFF0F766E),
          Icons.replay_rounded,
          'הוחזר'
        );
      case 'disputed':
        return (
          const Color(0xFFDC2626),
          const Color(0xFFB91C1C),
          Icons.gavel_rounded,
          'במחלוקת'
        );
      default:
        return (
          Brand.indigo,
          Brand.purple,
          Icons.assignment_rounded,
          'בטיפול'
        );
    }
  }

  // ── Provider card ─────────────────────────────────────────────────────
  Widget _buildProviderCard(Map<String, dynamic> job) {
    final expertId = job['expertId'] as String? ?? '';
    final expertName = job['expertName'] as String? ?? 'נותן שירות';

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: expertId.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExpertProfileScreen(
                      expertId: expertId,
                      expertName: expertName,
                    ),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              BookingProfileAvatar(
                  uid: expertId, name: expertName, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expertName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Brand.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _ProviderRatingLine(expertId: expertId),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded,
                  color: Brand.textLight),
            ],
          ),
        ),
      ),
    );
  }

  // ── Service info ──────────────────────────────────────────────────────
  Widget _buildServiceInfoCard(Map<String, dynamic> job) {
    final serviceType = (job['serviceType'] as String? ?? '').trim();
    final description = (job['description'] as String? ?? '').trim();
    final urgency = (job['urgency'] as String? ?? '').trim();
    final address = (job['address'] as String? ?? '').trim();

    if (serviceType.isEmpty &&
        description.isEmpty &&
        urgency.isEmpty &&
        address.isEmpty) {
      return const SizedBox.shrink();
    }

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
                icon: Icons.work_outline_rounded, title: 'פרטי השירות'),
            const SizedBox(height: 10),
            if (serviceType.isNotEmpty)
              _InfoRow(
                  icon: Icons.category_rounded,
                  label: 'קטגוריה',
                  value: serviceType),
            if (description.isNotEmpty)
              _InfoRow(
                  icon: Icons.description_rounded,
                  label: 'תיאור',
                  value: description,
                  multiline: true),
            if (urgency.isNotEmpty)
              _InfoRow(
                  icon: Icons.priority_high_rounded,
                  label: 'דחיפות',
                  value: urgency),
            if (address.isNotEmpty)
              _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'כתובת',
                  value: address,
                  multiline: true),
          ],
        ),
      ),
    );
  }

  // ── Schedule ──────────────────────────────────────────────────────────
  Widget _buildScheduleCard(Map<String, dynamic> job) {
    DateTime? appt;
    if (job['appointmentDate'] is Timestamp) {
      appt = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptTime = (job['appointmentTime'] as String? ?? '').trim();
    final duration =
        (job['estimatedDuration'] ?? job['durationMinutes']) as num?;

    if (appt == null && apptTime.isEmpty && duration == null) {
      return const SizedBox.shrink();
    }

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
                icon: Icons.event_rounded, title: 'מועד השירות'),
            const SizedBox(height: 10),
            if (appt != null)
              _InfoRow(
                icon: Icons.calendar_today_rounded,
                label: 'תאריך',
                value: DateFormat('EEEE, dd/MM/yyyy', 'he').format(appt),
              ),
            if (apptTime.isNotEmpty)
              _InfoRow(
                  icon: Icons.access_time_rounded,
                  label: 'שעה',
                  value: apptTime),
            if (duration != null)
              _InfoRow(
                icon: Icons.hourglass_bottom_rounded,
                label: 'משך משוער',
                value: '${duration.toStringAsFixed(0)} דקות',
              ),
          ],
        ),
      ),
    );
  }

  // ── Pricing breakdown ─────────────────────────────────────────────────
  Widget _buildPricingCard(Map<String, dynamic> job, double amount) {
    final breakdown =
        (job['priceBreakdown'] as Map<String, dynamic>?) ?? {};
    final base = (breakdown['base'] ?? breakdown['servicesTotal']) as num?;
    final addOnsTotal = breakdown['addOnsTotal'] as num?;
    final surcharge = (breakdown['immediateSurcharge'] ??
        breakdown['emergencySurcharge'] ??
        breakdown['ecoSurcharge']) as num?;
    final discount = breakdown['recurringDiscount'] as num?;
    final materials = breakdown['materialsEstimate'] as num?;
    final deposit = job['depositAmount'] as num?;
    final paidAtBooking = job['paidAtBooking'] as num?;
    final remaining = job['remainingAmount'] as num?;

    final hasBreakdown = base != null ||
        addOnsTotal != null ||
        surcharge != null ||
        discount != null ||
        materials != null ||
        deposit != null;

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
                icon: Icons.receipt_long_rounded, title: 'פירוט תשלום'),
            const SizedBox(height: 12),
            if (!hasBreakdown)
              _PriceLine(
                label: 'סכום השירות',
                value: amount,
                isBold: true,
              )
            else ...[
              if (base != null)
                _PriceLine(label: 'מחיר בסיס', value: base.toDouble()),
              if (materials != null && materials > 0)
                _PriceLine(
                    label: 'הערכת חומרים',
                    value: materials.toDouble()),
              if (addOnsTotal != null && addOnsTotal > 0)
                _PriceLine(
                    label: 'תוספות', value: addOnsTotal.toDouble()),
              if (surcharge != null && surcharge > 0)
                _PriceLine(
                    label: 'תוספת דחיפות',
                    value: surcharge.toDouble()),
              if (discount != null && discount > 0)
                _PriceLine(
                  label: 'הנחת קביעות',
                  value: -discount.toDouble(),
                  color: Brand.success,
                ),
              const Divider(height: 18, color: Color(0xFFE5E7EB)),
              _PriceLine(
                label: 'סה"כ',
                value: amount,
                isBold: true,
              ),
            ],
            if (deposit != null && deposit > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.savings_outlined,
                        size: 16, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        paidAtBooking != null && remaining != null
                            ? 'שולם בפיקדון: ₪${paidAtBooking.toStringAsFixed(0)}, יתרה: ₪${remaining.toStringAsFixed(0)}'
                            : 'פיקדון: ₪${deposit.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E40AF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Timeline ──────────────────────────────────────────────────────────
  Widget _buildTimelineCard(Map<String, dynamic> job) {
    final events = <(IconData, String, DateTime?, Color)>[
      (
        Icons.add_circle_outline_rounded,
        'הוזמן',
        (job['createdAt'] as Timestamp?)?.toDate(),
        Brand.indigo,
      ),
      (
        Icons.lock_outline_rounded,
        'תשלום בנאמנות',
        (job['paidAt'] as Timestamp?)?.toDate() ??
            (job['depositPaidAt'] as Timestamp?)?.toDate(),
        const Color(0xFFF97316),
      ),
      (
        Icons.directions_run_rounded,
        'נותן השירות בדרך',
        (job['expertOnWayAt'] as Timestamp?)?.toDate(),
        const Color(0xFF8B5CF6),
      ),
      (
        Icons.build_circle_outlined,
        'התחיל לעבוד',
        (job['workStartedAt'] as Timestamp?)?.toDate(),
        const Color(0xFF3B82F6),
      ),
      (
        Icons.assignment_turned_in_outlined,
        'דווח שהושלם',
        (job['expertCompletedAt'] as Timestamp?)?.toDate(),
        const Color(0xFF0D9488),
      ),
      (
        Icons.check_circle_rounded,
        'הסתיים ושוחרר',
        (job['completedAt'] as Timestamp?)?.toDate(),
        Brand.success,
      ),
      (
        Icons.cancel_rounded,
        'בוטל',
        (job['cancelledAt'] as Timestamp?)?.toDate(),
        Brand.error,
      ),
    ].where((e) => e.$3 != null).toList()
      ..sort((a, b) => a.$3!.compareTo(b.$3!));

    if (events.isEmpty) return const SizedBox.shrink();

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
                icon: Icons.timeline_rounded, title: 'ציר זמן'),
            const SizedBox(height: 14),
            for (int i = 0; i < events.length; i++)
              _TimelineEvent(
                icon: events[i].$1,
                label: events[i].$2,
                date: events[i].$3!,
                color: events[i].$4,
                isLast: i == events.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  // ── Review (if any) ───────────────────────────────────────────────────
  Widget _buildReviewSection(Map<String, dynamic> job) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('reviews')
          .where('jobId', isEqualTo: widget.jobId)
          .where('reviewerId', isEqualTo: _uid)
          .limit(1)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          // Customer hasn't reviewed yet — only show prompt if eligible.
          final status = job['status'] as String? ?? '';
          if (status != 'completed') return const SizedBox.shrink();
          return _Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.star_outline_rounded,
                      color: Brand.warning, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'עדיין לא דירגת את השירות הזה',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Brand.textDark,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReviewScreen(
                            jobId: widget.jobId,
                            revieweeId:
                                job['expertId'] as String? ?? '',
                            revieweeName:
                                job['expertName'] as String? ?? 'נותן שירות',
                            revieweeAvatar:
                                job['expertImage'] as String? ?? '',
                            isClientReview: true,
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'דרג',
                      style: TextStyle(
                          color: Brand.warning,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final review = snap.data!.docs.first.data() as Map<String, dynamic>;
        final overall = (review['overallRating'] as num?)?.toDouble() ?? 0;
        final params =
            (review['ratingParams'] as Map<String, dynamic>?) ?? {};
        final comment = (review['publicComment'] as String? ?? '').trim();

        return _Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(
                    icon: Icons.star_rounded, title: 'הדירוג שלך'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Brand.warning, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            overall.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (params.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final entry in params.entries)
                    _RatingParamRow(
                        label: _paramLabel(entry.key),
                        value:
                            (entry.value as num?)?.toDouble() ?? 0),
                ],
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      comment,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Brand.textDark,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _paramLabel(String key) {
    switch (key) {
      case 'professional':
        return 'מקצועיות';
      case 'timing':
        return 'דיוק בזמנים';
      case 'communication':
        return 'תקשורת';
      case 'value':
        return 'תמורה למחיר';
      default:
        return key;
    }
  }

  // ── Actions (rebook / message / receipt) ──────────────────────────────
  Widget _buildActionsCard(
      Map<String, dynamic> job, String status, double amount) {
    final expertId = job['expertId'] as String? ?? '';
    final expertName = job['expertName'] as String? ?? 'נותן שירות';
    final isFinal = status == 'completed' ||
        status == 'cancelled' ||
        status == 'cancelled_with_penalty' ||
        status == 'refunded' ||
        status == 'split_resolved';

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      child: Column(
        children: [
          if (isFinal && expertId.isNotEmpty)
            BookingPrimaryButton(
              icon: Icons.refresh_rounded,
              label: 'הזמן שוב את $expertName',
              color: Brand.indigo,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpertProfileScreen(
                    expertId: expertId,
                    expertName: expertName,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (expertId.isNotEmpty)
                Expanded(
                  child: BookingSecondaryButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'שלח הודעה',
                    color: Brand.indigo,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          receiverId: expertId,
                          receiverName: expertName,
                        ),
                      ),
                    ),
                  ),
                ),
              if (expertId.isNotEmpty) const SizedBox(width: 8),
              Expanded(
                child: BookingSecondaryButton(
                  icon: Icons.receipt_long_rounded,
                  label: 'קבלה',
                  color: const Color(0xFF0D9488),
                  onPressed: () => _openReceipt(job),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openReceipt(Map<String, dynamic> job) async {
    final expertId = job['expertId'] as String? ?? '';
    String? taxId;
    if (expertId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(expertId)
            .get();
        taxId = snap.data()?['taxId'] as String?;
      } catch (_) {}
    }
    if (!mounted) return;
    showReceiptSheet(context, jobData: job, providerTaxId: taxId);
  }
}

// ── Building blocks ─────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  const _Card({required this.child, required this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF0F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: Brand.indigo),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Brand.textDark,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool multiline;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Brand.textLight),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: const TextStyle(
                fontSize: 12.5,
                color: Brand.textMuted,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Brand.textDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final Color? color;
  const _PriceLine({
    required this.label,
    required this.value,
    this.isBold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: color ?? Brand.textDark,
              ),
            ),
          ),
          Text(
            '${value < 0 ? '−' : ''}₪${value.abs().toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Brand.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  final IconData icon;
  final String label;
  final DateTime date;
  final Color color;
  final bool isLast;
  const _TimelineEvent({
    required this.icon,
    required this.label,
    required this.date,
    required this.color,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: const Color(0xFFE5E7EB),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Brand.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd/MM/yyyy  •  HH:mm', 'he').format(date),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Brand.textLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingParamRow extends StatelessWidget {
  final String label;
  final double value;
  const _RatingParamRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Brand.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (value / 5).clamp(0, 1),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Brand.warning,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 26,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Brand.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderRatingLine extends StatelessWidget {
  final String expertId;
  const _ProviderRatingLine({required this.expertId});

  @override
  Widget build(BuildContext context) {
    if (expertId.isEmpty) {
      return const Text(
        'נותן שירות',
        style: TextStyle(fontSize: 12, color: Brand.textMuted),
      );
    }
    // §66: cached read — past-job tile re-renders many times during scroll;
    // 5-min cache prevents per-render network reads.
    return FutureBuilder<Map<String, dynamic>>(
      future: CachedReaders.providerProfile(expertId),
      builder: (context, snap) {
        final data = snap.data ?? const <String, dynamic>{};
        final rating = (data['rating'] as num?)?.toDouble() ?? 0;
        final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;
        final serviceType = (data['serviceType'] as String?) ?? '';
        return Row(
          children: [
            if (rating > 0) ...[
              const Icon(Icons.star_rounded,
                  color: Brand.warning, size: 14),
              const SizedBox(width: 3),
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Brand.textDark,
                ),
              ),
              if (reviewsCount > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '($reviewsCount)',
                  style: const TextStyle(
                      fontSize: 11, color: Brand.textLight),
                ),
              ],
              const SizedBox(width: 8),
            ],
            if (serviceType.isNotEmpty)
              Flexible(
                child: Text(
                  serviceType,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Brand.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (rating == 0 && serviceType.isEmpty)
              const Text(
                'נותן שירות',
                style:
                    TextStyle(fontSize: 12, color: Brand.textMuted),
              ),
          ],
        );
      },
    );
  }
}
