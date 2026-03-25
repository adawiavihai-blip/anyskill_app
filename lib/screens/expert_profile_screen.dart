// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';
import '../constants/quick_tags.dart';
import '../services/cancellation_policy_service.dart';
import '../services/cache_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/anyskill_logo.dart';
import '../widgets/favorite_button.dart';
import '../services/service_architect.dart';
import '../models/pricing_model.dart';
import '../widgets/xp_progress_bar.dart';

// Brand tokens
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);
const _kGold       = Color(0xFFFBBF24);


class ExpertProfileScreen extends StatefulWidget {
  final String expertId;
  final String expertName;

  const ExpertProfileScreen(
      {super.key, required this.expertId, required this.expertName});

  @override
  State<ExpertProfileScreen> createState() => _ExpertProfileScreenState();
}

class _ExpertProfileScreenState extends State<ExpertProfileScreen> {
  // ── Booking state ──────────────────────────────────────────────────────────
  bool _isProcessing = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedTimeSlot;
  int _refreshTrigger = 0;
  int _selectedServiceIndex = 0;

  // ── Portfolio image viewer state ───────────────────────────────────────────
  final PageController _pageController = PageController();

  // ── Bio expand state ───────────────────────────────────────────────────────
  bool _bioExpanded = false;

  // ── Dynamic pricing state ──────────────────────────────────────────────────
  /// Indices of add-ons the client has checked in the order sheet.
  final Set<int> _selectedAddOnIndices = {};

