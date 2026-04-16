// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'booking_shared_widgets.dart';
import '../../screens/expert_profile_screen.dart';
import '../../screens/chat_screen.dart';
import '../../screens/bookings/active_booking_detail_screen.dart';
import '../../features/pet_stay/screens/owner_pet_mode_screen.dart';
import '../live_travel_map.dart';

/// Customer-facing booking card with live signals, step tracker, tip, and actions.
///
/// Extracted from my_bookings_screen.dart (Phase 2 refactor).
class CustomerBookingCard extends StatefulWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final String currentUserId;
  final void Function(double amount) onCompleteJob;
  final void Function(double amount) onCancel;
  final VoidCallback onDispute;
  final VoidCallback onRate;
  final VoidCallback onDetails;
  final VoidCallback onRebook;
  final VoidCallback onReceipt;

  const CustomerBookingCard({
    super.key,
    required this.job,
    required this.jobId,
    required this.currentUserId,
    required this.onCompleteJob,
    required this.onCancel,
    required this.onDispute,
    required this.onRate,
    required this.onDetails,
    required this.onRebook,
    required this.onReceipt,
  });

  @override
  State<CustomerBookingCard> createState() => _CustomerBookingCardState();
}

class _CustomerBookingCardState extends State<CustomerBookingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;
  Timer? _workTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _workTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _workTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendTip(BuildContext context, double tipAmount) async {
    final expertId   = widget.job['expertId']   as String? ?? '';
    final expertName = widget.job['expertName'] as String? ?? 'מומחה';
    if (expertId.isEmpty || widget.currentUserId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('שלח טיפ',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'לשלוח ₪${tipAmount.toStringAsFixed(0)} טיפ ל-$expertName?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ביטול')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1)),
            onPressed: () => Navigator.pop(c, true),
            child:
                const Text('שלח', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('addTipToJob')
          .call({
        'jobId': widget.jobId,
        'expertId': expertId,
        'expertName': expertName,
        'tipAmount': tipAmount,
      }).timeout(const Duration(seconds: 30));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF6366F1),
          content: Text('₪${tipAmount.toStringAsFixed(0)} נשלחו ל-$expertName 🎉'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('שגיאה בשליחת טיפ: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job         = widget.job;
    final status      = job['status'] as String? ?? '';
    final expertId    = job['expertId']   as String? ?? '';
    final expertName  = job['expertName'] as String? ?? 'מומחה';
    final expertPhone = job['expertPhone'] as String? ?? '';
    final amount      = (job['totalAmount'] ??
            job['totalPaidByCustomer'] ??
            job['amount'] ??
            0.0)
        .toDouble();

    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptStr  = apptDate != null
        ? DateFormat('dd/MM/yy').format(apptDate)
        : 'טרם נקבע';
    final apptTime   = job['appointmentTime'] as String? ?? '';
    final chatRoomId = job['chatRoomId']      as String? ?? '';
    final isCompleted = status == 'completed';
    final isActive    = status == 'paid_escrow' || status == 'expert_completed';
    final isReviewed  = job['clientReviewDone'] == true;

    final expertOnWay   = job['expertOnWay']   == true;
    final workStartedTs = job['workStartedAt'] as Timestamp?;

    final int stepIndex;
    if (status == 'expert_completed' || status == 'completed') {
      stepIndex = 3;
    } else if (workStartedTs != null) {
      stepIndex = 2;
    } else if (expertOnWay) {
      stepIndex = 1;
    } else {
      stepIndex = 0;
    }

    final workMinutes = workStartedTs != null
        ? DateTime.now().difference(workStartedTs.toDate()).inMinutes
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Card header (tap → ActiveBookingDetailScreen) ─────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
            onTap: isActive
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ActiveBookingDetailScreen(
                          jobId: widget.jobId,
                          initialJob: widget.job,
                          onCancelRequested: (j, a) async =>
                              widget.onCancel(a),
                        ),
                      ),
                    )
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  BookingProfileAvatar(
                      uid: expertId, name: expertName, size: 50),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(expertName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF1A1A2E))),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 12, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(
                              apptTime.isNotEmpty
                                  ? '$apptStr · $apptTime'
                                  : apptStr,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8))),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_left_rounded,
                                size: 14, color: Color(0xFF6366F1)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  BookingStatusBadge(status),
                ],
              ),
            ),
          ),

          // ── Step tracker (active bookings) ───────────────────────────
          if (isActive || status == 'expert_completed') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: BookingStepIndicator(currentStep: stepIndex),
            ),
            const SizedBox(height: 12),
          ],

          // ── "On the way" live signal ──────────────────────────────────
          if (expertOnWay && workStartedTs == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6)
                                .withValues(alpha: _pulse.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Live',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3B82F6))),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('המומחה בדרך אליך',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E40AF))),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    // Inline live travel map — streams provider's GPS via
                    // LiveLocationService and renders a pulsing dot.
                    LiveTravelMap(providerUid: expertId),
                  ],
                ),
              ),
            ),
          ],

          // ── "In progress" timer ───────────────────────────────────────
          if (workStartedTs != null && status == 'paid_escrow') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Icon(Icons.construction_rounded,
                        size: 16,
                        color: const Color(0xFF16A34A)
                            .withValues(alpha: 0.5 + _pulse.value * 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'העבודה החלה לפני $workMinutes דקות',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D)),
                  ),
                ]),
              ),
            ),
          ],

          // ── Amount strip ─────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.lock_rounded,
                      size: 14, color: Color(0xFF6366F1)),
                  const SizedBox(width: 5),
                  Text(
                    isActive ? 'בנאמנות' : 'סכום',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ]),
                Text(
                  '₪${amount.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isCompleted
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF1A1A2E)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Action buttons ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              children: [

                if (status == 'expert_completed') ...[
                  // ── Deposit remainder notice (v12.1.0) ─────────────
                  // When a booking was paid with a deposit only, the
                  // customer now sees HOW MUCH will be charged on release
                  // so the "Confirm" button isn't a surprise.
                  if ((job['remainingAmount'] as num? ?? 0) > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined,
                              color: Color(0xFF1D4ED8), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'שולם בפיקדון: '
                                  '₪${((job['paidAtBooking'] as num?) ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1E40AF),
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'ייגבה בשחרור: '
                                  '₪${((job['remainingAmount'] as num?) ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1E40AF),
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  BookingPrimaryButton(
                    label: (job['remainingAmount'] as num? ?? 0) > 0
                        ? 'אשר ושלם את היתרה'
                        : 'אשר ושחרר תשלום',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () => widget.onCompleteJob(amount),
                  ),
                  const SizedBox(height: 8),
                  BookingSecondaryButton(
                    label: 'יש בעיה — פתח מחלוקת',
                    icon: Icons.report_outlined,
                    color: Colors.red,
                    onPressed: widget.onDispute,
                  ),
                ],

                if (status == 'paid_escrow') ...[
                  BookingQuickActionChip(
                    icon: Icons.cancel_outlined,
                    label: 'בטל הזמנה',
                    color: const Color(0xFFFEF2F2),
                    iconColor: Colors.red,
                    onPressed: () => widget.onCancel(amount),
                  ),
                ],

                if (isCompleted) ...[
                  if (!isReviewed) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text('איך היה השירות?',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              5,
                              (i) => GestureDetector(
                                onTap: widget.onRate,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Icon(Icons.star_rounded,
                                      size: 34,
                                      color: Colors.white
                                          .withValues(alpha: 0.45 + i * 0.11)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: widget.onRate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('שלח ביקורת ⭐',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF6366F1))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.volunteer_activism_rounded,
                          size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 5),
                      const Text('שלח טיפ:',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      for (final tip in [10.0, 20.0, 50.0])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _sendTip(context, tip),
                            child: Container(
                              margin: const EdgeInsetsDirectional.only(end: 6),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFFBBF24),
                                    width: 1),
                              ),
                              child: Text(
                                '₪${tip.toStringAsFixed(0)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E)),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 10),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 14, color: Color(0xFF16A34A)),
                            SizedBox(width: 6),
                            Text('ביקורת נשלחה — תודה!',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF16A34A))),
                          ]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  BookingPrimaryButton(
                    label: 'הזמן שוב את $expertName',
                    icon: Icons.replay_rounded,
                    color: const Color(0xFF6366F1),
                    onPressed: widget.onRebook,
                  ),
                  const SizedBox(height: 8),
                  BookingQuickActionChip(
                    icon: Icons.receipt_long_rounded,
                    label: 'קבלה',
                    onPressed: widget.onReceipt,
                  ),
                ],
              ],
            ),
          ),

          // ── Pet Mode entry (only on pet-services bookings) ─────────
          // Gated on `workStartedAt` — entry appears only after the provider
          // has tapped "הגעתי — התחל עבודה" (per Home Boarding spec §4).
          if (workStartedTs != null &&
              ((job['flagWalkTracking'] as bool? ?? false) ||
                  (job['flagDailyProof'] as bool? ?? false))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(
                      color: Color(0xFF6366F1), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.pets_rounded),
                label: const Text(
                  'מצב הכלב — מעקב חי, תמונות ופיד',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OwnerPetModeScreen(
                      jobId: widget.jobId,
                      jobStatus: status,
                      workStarted: job['workStartedAt'] != null,
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ── Direct Contact Bar (active bookings) ───────────────────
          if (isActive) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24)),
                border: Border(
                    top: BorderSide(color: Colors.grey.shade100, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: expertPhone.isNotEmpty
                          ? () => launchUrl(
                              Uri.parse('tel:$expertPhone'),
                              mode: LaunchMode.externalApplication)
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExpertProfileScreen(
                                    expertId: expertId,
                                    expertName: expertName,
                                  ),
                                ),
                              ),
                      borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_rounded,
                                size: 16,
                                color: expertPhone.isNotEmpty
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Text('📞 התקשר',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: expertPhone.isNotEmpty
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                      width: 1,
                      height: 30,
                      color: Colors.grey.shade200),
                  Expanded(
                    child: InkWell(
                      onTap: chatRoomId.isNotEmpty
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    receiverId: expertId,
                                    receiverName: expertName,
                                  ),
                                ),
                              )
                          : null,
                      borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color: chatRoomId.isNotEmpty
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Text('💬 שלח הודעה',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: chatRoomId.isNotEmpty
                                        ? const Color(0xFF6366F1)
                                        : const Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Footer: details link (non-active) ─────────────────────
          if (!isActive) ...[
            InkWell(
              onTap: widget.onDetails,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(24)),
                  border: Border(
                      top: BorderSide(
                          color: Colors.grey.shade100, width: 1)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('פרטי הזמנה',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500)),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Booking step indicator (Uber-style horizontal tracker) ─────────────────

class BookingStepIndicator extends StatelessWidget {
  final int currentStep; // 0–3

  const BookingStepIndicator({super.key, required this.currentStep});

  static const _steps = ['התקבלה', 'בדרך', 'בעבודה', 'הושלם'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final filled = i ~/ 2 < currentStep;
          return Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: filled
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final step     = i ~/ 2;
        final isActive = step == currentStep;
        final isDone   = step < currentStep;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width:  isActive ? 30 : 22,
              height: isActive ? 30 : 22,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF6366F1)
                    : isActive
                        ? Colors.white
                        : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
                border: isActive
                    ? Border.all(
                        color: const Color(0xFF6366F1), width: 2.5)
                    : null,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 12)
                    : isActive
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6366F1),
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _steps[step],
              style: TextStyle(
                  fontSize: 9,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? const Color(0xFF6366F1)
                      : isDone
                          ? const Color(0xFF6366F1).withValues(alpha: 0.7)
                          : const Color(0xFF94A3B8)),
            ),
          ],
        );
      }),
    );
  }
}
