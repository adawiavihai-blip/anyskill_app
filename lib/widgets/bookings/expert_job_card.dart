// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'booking_shared_widgets.dart';
import '../../widgets/customer_profile_sheet.dart';
import '../../widgets/pet_service_actions.dart';
import '../../features/pet_stay/screens/provider_pet_mode_screen.dart';
import '../../screens/chat_screen.dart';
import '../../services/live_location_service.dart';

/// Provider-facing job card with live signals, navigation, work stepper, and actions.
///
/// Extracted from my_bookings_screen.dart (Phase 2 refactor).
class ExpertJobCard extends StatefulWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final void Function(String jobId, String chatRoomId) onMarkDone;
  final void Function(String jobId) onCancel;
  final VoidCallback onDetails;
  final VoidCallback onReceipt;
  final VoidCallback? onRate;

  const ExpertJobCard({
    super.key,
    required this.job,
    required this.jobId,
    required this.onMarkDone,
    required this.onCancel,
    required this.onDetails,
    required this.onReceipt,
    this.onRate,
  });

  @override
  State<ExpertJobCard> createState() => _ExpertJobCardState();
}

class _ExpertJobCardState extends State<ExpertJobCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;
  Timer? _workTimer;
  bool _startingWork = false;

  static const _terminalStatuses = {
    'cancelled', 'cancelled_with_penalty', 'refunded',
    'split_resolved', 'completed',
  };

  static const _cancelledStatuses = {
    'cancelled', 'cancelled_with_penalty', 'refunded', 'split_resolved',
  };

  bool get _isTerminal =>
      _terminalStatuses.contains(widget.job['status'] as String? ?? '');

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    if (!_isTerminal) {
      _pulseCtrl.repeat(reverse: true);
      _workTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _workTimer?.cancel();
    super.dispose();
  }

  Future<void> _markOnTheWay() async {
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'expertOnWay':    true,
        'expertOnWayAt':  FieldValue.serverTimestamp(),
      });
      // Kick off live GPS broadcast so the customer's Active Booking
      // screen shows the provider moving on the map. Permission failures
      // are non-fatal — the status flag is still set.
      try {
        await LiveLocationService.startBroadcasting(activeJobId: widget.jobId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.orange,
            content: Text('מעקב חי לא פעיל: $e'),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('שגיאה: $e'),
        ));
      }
    }
  }

  Future<void> _markWorkStarted() async {
    setState(() => _startingWork = true);
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'workStartedAt': FieldValue.serverTimestamp(),
        'expertOnWay':   false,
      });
      // Stop broadcasting — the provider has arrived. Customer's map
      // falls back to the booking destination marker.
      await LiveLocationService.stopBroadcasting();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('שגיאה: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _startingWork = false);
    }
  }

  Future<void> _navigateToJob(String? lat, String? lng, String address) async {
    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    } else if (address.isNotEmpty) {
      final enc = Uri.encodeComponent(address);
      uri = Uri.parse('https://maps.google.com/?q=$enc');
    } else {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final job    = widget.job;
    final status = job['status'] as String? ?? '';

    // ── Lightweight card for cancelled/refunded states ──────────────────
    if (_cancelledStatuses.contains(status)) {
      return _buildCancelledCard(job, status);
    }

    final customerId   = job['customerId']   as String? ?? '';
    final customerName = job['customerName'] as String? ?? 'לקוח';
    final customerPhone = job['customerPhone'] as String? ?? '';
    final chatRoomId   = job['chatRoomId']   as String? ?? '';
    final address      = job['location']     as String? ?? '';
    final clientLat    = (job['clientLat'] as num?)?.toDouble().toString();
    final clientLng    = (job['clientLng'] as num?)?.toDouble().toString();
    final netAmount    = (job['netAmountForExpert'] ??
            job['totalPaidByCustomer'] ??
            job['totalAmount'] ??
            0.0)
        .toDouble();
    final workStartedTs = job['workStartedAt'] as Timestamp?;
    final expertOnWay   = job['expertOnWay'] == true;
    final workMinutes   = workStartedTs != null
        ? DateTime.now().difference(workStartedTs.toDate()).inMinutes
        : 0;

    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final apptStr  = apptDate != null
        ? DateFormat('dd/MM/yy').format(apptDate)
        : (() {
            if (job['createdAt'] is Timestamp) {
              return DateFormat('dd/MM/yy')
                  .format((job['createdAt'] as Timestamp).toDate());
            }
            return 'תאריך לא ידוע';
          })();
    final apptTime = job['appointmentTime'] as String? ?? '';

    final isPending   = status == 'paid_escrow';
    final isWaiting   = status == 'expert_completed';
    final isCompleted = status == 'completed';
    final isActive    = isPending || isWaiting;
    final hasNav      = address.isNotEmpty || (clientLat != null && clientLng != null);

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

          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => showCustomerProfileSheet(
                    context, customerId, customerName),
                child: BookingProfileAvatar(
                    uid: customerId, name: customerName, size: 50),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => showCustomerProfileSheet(
                      context, customerId, customerName),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1A1A2E))),
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                            apptTime.isNotEmpty
                                ? '$apptStr · $apptTime'
                                : apptStr,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8))),
                      ]),
                    ],
                  ),
                ),
              ),
              BookingStatusBadge(status),
            ]),
          ),

          // ── Client address + phone row ──────────────────────────────
          if (address.isNotEmpty || customerPhone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: Color(0xFF6366F1)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(address,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF475569))),
                        ),
                      ]),
                    if (address.isNotEmpty && customerPhone.isNotEmpty)
                      const SizedBox(height: 4),
                    if (customerPhone.isNotEmpty)
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('tel:$customerPhone'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Row(children: [
                          const Icon(Icons.phone_rounded,
                              size: 13, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Text(customerPhone,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Net amount strip ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCompleted
                  ? const Color(0xFFF0FFF4)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: isCompleted
                  ? Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.savings_rounded,
                    size: isCompleted ? 18 : 14,
                    color: isCompleted
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isCompleted ? 'סה"כ הרווח' : 'הרווח הצפוי',
                    style: TextStyle(
                      fontSize: isCompleted ? 13 : 12,
                      fontWeight: isCompleted
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isCompleted
                          ? const Color(0xFF15803D)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ]),
                Text(
                  '₪${netAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isCompleted ? 20 : 16,
                    color: isCompleted
                        ? const Color(0xFF15803D)
                        : const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),

          // ── Work-in-progress timer ────────────────────────────────
          if (workStartedTs != null && isPending) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Icon(Icons.construction_rounded,
                        size: 14,
                        color: const Color(0xFF16A34A)
                            .withValues(alpha: 0.5 + _pulse.value * 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text('עבודה החלה לפני $workMinutes דקות',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF15803D))),
                ]),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Actions ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              children: [

                if (isPending) ...[
                  if (hasNav) ...[
                    BookingPrimaryButton(
                      label: 'נווט לעבודה 🚗',
                      icon: Icons.directions_car_rounded,
                      color: const Color(0xFF0F172A),
                      onPressed: () =>
                          _navigateToJob(clientLat, clientLng, address),
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (workStartedTs == null && !expertOnWay) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.directions_car_rounded, size: 20),
                        label: const Text('אני בדרך 🚗',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        onPressed: () => _markOnTheWay(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (workStartedTs == null && expertOnWay) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _startingWork
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.handyman_rounded, size: 20),
                        label: const Text('הגעתי — התחל עבודה 🛠️',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        onPressed:
                            _startingWork ? null : _markWorkStarted,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Pet services module — walk tracking + daily proof ──
                  // Schema flags (`flagWalkTracking`, `flagDailyProof`) are
                  // cached on the job doc by the booking flow, so we don't
                  // need to re-fetch the category schema here.
                  // Gated on `workStartedAt` — actions become available only
                  // after the provider taps "הגעתי — התחל עבודה".
                  if (workStartedTs != null &&
                      ((job['flagWalkTracking'] as bool? ?? false) ||
                          (job['flagDailyProof'] as bool? ?? false))) ...[
                    // Entry point to the dedicated Pet Mode screen (dog
                    // card + daily schedule + future media feed).
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                          'מצב מטפל — פרופיל כלב ולוח זמנים',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProviderPetModeScreen(
                                jobId: widget.jobId),
                          ),
                        ),
                      ),
                    ),
                    PetServiceActions(
                      jobId: widget.jobId,
                      customerId: customerId,
                      customerName: customerName,
                      providerId: job['expertId'] as String? ?? '',
                      providerName: job['expertName'] as String? ?? '',
                      chatRoomId: chatRoomId,
                      walkTracking: job['flagWalkTracking'] as bool? ?? false,
                      dailyProof: job['flagDailyProof'] as bool? ?? false,
                    ),
                  ],

                  // "סיימתי" appears only after work has started (per spec
                  // progressive-disclosure for boarding/walks).
                  if (workStartedTs != null) ...[
                    BookingPrimaryButton(
                      label: 'סיימתי את העבודה',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF16A34A),
                      onPressed: () =>
                          widget.onMarkDone(widget.jobId, chatRoomId),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(children: [
                    Expanded(
                      child: BookingQuickActionChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'שלח הודעה',
                        onPressed: chatRoomId.isNotEmpty
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      receiverId: customerId,
                                      receiverName: customerName,
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BookingQuickActionChip(
                        icon: Icons.cancel_outlined,
                        label: 'בטל הזמנה',
                        color: const Color(0xFFFEF2F2),
                        iconColor: Colors.red,
                        onPressed: () => widget.onCancel(widget.jobId),
                      ),
                    ),
                  ]),
                ],

                if (isWaiting) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_top_rounded,
                              size: 15, color: Color(0xFF3B82F6)),
                          SizedBox(width: 6),
                          Text('ממתין לאישור הלקוח',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF3B82F6),
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                ],

                if (isCompleted) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, size: 20),
                      label: const Text('הצג קבלה',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: widget.onReceipt,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (ctx) {
                    Timestamp? toTs(dynamic v) => v is Timestamp ? v : null;
                    final completedTs =
                        toTs(job['completedAt']) ?? toTs(job['createdAt']);
                    final windowOpen = completedTs == null ||
                        DateTime.now()
                                .difference(completedTs.toDate())
                                .inDays <
                            7;
                    final reviewed = job['providerReviewDone'] == true;

                    if (reviewed) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
                          ],
                        ),
                      );
                    }
                    if (windowOpen) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.star_rounded, size: 20),
                          label: const Text('שתף חוות דעת ⭐',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          onPressed: widget.onRate,
                        ),
                      );
                    }
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_clock_rounded,
                              size: 14, color: Color(0xFF94A3B8)),
                          SizedBox(width: 6),
                          Text('חלון הביקורת פג (7 ימים)',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8))),
                        ],
                      ),
                    );
                  }),
                ],

                if (!isActive && !isCompleted) ...[
                  BookingStatusBadge(status),
                ],
              ],
            ),
          ),

          // ── Footer ───────────────────────────────────────────────────
          InkWell(
            onTap: widget.onDetails,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(
                    top: BorderSide(color: Colors.grey.shade100, width: 1)),
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
      ),
    );
  }

  Widget _buildCancelledCard(Map<String, dynamic> job, String status) {
    final customerName = job['customerName'] as String? ?? 'לקוח';
    final customerId   = job['customerId']   as String? ?? '';
    final amount = ((job['netAmountForExpert'] ??
                job['totalPaidByCustomer'] ??
                job['totalAmount'] ?? 0.0) as num)
            .toDouble();
    DateTime? apptDate;
    if (job['appointmentDate'] is Timestamp) {
      apptDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    final dateStr = apptDate != null
        ? DateFormat('dd/MM/yy').format(apptDate)
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: BookingProfileAvatar(uid: customerId, name: customerName, size: 44),
        title: Text(customerName,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF1A1A2E))),
        subtitle: Text(
          [
            if (dateStr.isNotEmpty) dateStr,
            if (amount > 0) '₪${amount.toStringAsFixed(0)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BookingStatusBadge(status),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onDetails,
              child: const Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Expert earnings summary bar ────────────────────────────────────────────

class ExpertEarningsSummary extends StatelessWidget {
  final double expectedEarnings;
  final int    activeCount;

  const ExpertEarningsSummary({
    super.key,
    required this.expectedEarnings,
    required this.activeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('סה"כ רווח צפוי',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              Text(
                '₪${expectedEarnings.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$activeCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const Text('הזמנות',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ]),
    );
  }
}