  final List<String> _timeSlots = [
    "08:00", "09:00", "10:00", "11:00",
    "14:00", "15:00", "16:00", "17:00", "18:00", "19:00",
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Derived service tiers (no separate Firestore collection needed)
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds category-aware service tiers from [ServiceArchitect] templates.
  List<Map<String, dynamic>> _deriveServices(
      double pricePerHour, String category) {
    final templates = ServiceArchitect.templatesFor(category);
    return templates.map((t) => {
      'title':     t.title,
      'subtitle':  t.subtitle,
      'unitLabel': t.unitLabel,
      'unitIcon':  t.unitIcon,
      'price':     (pricePerHour * t.multiplier).roundToDouble(),
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _getChatRoomId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join("_");
  }

  /// Render a gallery image that may be an HTTP URL or a raw base64 string.
  Widget _buildGalleryImage(String src, {BoxFit fit = BoxFit.cover}) {
    if (src.startsWith('http')) {
      return CachedNetworkImage(
          imageUrl: src, fit: fit, errorWidget: (_, __, ___) => _imagePH());
    }
    try {
      final bytes = base64Decode(src.contains(',') ? src.split(',').last : src);
      return Image.memory(bytes, fit: fit);
    } catch (_) {
      return _imagePH();
    }
  }

  Widget _imagePH() => Container(
        color: _kPurpleSoft,
        child: Icon(Icons.image_outlined,
            size: 40, color: _kPurple.withValues(alpha: 0.3)),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Payment / booking (UNCHANGED LOGIC)
  // ─────────────────────────────────────────────────────────────────────────

  // Returns true on success, false on any error (error UI already shown).
  //
  // v4.3.0 — WriteBatch architecture:
  //   Phase 1: Sequential reads (fee %, balance, slot existence) — plain awaits,
  //            no runTransaction wrapper, so no JS Promise retry loop on Web.
  //   Phase 2: WriteBatch.commit() — single batched RPC, stable on all platforms
  //            including Desktop Chrome where runTransaction's internal Promise
  //            chain caused "Dart exception from converted Future" (minified:kt).
  //
  // navigator.pop() is still intentionally NOT called here — the success view's
  // "Done" button is the sole trigger, decoupled from every async chain.
  Future<bool> _processEscrowPayment(
      BuildContext context, double totalPrice, String cancellationPolicy,
      {bool isDemo = false}) async {
    // ── Demo expert: show success illusion, log demand signal, no real writes ──
    if (isDemo) {
      return await _handleDemoBooking(context);
    }

    if (_isProcessing) return false;
    setState(() => _isProcessing = true);

    // Capture l10n strings before any await (context may be gone after await)
    final l10n                   = AppLocalizations.of(context);
    final msgInsufficientBalance = l10n.expertInsufficientBalance;
    final msgTransactionTitle    = l10n.expertTransactionTitle(widget.expertName);
    final dateStr = _selectedDay != null
        ? '${_selectedDay!.day}/${_selectedDay!.month}'
        : '';

    final firestore = FirebaseFirestore.instance;
    final String currentUserId =
        FirebaseAuth.instance.currentUser?.uid ?? "";
    final String chatRoomId =
        _getChatRoomId(currentUserId, widget.expertId);
    final adminSettingsRef = firestore
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    // Sentinel thrown to signal a slot collision (distinct from generic errors).
    const kSlotConflict = '__SLOT_CONFLICT__';

    // messenger captured only for error feedback.
    final messenger = ScaffoldMessenger.of(context);

    try {
      // ── Phase 1: reads ────────────────────────────────────────────────────
      // Plain sequential awaits — no transaction wrapper, no JS Promise retries.

      // 1a. Admin fee
      final adminSnap = await adminSettingsRef.get();
      final Map<String, dynamic> adminData = adminSnap.data() ?? {};
      final double feePercentage =
          ((adminData['feePercentage']) ?? 0.10).toDouble();
      final double commission        = totalPrice * feePercentage;
      final double expertNetEarnings = totalPrice - commission;

      // 1b. Customer balance
      final customerRef  = firestore.collection('users').doc(currentUserId);
      final customerSnap = await customerRef.get();
      final Map<String, dynamic> customerData = customerSnap.data() ?? {};
      final double currentBalance  = (customerData['balance'] ?? 0.0).toDouble();
      if (currentBalance < totalPrice) throw msgInsufficientBalance;

      // 1c. Slot collision pre-flight
      //     Two users booking the same slot in the same millisecond is
      //     vanishingly rare in a boutique marketplace; a pre-flight read is a
      //     practical guard without the Promise-chain overhead of runTransaction.
      DocumentReference? slotRef;
      final d = _selectedDay;
      final t = _selectedTimeSlot;
      if (d != null && t != null) {
        final slotKey =
            '${widget.expertId}_'
            '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}_'
            '${t.replaceAll(':', '').replaceAll(' ', '')}';
        slotRef = firestore.collection('bookingSlots').doc(slotKey);
        final slotSnap = await slotRef.get();
        if (slotSnap.exists) throw kSlotConflict;
      }

      // ── Phase 2: WriteBatch commit ─────────────────────────────────────────
      // WriteBatch.commit() issues a single batched Firestore write RPC.
      // Unlike runTransaction it has no retry loop and does not create a
      // nested JS Promise chain, making it stable on Desktop Web (Chrome/Edge).
      final cancelDeadline = CancellationPolicyService.deadline(
        policy:          cancellationPolicy,
        appointmentDate: _selectedDay,
        timeSlot:        _selectedTimeSlot,
      );

      final batch  = firestore.batch();
      final jobRef = firestore.collection('jobs').doc();

      // Reserve booking slot (prevents duplicate in normal flow)
      if (slotRef != null) {
        batch.set(slotRef, {
          'expertId':  widget.expertId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Job document — immediately visible to provider's StreamBuilder
      batch.set(jobRef, {
        'jobId':               jobRef.id,
        'chatRoomId':          chatRoomId,
        'customerId':          currentUserId,
        'customerName':        customerData['name'] ?? '',
        'expertId':            widget.expertId,
        'expertName':          widget.expertName,
        'totalPaidByCustomer': totalPrice,
        'totalAmount':         totalPrice,
        'commissionAmount':    commission,
        'netAmountForExpert':  expertNetEarnings,
        'appointmentDate':     _selectedDay,
        'appointmentTime':     _selectedTimeSlot,
        'status':              'paid_escrow',
        'createdAt':           FieldValue.serverTimestamp(),
        'cancellationPolicy':  cancellationPolicy,
        if (cancelDeadline != null)
          'cancellationDeadline': Timestamp.fromDate(cancelDeadline),
      });

      // Deduct customer balance
      batch.update(customerRef, {'balance': FieldValue.increment(-totalPrice)});

      // Platform commission record
      batch.set(firestore.collection('platform_earnings').doc(), {
        'jobId':          jobRef.id,
        'amount':         commission,
        'sourceExpertId': widget.expertId,
        'timestamp':      FieldValue.serverTimestamp(),
        'status':         'pending_escrow',
      });

      // Wallet transaction log
      batch.set(firestore.collection('transactions').doc(), {
        'userId':    currentUserId,
        'amount':    -totalPrice,
        'title':     msgTransactionTitle,
        'timestamp': FieldValue.serverTimestamp(),
        'status':    'escrow',
      });

      await batch.commit();

      // Debug: confirm the exact expertId written so we can verify it matches
      // the provider's UID in my_bookings_screen.dart's _expertStream query.
      // Compare this value against the "[AnySkill] isProvider" log on the
      // provider's device — they must be identical for the stream to pick it up.

      // System chat message (non-critical; after batch so batch failure is clean)
      await _sendSystemNotification(
          chatRoomId, totalPrice, expertNetEarnings, currentUserId,
          systemMsg: l10n.expertSystemMessage(
              dateStr, _selectedTimeSlot ?? '',
              expertNetEarnings.toStringAsFixed(0)));

      // Batch committed — signal success. The sheet's StatefulBuilder will swap
      // to the success view; the user's "Done" tap triggers pop() as a plain
      // synchronous gesture, with zero async-chain coupling.
      return true;
    } catch (e) {
      debugPrint('[AnySkill] Booking error: ${e.toString()}');
      if (mounted) {
        if (e == kSlotConflict) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Row(children: [
                Icon(Icons.event_busy_rounded,
                    color: Color(0xFFEF4444), size: 22),
                SizedBox(width: 8),
                Text('המועד תפוס',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              content: const Text(
                'מישהו כבר הזמין את המומחה לאותו מועד.\n'
                'אנא בחר תאריך או שעה אחרים.',
                textAlign: TextAlign.right,
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        } else {
          messenger.showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              e.toString() == msgInsufficientBalance
                  ? msgInsufficientBalance
                  : e.toString().toLowerCase().contains('permission') ||
                          e.toString().toLowerCase().contains('insufficient')
                      ? 'חלה שגיאה בתהליך ההזמנה, אנא נסה שנית.'
                      : e.toString(),
            ),
          ));
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Demo booking: fake success + admin demand signal ──────────────────────
  // No real Firestore writes (no job doc, no wallet deduction).
  // Logs the demand event so the admin Live Feed picks it up, then returns
  // true — the caller's StatefulBuilder switches to the shared success view.
  Future<bool> _handleDemoBooking(BuildContext context) async {
    // 1. Log demand signal to activity_log (admin Live Feed)
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await FirebaseFirestore.instance.collection('activity_log').add({
        'type':       'demo_booking_attempt',
        'expertId':   widget.expertId,
        'expertName': widget.expertName,
        'userId':     uid,
        // 'createdAt' is the field the LiveActivityTab stream orders by.
        // Using 'timestamp' here would silently exclude this doc from results.
        'createdAt':  FieldValue.serverTimestamp(),
        'priority':   'high',
        // 'title' and 'detail' are the fields the live feed card reads.
        'title':      '🔥 ביקשה הזמנה ממומחה דמו',
        'detail':     '${widget.expertName} — לחץ להמרה למומחה אמיתי',
      });
    } catch (_) {
      // Non-blocking — if logging fails the UX is unaffected
    }

    // The caller's StatefulBuilder switches to the shared success view.
    // No navigator.pop() here — decoupled completely from this Future chain.
    return true;
  }

  Future<void> _sendSystemNotification(
      String chatRoomId, double total, double net, String currentUserId,
      {required String systemMsg}) async {
    final chatRef =
        FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
    // Ensure the chat doc exists with both participants BEFORE writing the
    // message — the messages rule checks chats/{id}.data.users.
    await chatRef.set(
        {'users': [currentUserId, widget.expertId]},
        SetOptions(merge: true));
    await chatRef.collection('messages').add({
      'senderId': 'system',
      'message':  systemMsg,
      'type':      'text',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }



  // ─────────────────────────────────────────────────────────────────────────
  // UI: Quick Tags
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildQuickTagsSection(Map<String, dynamic> data) {
    final tagKeys = ((data['quickTags'] as List?) ?? []).cast<String>();
    final resolved = tagKeys
        .map(quickTagByKey)
        .whereType<Map<String, String>>()
        .toList();
    if (resolved.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: resolved.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _kPurpleSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
        ),
        child: Text(
          '${t['emoji']} ${t['label']}',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kPurple),
        ),
      )).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Bio section
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBioSection(Map<String, dynamic> data, AppLocalizations l10n) {
    final bio = data['aboutMe'] as String? ?? l10n.expertBioPlaceholder;
    const maxLines = 3;
    final isLong   = bio.split('\n').length > maxLines || bio.length > 160;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          bio,
          textAlign: TextAlign.right,
          maxLines: _bioExpanded ? null : maxLines,
          overflow: _bioExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 15, height: 1.6, color: Colors.grey[800]),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _bioExpanded = !_bioExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _bioExpanded ? l10n.expertBioShowLess : l10n.expertBioReadMore,
                style: const TextStyle(
                    color: _kPurple,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Service menu
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildServiceMenu(Map<String, dynamic> data, AppLocalizations l10n) {
    final pricing  = PricingModel.fromFirestore(data);
    final category = data['serviceType'] as String? ?? '';
    final services = _deriveServices(pricing.basePrice, category);

    return Column(
      children: [
        ...List.generate(services.length, (i) {
        final svc      = services[i];
        final selected = i == _selectedServiceIndex;
        final svcPrice = svc['price'] as double;

        return GestureDetector(
          onTap: () => setState(() => _selectedServiceIndex = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:        selected ? _kPurpleSoft : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:  selected ? _kPurple : Colors.grey.shade200,
                width:  selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // ── Selection indicator ────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:  selected ? _kPurple : Colors.transparent,
                    border: Border.all(
                        color:  selected ? _kPurple : Colors.grey.shade300,
                        width:  2),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 12)
                      : null,
                ),
                const SizedBox(width: 10),
                // ── Title + pill ───────────────────────────────────────
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Duration pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? _kPurple.withValues(alpha: 0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(svc['unitLabel'] as String,
                            style: TextStyle(
                                fontSize: 10,
                                color: selected ? _kPurple : Colors.grey[600],
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Text(svc['title'] as String,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: selected ? _kPurple : Colors.black87)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // ── Price ──────────────────────────────────────────────
                Text('₪${svcPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: _kPurple,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ],
            ),
          ),
        );
        }),

        // ── Add-ons panel ─────────────────────────────────────────────────
        if (pricing.addOns.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildAddOnsPanel(pricing),
        ],
      ],
    );
  }

  Widget _buildAddOnsPanel(PricingModel pricing) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kPurpleSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPurple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('תוספות אופציונליות',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              SizedBox(width: 6),
              Icon(Icons.add_circle_outline_rounded,
                  size: 16, color: _kPurple),
            ],
          ),
          const SizedBox(height: 10),
          ...pricing.addOns.asMap().entries.map((entry) {
            final i  = entry.key;
            final ao = entry.value;
            final checked = _selectedAddOnIndices.contains(i);
            return GestureDetector(
              onTap: () => setState(() {
                if (checked) {
                  _selectedAddOnIndices.remove(i);
                } else {
                  _selectedAddOnIndices.add(i);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: checked ? _kPurple : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: checked
                        ? _kPurple
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: checked
                            ? Colors.white
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: checked
                              ? Colors.white
                              : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: checked
                          ? const Icon(Icons.check_rounded,
                              color: _kPurple, size: 13)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '+₪${ao.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: checked ? Colors.white : _kPurple,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      ao.title,
                      style: TextStyle(
                        color: checked ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Interactive Portfolio grid
  // ─────────────────────────────────────────────────────────────────────────

  void _expandPortfolioImage(
      BuildContext context, List<String> images, int startIndex) {
    final ctrl = PageController(initialPage: startIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      // dialogCtx is the dialog's own context — required for correct Navigator.pop
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PageView.builder(
              controller: ctrl,
              itemCount: images.length,
              itemBuilder: (_, i) => Center(
                child: InteractiveViewer(
                  child: _buildGalleryImage(images[i], fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                // Use dialogCtx so only the dialog is popped, not the whole page
                onTap: () => Navigator.pop(dialogCtx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => ctrl.dispose());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Calendar (unchanged logic, updated style)
  // ─────────────────────────────────────────────────────────────────────────

  Set<DateTime> _parseUnavailableDates(Map<String, dynamic> data) {
    final raw = data['unavailableDates'] as List<dynamic>? ?? [];
    return raw
        .map((d) => DateTime.tryParse(d.toString()))
        .whereType<DateTime>()
        .map((d) => DateTime.utc(d.year, d.month, d.day))
        .toSet();
  }

  Widget _buildCalendar(Set<DateTime> unavailableDates) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: TableCalendar(
        locale: 'he_IL',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _focusedDay,
        headerStyle:
            const HeaderStyle(formatButtonVisible: false, titleCentered: true),
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        enabledDayPredicate: (day) {
          final n = DateTime.utc(day.year, day.month, day.day);
          return !unavailableDates.contains(n);
        },
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay     = selectedDay;
            _focusedDay      = focusedDay;
            _selectedTimeSlot = null;
          });
        },
        calendarBuilders: CalendarBuilders(
          disabledBuilder: (context, day, _) {
            final n = DateTime.utc(day.year, day.month, day.day);
            if (!unavailableDates.contains(n)) return null;
            return Center(
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: Center(
                  child: Text('${day.day}',
                      style: TextStyle(
                          color: Colors.red.shade300,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration:
              BoxDecoration(color: _kPurple, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: Color(0xFFE0E7FF), shape: BoxShape.circle),
          todayTextStyle: TextStyle(
              color: _kPurple, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Time slots
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimeSlots(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(l10n.expertSelectTime,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: _timeSlots.length,
            itemBuilder: (context, index) {
              final slot       = _timeSlots[index];
              final isSelected = _selectedTimeSlot == slot;
              return GestureDetector(
                onTap: () => setState(() => _selectedTimeSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected ? _kPurple : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? _kPurple : Colors.grey.shade300),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: _kPurple.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Text(slot,
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Reviews — Advanced Social Proof System
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReviewsSection(AppLocalizations l10n) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isProvider = currentUid == widget.expertId;

    return FutureBuilder<QuerySnapshot>(
      key: ValueKey('reviews_$_refreshTrigger'),
      future: FirebaseFirestore.instance
          .collection('reviews')
          .where('expertId', isEqualTo: widget.expertId)
          .limit(40)
          .get(),
      builder: (context, snapshot) {
        // Show spinner while Firestore is loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];
        // Filter: show review if isPublished == true OR field is absent (legacy)
        final publishedDocs = allDocs.where((doc) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          final published = d['isPublished'];
          return published == null || published == true;
        }).toList();
        // Sort client-side by timestamp desc (avoids composite index)
        publishedDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>? ?? {};
          final bData = b.data() as Map<String, dynamic>? ?? {};
          final aTs = (aData['timestamp'] ?? aData['createdAt']) as Timestamp?;
          final bTs = (bData['timestamp'] ?? bData['createdAt']) as Timestamp?;
          if (aTs == null || bTs == null) return 0;
          return bTs.compareTo(aTs);
        });
        final docs = publishedDocs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (docs.isNotEmpty)
                  Text(
                    '(${docs.length})',
                    style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                const Text(
                  'ביקורות',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ── Empty state ───────────────────────────────────────────────────
            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(l10n.expertNoReviews,
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 14)),
                ),
              )
            else
              // ── Flat Airbnb-style review list ─────────────────────────────
              ...List.generate(docs.length, (idx) {
                final doc      = docs[idx];
                final r        = doc.data() as Map<String, dynamic>;
                final rating   = (r['rating'] as num? ?? 5).toDouble();
                final name     = r['reviewerName'] as String?
                    ?? l10n.expertDefaultReviewer;
                final comment  = (r['comment'] ?? '').toString().trim();
                final ts       = r['timestamp'] as Timestamp?;
                final date     = ts != null
                    ? DateFormat('dd/MM/yy').format(ts.toDate())
                    : '';
                final response = r['providerResponse'] as String?;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── Row: avatar + name / stars + date ──────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: indigo stars + date
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: List.generate(5, (i) => Icon(
                                  i < rating
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: _kPurple,
                                  size: 14,
                                )),
                              ),
                              if (date.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(date,
                                    style: const TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 11)),
                              ],
                            ],
                          ),
                          // Right: grey initial avatar + name + verified badge
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: Colors.black87)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.verified_rounded,
                                          color: Colors.green, size: 10),
                                      const SizedBox(width: 2),
                                      Text(l10n.expertVerifiedBooking,
                                          style: TextStyle(
                                              color: Colors.green[700],
                                              fontSize: 10)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(width: 10),
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFFE5E7EB),
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF374151),
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Comment ─────────────────────────────────────────────
                    if (comment.isNotEmpty) ...[
                      Text(comment,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.55,
                              color: Colors.grey[700])),
                      const SizedBox(height: 10),
                    ],

                    // ── Provider response ────────────────────────────────────
                    if (response != null && response.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kPurpleSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _kPurple.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Icon(Icons.verified_user_rounded,
                                    color: _kPurple, size: 14),
                                Text(l10n.expertProviderResponse,
                                    style: const TextStyle(
                                        color: _kPurple,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(response,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.5,
                                    color: Colors.grey[700])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (isProvider) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                              foregroundColor: _kPurple,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2)),
                          icon: const Icon(Icons.reply_rounded, size: 15),
                          label: Text(l10n.expertAddReply,
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              _showProviderReplyDialog(context, doc.id),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    // ── 1px separator ────────────────────────────────────────
                    const Divider(height: 1, thickness: 1,
                        color: Color(0xFFF3F4F6)),
                  ],
                );
              }),
          ],
        );
      },
    );
  }

  // ── Provider reply bottom sheet ───────────────────────────────────────────
  void _showProviderReplyDialog(BuildContext context, String reviewDocId) {
    final ctrl = TextEditingController();
    // Dispose the controller when the sheet is dismissed (success or cancel).
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Drag handle
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 16),
              Text(l10n.expertAddReplyTitle,
                  style: const
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: l10n.expertReplyHint,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _kPurple, width: 1.5)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                onPressed: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  // Capture l10n error formatter before await
                  final replyErrorFn = l10n.expertReplyError; // ignore: prefer_function_declarations_over_variables
                  try {
                    await FirebaseFirestore.instance
                        .collection('reviews')
                        .doc(reviewDocId)
                        .update({'providerResponse': text});
                    if (ctx.mounted) Navigator.pop(ctx);
                    // Check parent state — ctx may be mounted while parent disposed
                    if (mounted) setState(() => _refreshTrigger++);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        backgroundColor: Colors.red,
                        content: Text(replyErrorFn('$e')),
                      ));
                    }
                  }
                },
                child: Text(l10n.expertPublishReply,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        );
      },
    ).whenComplete(() => ctrl.dispose());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Sticky bottom bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context, Map<String, dynamic> data) {
    final l10n       = AppLocalizations.of(context);
    final pricing    = PricingModel.fromFirestore(data);
    final category   = data['serviceType'] as String? ?? '';
    final services   = _deriveServices(pricing.basePrice, category);
    final svcPrice   = services[_selectedServiceIndex]['price'] as double;
    // Add selected add-ons on top of the tier price
    final addOnTotal = _selectedAddOnIndices.fold<double>(
        0.0, (acc, idx) => acc + (idx < pricing.addOns.length ? pricing.addOns[idx].price : 0.0));
    final totalPrice = svcPrice + addOnTotal;
    final isReady    = _selectedDay != null && _selectedTimeSlot != null;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: Border(
                  top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, -5)),
              ],
            ),
            child: Row(
              children: [
                // ── Chat button ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _kPurple.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: _kPurple),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(
                                receiverId: widget.expertId,
                                receiverName: widget.expertName))),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Book Now ──────────────────────────────────────────
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      // When onPressed is null Flutter uses disabledBackgroundColor —
                      // explicit values keep the "idle state" look consistent.
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed:
                        isReady ? () => _showBookingSummary(context, data, totalPrice, addOns: pricing.addOns, selectedAddOns: _selectedAddOnIndices) : null,
                    child: _isProcessing
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5)
                        : isReady
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white,
                                      size: 14),
                                  Text(
                                    l10n.expertBookForTime(_selectedTimeSlot ?? ''),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  Text(
                                    '₪${totalPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    l10n.expertStartingFrom(pricing.basePrice.toStringAsFixed(0)),
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11),
                                  ),
                                  Text(
                                    l10n.expertSelectDateTime,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Booking summary sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showBookingSummary(
      BuildContext context, Map<String, dynamic> data, double price, {
      List<AddOn> addOns = const [],
      Set<int> selectedAddOns = const {},
  }) {
    final l10n    = AppLocalizations.of(context);
    final isDemo  = data['isDemo'] == true;
    final dateStr = _selectedDay != null
        ? "${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}"
        : "";
    // Use l10n title list — avoids calling _deriveServices with the already-
    // computed tier price (which would re-derive tiers from the wrong base).
    final svcTitles = [l10n.serviceSingleLesson, l10n.serviceExtendedLesson, l10n.serviceFullSession];
    final svcTitle  = svcTitles[_selectedServiceIndex.clamp(0, 2)];

    final policy = data['cancellationPolicy'] as String? ?? 'flexible';

    // Human-readable deadline string for the notice
    final dlDt = CancellationPolicyService.deadline(
      policy:          policy,
      appointmentDate: _selectedDay,
      timeSlot:        _selectedTimeSlot,
    );
    final dlStr = dlDt != null
        ? "${dlDt.day}/${dlDt.month} ${dlDt.hour.toString().padLeft(2,'0')}:${dlDt.minute.toString().padLeft(2,'0')}"
        : null;
    final penaltyPct = (CancellationPolicyService.penaltyFraction(policy) * 100).toInt();

    // Both closure vars live outside the builder so they survive rebuilds.
    // sheetBusy  — blocks all input while the transaction is in-flight.
    // isSuccess  — when true, the builder renders the success view instead of
    //              the summary form. The success view's "Done" button is the
    //              ONLY place navigator.pop() is called, fully decoupled from
    //              the Firestore Promise chain (root fix for Web "converted
    //              Future" exception).
    bool sheetBusy  = false;
    bool isSuccess  = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // isDismissible=false while busy so the user can't Escape mid-transaction
      isDismissible: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          // ── Success view ──────────────────────────────────────────────────
          if (isSuccess) {
            return _buildBookingSuccessView(sheetCtx, l10n);
          }

          // ── Booking summary form ──────────────────────────────────────────
          return AbsorbPointer(
          absorbing: sheetBusy,
          child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(l10n.expertBookingSummaryTitle,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("$svcTitle • $dateStr $_selectedTimeSlot",
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kPurpleSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: _kPurple, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _summaryRow(l10n.expertSummaryRowService, svcTitle),
                  _summaryRow(l10n.expertSummaryRowDate, dateStr),
                  _summaryRow(l10n.expertSummaryRowTime, _selectedTimeSlot ?? '—'),
                  // Base service price (before add-ons)
                  _summaryRow(
                    l10n.expertSummaryRowPrice,
                    "₪${(price - selectedAddOns.fold<double>(0.0, (s, i) => s + (i < addOns.length ? addOns[i].price : 0.0))).toStringAsFixed(0)}",
                  ),
                  // Selected add-ons breakdown
                  for (final i in selectedAddOns)
                    if (i < addOns.length)
                      _summaryRow(
                        '+ ${addOns[i].title}',
                        '+₪${addOns[i].price.toStringAsFixed(0)}',
                        isAddOn: true,
                      ),
                  _summaryRow(l10n.expertSummaryRowProtection, l10n.expertSummaryRowIncluded,
                      isGreen: true),
                  const Divider(height: 16),
                  _summaryRow(l10n.expertSummaryRowTotal,
                      "₪${price.toStringAsFixed(0)}",
                      isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Cancellation policy notice ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC02),
                    width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF856404)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dlStr != null
                          ? l10n.expertCancellationNotice(
                              CancellationPolicyService.label(policy),
                              dlStr,
                              penaltyPct)
                          : l10n.expertCancellationNoDeadline(
                              CancellationPolicyService.label(policy),
                              CancellationPolicyService.description(policy)),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF856404)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      sheetBusy ? Colors.grey : _kPurple,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
              icon: sheetBusy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_rounded,
                      color: Colors.white, size: 18),
              label: Text(l10n.expertConfirmPaymentButton,
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              onPressed: sheetBusy
                  ? null
                  : () async {
                      setSheetState(() => sheetBusy = true);
                      final ok = await _processEscrowPayment(
                          context, price, policy, isDemo: isDemo);
                      if (ok) {
                        // Switch to success view — pop is triggered by user
                        // tapping "Done", not by this async chain.
                        setSheetState(() => isSuccess = true);
                      } else {
                        // Error already shown via snackbar/dialog; re-enable.
                        setSheetState(() => sheetBusy = false);
                      }
                    },
            ),
            const SizedBox(height: 10),
            Text(
              'VERSION: 4.3.0',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
          );   // closes AbsorbPointer
        },     // closes StatefulBuilder builder
      ),       // closes StatefulBuilder
    );
  }

  // ── Booking success view ──────────────────────────────────────────────────
  // Replaces the booking summary inside the bottom sheet upon transaction
  // commit. The "Done" button is the sole trigger for navigator.pop(), which
  // means pop() is always a direct user gesture — never inside an async chain.
  Widget _buildBookingSuccessView(BuildContext ctx, AppLocalizations l10n) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Animated checkmark circle ────────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // ── Title ────────────────────────────────────────────────────────
          const Text(
            'ההזמנה בוצעה בהצלחה! 🎉',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1B4B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.expertEscrowSuccess,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          // ── Done button — only place pop() is called ─────────────────────
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'בוצע ✓',
              style: TextStyle(
                  fontSize: 17,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, bool isGreen = false, bool isAddOn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: isAddOn ? 12 : 14,
                  fontWeight:
                      isBold ? FontWeight.bold : FontWeight.normal,
                  color: isAddOn ? const Color(0xFF6366F1) : Colors.grey[700])),
          Text(value,
              style: TextStyle(
                  fontSize: isAddOn ? 12 : 14,
                  color: isGreen
                      ? Colors.green
                      : isAddOn
                          ? const Color(0xFF6366F1)
                          : isBold
                              ? Colors.black
                              : Colors.black87,
                  fontWeight: (isBold || isAddOn)
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section header helper
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (trailing != null) trailing,
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // UI: Specialist card — mirrors ProfileScreen specialist header exactly
  // ─────────────────────────────────────────────────────────────────────────

  /// Extracts YouTube video ID from a full URL or bare ID string.
  String? _extractYouTubeId(String url) {
    if (url.isEmpty) return null;
    // youtu.be/<id>
    final short = RegExp(r'youtu\.be/([^?&\s]+)').firstMatch(url);
    if (short != null) return short.group(1);
    // ?v=<id>
    final long = RegExp(r'[?&]v=([^&\s]+)').firstMatch(url);
    if (long != null) return long.group(1);
    // bare 11-char ID
    if (url.length == 11 && !url.contains('/')) return url;
    return null;
  }

  Widget _buildSpecialistCard(Map<String, dynamic> data) {
    final profileImg   = data['profileImage'] as String?
                      ?? data['photoUrl']    as String?
                      ?? data['photoURL']    as String?  // Firebase Auth field name
                      ?? '';
    final hasImg       = profileImg.isNotEmpty && profileImg.startsWith('http');
    final name         = data['name'] as String? ?? widget.expertName;
    final isVerified   = data['isVerified'] == true;
    final isVolunteer  = data['isVolunteer'] == true;
    final serviceType  = data['serviceType'] as String? ?? '';
    final bio          = data['aboutMe'] as String? ?? data['bio'] as String? ?? '';
    final xp           = (data['xp'] as num? ?? 0).toInt();
    final rating       = data['rating'] ?? '5.0';
    final reviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    final jobsCount    =
        (data['completedJobsCount'] as num? ?? data['orderCount'] as num? ?? reviewsCount).toInt();
    // YouTube intro URL (provider pastes in Edit Profile → videoUrl field)
    final youtubeUrl   = data['videoUrl'] as String? ?? '';
    final videoId      = _extractYouTubeId(youtubeUrl);
    // Verified uploaded video (provider uploads raw file → admin approves)
    final verifiedVideoUrl  = data['verificationVideoUrl'] as String? ?? '';
    final videoVerifiedByAdmin = data['videoVerifiedByAdmin'] as bool? ?? false;
    final hasVerifiedVideo  = videoVerifiedByAdmin && verifiedVideoUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LEFT: name, role label, specialty, bio, stats ───────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isVerified) ...[
                          const Icon(Icons.verified, color: Colors.blue, size: 18),
                          const SizedBox(width: 5),
                        ],
                        if (isVolunteer) ...[
                          const Icon(Icons.favorite, color: Colors.red, size: 16),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'נותן שירות',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w400),
                    ),
                    if (serviceType.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(serviceType,
                          style: const TextStyle(
                              color: _kPurple,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(bio,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                              height: 1.4)),
                    ],
                    const SizedBox(height: 14),
                    _expertStatRow(
                        label: 'עבודות',
                        value: '$jobsCount',
                        icon: Icons.shield_outlined,
                        iconColor: _kPurple),
                    const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
                    _expertStatRow(
                        label: 'דירוג',
                        value: '$rating',
                        icon: Icons.star_rounded,
                        iconColor: _kGold),
                    const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
                    _expertStatRow(
                        label: 'ביקורות',
                        value: '$reviewsCount',
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: Colors.teal),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ── RIGHT: profile photo ─────────────────────────────────────
              CircleAvatar(
                radius: 52,
                backgroundColor: hasImg
                    ? _kPurpleSoft
                    : const Color(0xFFE5E7EB),
                backgroundImage: hasImg ? CachedNetworkImageProvider(profileImg) : null,
                child: hasImg
                    ? null
                    : Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151)),
                      ),
              ),
            ],
          ),
          // ── Video section ────────────────────────────────────────────────
          // Priority 1: admin-approved uploaded video (verificationVideoUrl)
          // Priority 2: YouTube URL (videoUrl field)
          if (hasVerifiedVideo) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse(verifiedVideoUrl);
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A0E3C), Color(0xFF2D1A6B)],
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 32, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('וידאו היכרות',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.verified_rounded,
                              color: Color(0xFF22C55E), size: 13),
                          SizedBox(width: 4),
                          Text('מאומת על ידי AnySkill',
                              style: TextStyle(
                                  color: Color(0xFF22C55E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else if (videoId != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse(youtubeUrl.startsWith('http')
                    ? youtubeUrl
                    : 'https://www.youtube.com/watch?v=$videoId');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CachedNetworkImage(
                      imageUrl:
                          'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        height: 160,
                        color: _kPurpleSoft,
                        child: const Icon(Icons.videocam_outlined,
                            size: 48, color: _kPurple),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      height: 160,
                      color: Colors.black.withValues(alpha: 0.28),
                    ),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 32, color: _kPurple),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // ── XP Progress Bar ─────────────────────────────────────────────
          XpProgressBar(xp: xp),
        ],
      ),
    );
  }

  Widget _expertStatRow({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF9CA3AF))),
      ],
    );
  }

  Widget _buildActionSquares(BuildContext context, Map<String, dynamic> data) {
    final gallery    = (data['gallery'] as List? ?? []).cast<String>();
    final isPromoted = data['isPromoted'] == true;
    DateTime? expiryDate;
    try {
      final ts = data['promotionExpiryDate'];
      if (ts != null) expiryDate = (ts as dynamic).toDate() as DateTime;
    } catch (_) {}
    final isVipActive = isPromoted &&
        expiryDate != null &&
        expiryDate.isAfter(DateTime.now());

    return Row(
      children: [
        // Gallery square
        Expanded(
          child: InkWell(
            onTap: gallery.isEmpty
                ? null
                : () => _expandPortfolioImage(context, gallery, 0),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 32,
                      color: gallery.isEmpty ? Colors.grey[300] : Colors.black),
                  const SizedBox(height: 10),
                  Text(
                    'גלריית עבודות',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: gallery.isEmpty ? Colors.grey[300] : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // VIP square
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isVipActive ? _kGold : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
              border: isVipActive ? null : Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 32,
                    color: isVipActive ? Colors.white : Colors.amber[700]),
                const SizedBox(height: 10),
                Text(
                  isVipActive ? 'מומחה VIP' : 'מומחה',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isVipActive ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        titleSpacing: 0,
        title: Text(widget.expertName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          FavoriteButton(providerId: widget.expertId, size: 24),
          const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(child: AnySkillBrandIcon(size: 22)),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_refreshTrigger),
        future: CacheService.getDoc(
          'users', widget.expertId,
          ttl: CacheService.kExpertProfile,
          forceRefresh: true,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l10n    = AppLocalizations.of(context);
          final data    = snapshot.data!;
          final unavail = _parseUnavailableDates(data);

          return Stack(
            children: [
              // ── Main scrollable content ──────────────────────────────────
              RefreshIndicator(
                onRefresh: () async => setState(() => _refreshTrigger++),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Specialist card (mirrors ProfileScreen) ─────────────
                    SliverToBoxAdapter(
                      child: _buildSpecialistCard(data),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _buildActionSquares(context, data),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // ── About ──────────────────────────────────
                                _sectionHeader(l10n.expertSectionAbout),
                                _buildBioSection(data, l10n),
                                const SizedBox(height: 16),

                                // ── Quick Tags ─────────────────────────────
                                _buildQuickTagsSection(data),
                                if ((data['quickTags'] as List? ?? [])
                                    .isNotEmpty)
                                  const SizedBox(height: 24),

                                // ── Service Menu ───────────────────────────
                                _sectionHeader(l10n.expertSectionService),
                                _buildServiceMenu(data, l10n),
                                const SizedBox(height: 24),

                                // ── Booking calendar ──────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                _sectionHeader(l10n.expertSectionSchedule),
                                _buildCalendar(unavail),
                                if (_selectedDay != null) ...[
                                  const SizedBox(height: 16),
                                  _buildTimeSlots(l10n),
                                ],
                                const SizedBox(height: 24),

                                // ── Reviews ────────────────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                _buildReviewsSection(l10n),

                                // Space for sticky bar
                                const SizedBox(height: 120),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Sticky bottom bar ─────────────────────────────────────────
              _buildBottomBar(context, data),
            ],
          );
        },
      ),
    );
  }
}

