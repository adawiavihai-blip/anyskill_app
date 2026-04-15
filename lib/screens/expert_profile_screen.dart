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
import '../utils/safe_image_provider.dart';
import '../constants.dart' show appVersion;
import '../widgets/price_list_widget.dart';
import '../widgets/category_specs_widget.dart';
import '../features/pet_stay/models/dog_profile.dart';
import '../features/pet_stay/models/pet_stay.dart';
import '../features/pet_stay/models/schedule_item.dart';
import '../features/pet_stay/services/pet_stay_service.dart';
import '../features/pet_stay/services/schedule_generator.dart';
import '../features/pet_stay/widgets/dog_picker_section.dart';

// Brand tokens
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);


class ExpertProfileScreen extends StatefulWidget {
  final String expertId;
  final String expertName;
  /// v10.5.0: When provided, the profile shows identity-specific rating,
  /// reviewsCount, and reviews from this listing only.
  final String? listingId;

  const ExpertProfileScreen({
    super.key,
    required this.expertId,
    required this.expertName,
    this.listingId,
  });

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

  /// Slots already booked for the selected day — grayed out in the time picker.
  Set<String> _bookedSlots = {};
  bool _loadingSlots = false;

  /// v2 service schema for the expert's category. Loaded once when the profile
  /// resolves. Used by the booking sheet to render booking requirements + show
  /// deposit / surcharge information.
  ServiceSchema _serviceSchema = ServiceSchema.empty();
  String _lastSchemaCategory = '';

  /// Customer-supplied answers to [ServiceSchema.bookingRequirements].
  /// Persisted to `jobs/{id}.bookingRequirementValues` on payment.
  final Map<String, dynamic> _bookingReqValues = {};

  /// Pet Stay Tracker (v13.0.0) — selected dog for pet-services bookings.
  /// Required when `_serviceSchema.walkTracking || dailyProof`.
  /// Snapshot is written to `jobs/{id}/petStay/data` inside the payment tx.
  DogProfile? _selectedDog;

  /// End date for multi-night boarding (pension). Defaults to start+1 at
  /// booking time. Irrelevant for dog-walker (single session).
  DateTime? _petStayEndDate;

  final List<String> _timeSlots = [
    "08:00", "09:00", "10:00", "11:00",
    "14:00", "15:00", "16:00", "17:00", "18:00", "19:00",
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
  }

  /// v10.5.0: Loads user doc + merges listing-specific fields when listingId
  /// is provided. This ensures rating/reviewsCount/aboutMe/gallery reflect
  /// the specific professional identity, not the global user aggregate.
  Future<Map<String, dynamic>> _loadProfileData() async {
    final userData = await CacheService.getDoc(
      'users', widget.expertId,
      ttl: CacheService.kExpertProfile,
      forceRefresh: true,
    );

    // If no listingId, return user data as-is (backward compat)
    if (widget.listingId == null) return userData;

    // Merge listing-specific fields over the user doc
    try {
      final listingSnap = await FirebaseFirestore.instance
          .collection('provider_listings')
          .doc(widget.listingId)
          .get();
      if (listingSnap.exists) {
        final listing = listingSnap.data() ?? {};
        // Override identity-specific fields from listing
        if (listing['rating'] != null) userData['rating'] = listing['rating'];
        if (listing['reviewsCount'] != null) userData['reviewsCount'] = listing['reviewsCount'];
        if (listing['aboutMe'] != null && (listing['aboutMe'] as String).isNotEmpty) {
          userData['aboutMe'] = listing['aboutMe'];
        }
        if (listing['gallery'] != null) userData['gallery'] = listing['gallery'];
        if (listing['pricePerHour'] != null) userData['pricePerHour'] = listing['pricePerHour'];
        if (listing['serviceType'] != null) userData['serviceType'] = listing['serviceType'];
        if (listing['quickTags'] != null) userData['quickTags'] = listing['quickTags'];
        if (listing['categoryDetails'] != null) userData['categoryDetails'] = listing['categoryDetails'];
        if (listing['priceList'] != null) userData['priceList'] = listing['priceList'];
        if (listing['cancellationPolicy'] != null) userData['cancellationPolicy'] = listing['cancellationPolicy'];
      }
    } catch (e) {
      debugPrint('[ExpertProfile] Listing merge error: $e');
    }

    // Load v2 schema for the expert's most-specific category. Stored on
    // state so the booking sheet can render booking requirements + show
    // deposit / surcharge banners. Cached by category name to avoid refetching.
    final categoryName = (userData['serviceType'] as String? ?? '').trim();
    if (categoryName.isNotEmpty && categoryName != _lastSchemaCategory) {
      try {
        final schema = await loadServiceSchemaFor(categoryName);
        if (mounted) {
          setState(() {
            _serviceSchema = schema;
            _lastSchemaCategory = categoryName;
          });
        }
      } catch (e) {
        debugPrint('[ExpertProfile] Schema load error: $e');
      }
    }

    return userData;
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

    // ── Anti-fraud: block self-booking ───────────────────────────────────
    final selfUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (selfUid == widget.expertId) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('לא ניתן להזמין שירות מעצמך'),
          backgroundColor: Color(0xFFEF4444),
        ));
      }
      return false;
    }

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
      // ── Atomic transaction ──────────────────────────────────────────
      // Fee, balance, slot check, and all writes happen inside a single
      // transaction — prevents double-spend and fee-change race conditions.
      final customerRef = firestore.collection('users').doc(currentUserId);

      // Slot pre-compute (key only — actual guard is inside transaction)
      DocumentReference? slotRef;
      final d = _selectedDay;
      final t = _selectedTimeSlot;
      if (d != null && t != null) {
        final slotKey =
            '${widget.expertId}_'
            '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}_'
            '${t.replaceAll(':', '').replaceAll(' ', '')}';
        slotRef = firestore.collection('bookingSlots').doc(slotKey);
      }

      final cancelDeadline = CancellationPolicyService.deadline(
        policy:          cancellationPolicy,
        appointmentDate: _selectedDay,
        timeSlot:        _selectedTimeSlot,
      );

      final jobRef = firestore.collection('jobs').doc();

      // Commission values — computed inside transaction, stored here for
      // the post-transaction system message.
      double commission = 0;
      double expertNetEarnings = 0;

      // Pet Stay Tracker — captured inside the tx, written via WriteBatch
      // AFTER the tx commits to avoid hitting Firestore's 500-op cap on
      // long pension stays (180 days × 5 items/day = 900 items > limit).
      String? petStayJobId;
      List<ScheduleItem> petStayScheduleItems = const [];

      await firestore.runTransaction((tx) async {
        // READ: admin fee settings (inside transaction = atomic)
        final adminSnap = await tx.get(adminSettingsRef);
        final feePercentage =
            ((adminSnap.data() ?? {})['feePercentage'] as num? ?? 0.10)
                .toDouble();
        commission = double.parse((totalPrice * feePercentage).toStringAsFixed(2));
        expertNetEarnings = double.parse((totalPrice - commission).toStringAsFixed(2));

        // READ: customer balance (inside transaction = atomic)
        final customerSnap = await tx.get(customerRef);
        final Map<String, dynamic> customerData = customerSnap.data() ?? {};
        final double currentBalance = (customerData['balance'] ?? 0.0).toDouble();

        // ── DEPOSIT-ONLY ESCROW MODE (v12.1.0) ──────────────────────────
        // When the schema defines a depositPercent > 0, the customer pays
        // ONLY that fraction at booking. The remainder is collected at
        // completion (BookingActions.markCompleted reads `remainingAmount`
        // and debits the customer at that point).
        //
        // Schemas without a deposit (most cases) keep the legacy behaviour:
        // paidAtBooking == totalPrice, remainingAmount == 0.
        final double depositAmount = _serviceSchema.depositPercent > 0
            ? double.parse(
                (totalPrice * _serviceSchema.depositPercent / 100)
                    .toStringAsFixed(2))
            : 0.0;
        final double paidAtBooking =
            depositAmount > 0 ? depositAmount : totalPrice;
        final double remainingAmount = double.parse(
            (totalPrice - paidAtBooking).toStringAsFixed(2));

        // The customer only needs enough balance to cover the deposit.
        if (currentBalance < paidAtBooking) throw msgInsufficientBalance;

        // READ: slot collision check (inside transaction = atomic)
        if (slotRef != null) {
          final slotSnap = await tx.get(slotRef);
          if (slotSnap.exists) throw kSlotConflict;
          tx.set(slotRef, {
            'expertId':  widget.expertId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // WRITE: job document
        tx.set(jobRef, {
          'jobId':               jobRef.id,
          'chatRoomId':          chatRoomId,
          'customerId':          currentUserId,
          'customerName':        customerData['name'] ?? '',
          'expertId':            widget.expertId,
          'expertName':          widget.expertName,
          'totalPaidByCustomer': paidAtBooking,
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
          // ── v2 schema additions ────────────────────────────────────────
          if (_bookingReqValues.isNotEmpty)
            'bookingRequirementValues': Map<String, dynamic>.from(_bookingReqValues),
          if (depositAmount > 0) ...{
            'depositAmount':    depositAmount,
            'depositPercent':   _serviceSchema.depositPercent,
            'paidAtBooking':    paidAtBooking,
            'remainingAmount':  remainingAmount,
            'depositPaidAt':    FieldValue.serverTimestamp(),
          },
          // Cached schema flags so the order card can branch without
          // re-fetching the category doc on every render.
          'expertServiceType': _lastSchemaCategory,
          if (_serviceSchema.walkTracking) 'flagWalkTracking': true,
          if (_serviceSchema.dailyProof) 'flagDailyProof': true,
          if (_serviceSchema.priceLocked) 'flagPriceLocked': true,
          if (_serviceSchema.requireVisualDiagnosis)
            'flagRequireVisualDiagnosis': true,
        });

        // WRITE: PetStay snapshot + schedule (Pet Stay Tracker v13.0.0).
        // Frozen copy of the dog profile + auto-generated daily checklist.
        // Same transaction = job + petStay + schedule items are atomic.
        if ((_serviceSchema.walkTracking || _serviceSchema.dailyProof) &&
            _selectedDog != null &&
            _selectedDay != null) {
          final isPension = _serviceSchema.dailyProof;
          final isDogWalker =
              _serviceSchema.walkTracking && !_serviceSchema.dailyProof;
          final endDate = isPension
              ? (_petStayEndDate ??
                  _selectedDay!.add(const Duration(days: 1)))
              : _selectedDay!;
          final petStay = PetStay.initial(
            dog: _selectedDog!,
            customerId: currentUserId,
            expertId: widget.expertId,
            startDate: _selectedDay!,
            endDate: endDate,
            isPension: isPension,
            isDogWalker: isDogWalker,
          );
          PetStayService.instance.writeInitialSnapshotInTransaction(
            tx: tx,
            jobId: jobRef.id,
            snapshot: petStay,
          );

          // Schedule items — only generated for pension (multi-day).
          // Dog-walker skips this since the walk session IS the activity.
          // CAPTURE to outer scope — written via WriteBatch AFTER the tx
          // to avoid Firestore's 500-op transaction limit on long stays.
          petStayJobId = jobRef.id;
          petStayScheduleItems = ScheduleGenerator.generate(
            dog: _selectedDog!,
            startDate: _selectedDay!,
            endDate: endDate,
            customerId: currentUserId,
            expertId: widget.expertId,
            isPension: isPension,
          );
        }

        // WRITE: deduct customer balance — ONLY the deposit (or full price
        // when no deposit is configured).
        tx.update(customerRef,
            {'balance': FieldValue.increment(-paidAtBooking)});

        // WRITE: platform commission
        tx.set(firestore.collection('platform_earnings').doc(), {
          'jobId':          jobRef.id,
          'amount':         commission,
          'sourceExpertId': widget.expertId,
          'timestamp':      FieldValue.serverTimestamp(),
          'status':         'pending_escrow',
        });

        // WRITE: wallet transaction log
        tx.set(firestore.collection('transactions').doc(), {
          'userId':    currentUserId,
          'amount':    -paidAtBooking,
          'title':     depositAmount > 0
              ? '$msgTransactionTitle (פיקדון)'
              : msgTransactionTitle,
          'timestamp': FieldValue.serverTimestamp(),
          'status':    'escrow',
        });
      });

      // Pet Stay schedule items — written via WriteBatch AFTER the main
      // booking transaction commits. Graceful degradation: any failure
      // here is logged but does NOT roll back the paid booking. Provider
      // will see an empty checklist (dog card still renders) and admin
      // can regenerate if needed.
      if (petStayJobId != null && petStayScheduleItems.isNotEmpty) {
        try {
          await PetStayService.instance.writeScheduleItemsBatched(
            jobId: petStayJobId!,
            items: petStayScheduleItems,
          );
        } catch (e) {
          debugPrint('[PetStay] schedule batch write failed: $e');
        }
      }

      // System chat message (non-critical; after transaction)
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

  // ── Demo booking: fake success + admin notification + audit trail ────────
  //
  // No real Firestore booking writes (no job doc, no wallet deduction, no
  // bookingSlot reservation). Instead:
  //   1. Read the customer's profile (name + image + phone) for the admin
  //      notification card.
  //   2. Create a `demo_bookings` doc — visible in the AdminDemoExpertsTab
  //      "Bookings" sub-tab.
  //   3. Log a demand signal to `activity_log` (admin Live Feed — existing).
  //   4. Notify EVERY admin user via in-app notification + (best-effort) FCM.
  //   5. Notify the CUSTOMER so they see the friendly "we'll update you"
  //      message in their notifications screen too.
  //
  // Returns true on success — the caller's StatefulBuilder then renders the
  // demo-aware success view (with the softer "we'll update you" wording).
  // All steps are wrapped in try/catch so a failed notification or audit
  // write never blocks the customer's UX.
  Future<bool> _handleDemoBooking(BuildContext context) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // ── 1. Read customer profile (best-effort) ───────────────────────────
    String customerName = 'לקוח';
    String customerImage = '';
    String customerPhone = '';
    try {
      final customerDoc = await db.collection('users').doc(uid).get();
      final cd = customerDoc.data() ?? {};
      customerName = cd['name'] as String? ?? 'לקוח';
      customerImage = cd['profileImage'] as String? ?? '';
      customerPhone = cd['phone'] as String? ?? '';
    } catch (_) {}

    // ── 2. Format the requested slot for the admin (if any) ──────────────
    final dateStr = _selectedDay != null
        ? '${_selectedDay!.day.toString().padLeft(2, '0')}/'
            '${_selectedDay!.month.toString().padLeft(2, '0')}/'
            '${_selectedDay!.year}'
        : '';
    final timeStr = _selectedTimeSlot ?? '';

    // ── 3. Compute the price the customer would have paid ───────────────
    double totalAmount = 0;
    try {
      final demoData = await db.collection('users').doc(widget.expertId).get();
      final dd = demoData.data() ?? {};
      totalAmount = (dd['pricePerHour'] as num? ?? 150).toDouble();
    } catch (_) {}

    // ── 4. Get demo expert category for the admin context ───────────────
    String demoCategory = '';
    try {
      final demoDoc = await db.collection('users').doc(widget.expertId).get();
      final dd = demoDoc.data() ?? {};
      final parent = dd['parentCategory'] as String? ?? '';
      final sub = dd['subCategoryName'] as String? ?? '';
      demoCategory = parent.isNotEmpty && sub.isNotEmpty
          ? '$parent › $sub'
          : (parent.isNotEmpty
              ? parent
              : (dd['serviceType'] as String? ?? ''));
    } catch (_) {}

    // ── 5. Write the demo_bookings doc — admin-visible record ────────────
    try {
      await db.collection('demo_bookings').add({
        'customerId': uid,
        'customerName': customerName,
        'customerImage': customerImage,
        'customerPhone': customerPhone,
        'demoExpertId': widget.expertId,
        'demoExpertName': widget.expertName,
        'demoExpertCategory': demoCategory,
        'selectedDate': dateStr,
        'selectedTime': timeStr,
        'totalAmount': totalAmount,
        'status': 'pending', // 'pending' | 'contacted'
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[demo_booking] Failed to write demo_bookings: $e');
    }

    // ── 6. Log to activity_log (existing admin Live Feed) ────────────────
    try {
      await db.collection('activity_log').add({
        'type': 'demo_booking_attempt',
        'expertId': widget.expertId,
        'expertName': widget.expertName,
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'priority': 'high',
        'title': '🔥 לקוח ניסה להזמין מומחה דמו',
        'detail':
            '$customerName רוצה להזמין את ${widget.expertName} ($demoCategory)',
        'expireAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      });
    } catch (_) {}

    // ── 7. Notify EVERY admin in the system ─────────────────────────────
    // Reads all users with isAdmin == true and writes one notification doc
    // per admin. This is the cheapest path that doesn't require a Cloud
    // Function (1-3 admin users in practice).
    try {
      final adminsSnap = await db
          .collection('users')
          .where('isAdmin', isEqualTo: true)
          .limit(10)
          .get();
      final batch = db.batch();
      for (final adminDoc in adminsSnap.docs) {
        final adminId = adminDoc.id;
        final notifRef = db.collection('notifications').doc();
        batch.set(notifRef, {
          'userId': adminId,
          'type': 'demo_booking_attempt',
          'title': '🔥 ניסיון הזמנה לפרופיל דמו',
          'body':
              '$customerName רוצה להזמין את ${widget.expertName}${dateStr.isNotEmpty ? " ל-$dateStr $timeStr" : ""}',
          'isRead': false,
          'priority': 'high',
          'data': {
            'demoExpertId': widget.expertId,
            'customerId': uid,
            'customerPhone': customerPhone,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (adminsSnap.docs.isNotEmpty) await batch.commit();
    } catch (e) {
      debugPrint('[demo_booking] Failed to notify admins: $e');
    }

    // ── 8. Notify the CUSTOMER (matches the friendly success message) ────
    try {
      await db.collection('notifications').add({
        'userId': uid,
        'type': 'demo_booking_received',
        'title': '⏳ הזמנתך התקבלה',
        'body':
            'הזמנת את ${widget.expertName}. אנחנו מעדכנים אותך כשנותן השירות פנוי.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    // The caller's StatefulBuilder switches to the shared success view.
    // No navigator.pop() here — decoupled from this Future chain.
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
            _selectedDay      = selectedDay;
            _focusedDay       = focusedDay;
            _selectedTimeSlot = null;
            _bookedSlots      = {};
          });
          _loadBookedSlots(selectedDay);
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

  /// Fetches already-booked slots for [day] from the bookingSlots collection.
  Future<void> _loadBookedSlots(DateTime day) async {
    setState(() => _loadingSlots = true);
    try {
      final datePrefix =
          '${widget.expertId}_'
          '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}_';
      // bookingSlots doc IDs follow the pattern: {expertId}_{YYYYMMDD}_{HHmm}
      // Query all slots for this expert + date.
      final snap = await FirebaseFirestore.instance
          .collection('bookingSlots')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: datePrefix)
          .where(FieldPath.documentId, isLessThan: '${datePrefix}z')
          .limit(20)
          .get();

      final booked = <String>{};
      for (final doc in snap.docs) {
        // Extract HHmm from doc ID → "HH:mm"
        final suffix = doc.id.replaceFirst(datePrefix, '');
        if (suffix.length == 4) {
          booked.add('${suffix.substring(0, 2)}:${suffix.substring(2)}');
        }
      }
      if (mounted) setState(() { _bookedSlots = booked; _loadingSlots = false; });
    } catch (e) {
      debugPrint('[Booking] Failed to load booked slots: $e');
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  /// Generates time slots from the provider's `workingHours` for [_selectedDay].
  /// Falls back to hardcoded [_timeSlots] if the provider hasn't set hours.
  List<String> _resolveTimeSlots(Map<String, dynamic> expertData) {
    final rawHours = expertData['workingHours'] as Map<String, dynamic>?;
    if (rawHours == null || rawHours.isEmpty || _selectedDay == null) {
      return _timeSlots; // legacy fallback
    }
    // DateTime.weekday: 1=Monday..7=Sunday. Our schema: 0=Sunday..6=Saturday.
    final dayIndex = _selectedDay!.weekday == 7 ? 0 : _selectedDay!.weekday;
    final dayEntry = rawHours['$dayIndex'] as Map<String, dynamic>?;
    if (dayEntry == null) return []; // provider doesn't work this day
    final from = dayEntry['from']?.toString() ?? '09:00';
    final to   = dayEntry['to']?.toString()   ?? '17:00';
    final fromHour = int.tryParse(from.split(':').first) ?? 9;
    final toHour   = int.tryParse(to.split(':').first)   ?? 17;
    return [
      for (int h = fromHour; h < toHour; h++)
        '${h.toString().padLeft(2, '0')}:00',
    ];
  }

  Widget _buildTimeSlots(AppLocalizations l10n, Map<String, dynamic> expertData) {
    final slots = _resolveTimeSlots(expertData);
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'הספק לא עובד ביום הזה',
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }
    // Reset selection if it's no longer in the available slots
    if (_selectedTimeSlot != null && !slots.contains(_selectedTimeSlot)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedTimeSlot = null);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_loadingSlots)
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple),
              ),
            Text(l10n.expertSelectTime,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot       = slots[index];
              final isBooked   = _bookedSlots.contains(slot);
              final isSelected = _selectedTimeSlot == slot;
              return GestureDetector(
                onTap: isBooked
                    ? null  // tapping a booked slot does nothing
                    : () => setState(() => _selectedTimeSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: isBooked
                        ? Colors.grey.shade200
                        : isSelected ? _kPurple : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isBooked
                            ? Colors.grey.shade300
                            : isSelected ? _kPurple : Colors.grey.shade300),
                    boxShadow: isSelected && !isBooked
                        ? [
                            BoxShadow(
                                color: _kPurple.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]
                        : [],
                  ),
                  child: Center(
                    child: isBooked
                        ? Text(slot,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.lineThrough))
                        : Text(slot,
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

  // ── Reviews: Airbnb-style state ─────────────────────────────────────────
  String _reviewSearchQuery = '';
  bool _reviewsExpanded = false;
  static const int _reviewsPageSize = 6;
  static const _kGold = Color(0xFFD4AF37);

  Widget _buildReviewsSection(AppLocalizations l10n) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isProvider = currentUid == widget.expertId;

    Query<Map<String, dynamic>> reviewsQuery;
    if (widget.listingId != null) {
      reviewsQuery = FirebaseFirestore.instance
          .collection('reviews')
          .where('listingId', isEqualTo: widget.listingId)
          .limit(100);
    } else {
      reviewsQuery = FirebaseFirestore.instance
          .collection('reviews')
          .where('expertId', isEqualTo: widget.expertId)
          .limit(100);
    }

    // Volunteer reviews stream: completed community_requests for this expert
    final volunteerStream = FirebaseFirestore.instance
        .collection('community_requests')
        .where('volunteerId', isEqualTo: widget.expertId)
        .where('status', isEqualTo: 'completed')
        .limit(50)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('reviews_$_refreshTrigger'),
      stream: reviewsQuery.snapshots(),
      builder: (context, reviewSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: volunteerStream,
          builder: (context, volSnap) {
        if (reviewSnap.hasError && volSnap.hasError) return const SizedBox.shrink();
        if (!reviewSnap.hasData && !volSnap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // ── Build unified review items list ──────────────────────────────
        // Each item is a Map with a `_isVolunteer` flag for styling.
        final items = <Map<String, dynamic>>[];

        // Paid reviews
        if (reviewSnap.hasData) {
          for (final doc in reviewSnap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>? ?? {};
            final published = d['isPublished'];
            if (published != null && published != true) continue;
            items.add({
              ...d,
              '_docId': doc.id,
              '_isVolunteer': false,
            });
          }
        }

        // Volunteer reviews (from community_requests)
        if (volSnap.hasData) {
          for (final doc in volSnap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>? ?? {};
            final review = d['volunteerReview'] as String? ?? '';
            if (review.isEmpty) continue; // no review text = skip
            final photoUrl = d['completionPhotoUrl'] as String? ?? '';
            items.add({
              'reviewerName': d['requesterName'] as String? ?? 'אנונימי',
              'reviewerId': d['requesterId'] as String?,
              'reviewerImage': d['requesterImage'] as String?,
              'comment': review,
              'rating': 5.0, // volunteer = 5-star by definition
              'timestamp': d['completedAt'],
              'createdAt': d['completedAt'],
              'providerResponse': null,
              'reviewPhotos': photoUrl.isNotEmpty ? [photoUrl] : null,
              'thankYouNote': d['thankYouNote'] as String?,
              '_docId': doc.id,
              '_isVolunteer': true,
            });
          }
        }

        // Sort all items by timestamp descending
        items.sort((a, b) {
          final aTs = (a['timestamp'] ?? a['createdAt']) as Timestamp?;
          final bTs = (b['timestamp'] ?? b['createdAt']) as Timestamp?;
          if (aTs == null || bTs == null) return 0;
          return bTs.compareTo(aTs);
        });

        // ── Compute aggregate ratings from ratingParams ──────────────────
        double avgOverall = 0, avgProfessional = 0, avgTiming = 0, avgComm = 0;
        int paramCount = 0;
        for (final item in items) {
          final params = item['ratingParams'] as Map<String, dynamic>?;
          if (params != null && params.isNotEmpty) {
            avgProfessional += (params['professional'] as num? ?? 0).toDouble();
            avgTiming       += (params['timing'] as num? ?? 0).toDouble();
            avgComm         += (params['communication'] as num? ?? 0).toDouble();
            paramCount++;
          }
          avgOverall += (item['rating'] as num? ?? item['overallRating'] as num? ?? 0).toDouble();
        }
        final total = items.length;
        if (total > 0) avgOverall /= total;
        if (paramCount > 0) {
          avgProfessional /= paramCount;
          avgTiming       /= paramCount;
          avgComm         /= paramCount;
        }

        // ── Search filter ─────────────────────────────────────────────────
        final filtered = _reviewSearchQuery.isEmpty
            ? items
            : items.where((item) {
                final comment = (item['comment'] ?? item['publicComment'] ?? '').toString().toLowerCase();
                final name = (item['reviewerName'] ?? '').toString().toLowerCase();
                final response = (item['providerResponse'] ?? '').toString().toLowerCase();
                final thankYou = (item['thankYouNote'] ?? '').toString().toLowerCase();
                final q = _reviewSearchQuery.toLowerCase();
                return comment.contains(q) || name.contains(q) ||
                       response.contains(q) || thankYou.contains(q);
              }).toList();

        // ── Pagination ────────────────────────────────────────────────────
        final visible = _reviewsExpanded
            ? filtered
            : filtered.take(_reviewsPageSize).toList();
        final hasMore = filtered.length > _reviewsPageSize && !_reviewsExpanded;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ══════════════════════════════════════════════════════════════
            // TRUST HEADER
            // ══════════════════════════════════════════════════════════════
            if (total > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '$total ביקורות',
                    style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280)),
                  ),
                  Row(
                    children: [
                      Text(
                        avgOverall.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, color: _kGold, size: 28),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (paramCount > 0) ...[
                _ratingBar('מקצועיות', avgProfessional),
                const SizedBox(height: 8),
                _ratingBar('עמידה בזמנים', avgTiming),
                const SizedBox(height: 8),
                _ratingBar('תקשורת', avgComm),
                const SizedBox(height: 16),
              ],

              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  textAlign: TextAlign.start,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'חפש בביקורות...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() {
                    _reviewSearchQuery = v;
                    _reviewsExpanded = false;
                  }),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(),
                  const Text('ביקורות',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
            ],

            // ══════════════════════════════════════════════════════════════
            // EMPTY / CARDS / SHOW ALL
            // ══════════════════════════════════════════════════════════════
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _reviewSearchQuery.isNotEmpty
                        ? 'לא נמצאו ביקורות עבור "$_reviewSearchQuery"'
                        : l10n.expertNoReviews,
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  ),
                ),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final useGrid = constraints.maxWidth >= 560;

                  if (useGrid) {
                    final rows = <Widget>[];
                    for (int i = 0; i < visible.length; i += 2) {
                      rows.add(IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildReviewCardFromMap(
                              visible[i], l10n, isProvider)),
                            const SizedBox(width: 12),
                            if (i + 1 < visible.length)
                              Expanded(child: _buildReviewCardFromMap(
                                visible[i + 1], l10n, isProvider))
                            else
                              const Expanded(child: SizedBox()),
                          ],
                        ),
                      ));
                      if (i + 2 < visible.length) {
                        rows.add(const SizedBox(height: 12));
                      }
                    }
                    return Column(children: rows);
                  }

                  return Column(
                    children: visible.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildReviewCardFromMap(item, l10n, isProvider),
                    )).toList(),
                  );
                },
              ),

              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => setState(() => _reviewsExpanded = true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1A2E),
                        side: const BorderSide(color: Color(0xFF1A1A2E)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'הצג את כל ${filtered.length} הביקורות',
                        style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
          },
        );
      },
    );
  }

  // ── Rating progress bar (Airbnb-style) ──────────────────────────────────
  Widget _ratingBar(String label, double value) {
    final fraction = (value / 5.0).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(value.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E))),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(_kGold),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ),
      ],
    );
  }

  // ── Single review card (Airbnb-style, volunteer-aware) ────────────────
  Widget _buildReviewCardFromMap(
    Map<String, dynamic> r,
    AppLocalizations l10n,
    bool isProvider,
  ) {
    final isVolunteer = r['_isVolunteer'] as bool? ?? false;
    final docId      = r['_docId'] as String? ?? '';
    final rating     = (r['rating'] as num? ?? r['overallRating'] as num? ?? 5).toDouble();
    final name       = r['reviewerName'] as String? ?? l10n.expertDefaultReviewer;
    final comment    = (r['comment'] ?? r['publicComment'] ?? '').toString().trim();
    final ts         = (r['timestamp'] ?? r['createdAt']) as Timestamp?;
    final date       = ts != null ? DateFormat('MMM yyyy').format(ts.toDate()) : '';
    final response   = r['providerResponse'] as String?;
    final reviewerImage = r['reviewerImage'] as String?;
    final reviewerId = r['reviewerId'] as String?;
    final thankYou   = r['thankYouNote'] as String?;
    final photos = (r['reviewPhotos'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .where((url) => url.isNotEmpty)
        .toList();

    final imgProvider = safeImageProvider(reviewerImage);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Volunteer cards get a light gold tint background
        color: isVolunteer
            ? const Color(0xFFFFFBEB) // warm gold tint
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isVolunteer
              ? _kGold.withValues(alpha: 0.3)
              : const Color(0xFFF3F4F6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Volunteer badge (if applicable) ──────────────────────────
          if (isVolunteer) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFB8860B)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, color: Colors.white, size: 11),
                  SizedBox(width: 3),
                  Text(
                    'התנדבות בקהילה',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Reviewer header ──────────────────────────────────────────
          Row(
            children: [
              // Left: stars + date
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) => Icon(
                      i < rating.round()
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: _kGold,
                      size: 14,
                    )),
                  ),
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(date,
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 11)),
                  ],
                ],
              ),
              const Spacer(),
              // Right: name (+ gold heart for volunteers) + avatar
              if (isVolunteer)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 4),
                  child: Icon(Icons.favorite_rounded, color: _kGold, size: 14),
                ),
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(width: 8),
              imgProvider != null
                  ? CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFE5E7EB),
                      backgroundImage: imgProvider,
                    )
                  : (reviewerId != null && reviewerId.isNotEmpty)
                      ? FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(reviewerId)
                              .get(),
                          builder: (_, snap) {
                            if (snap.hasData && snap.data!.exists) {
                              final userData = snap.data!.data()
                                  as Map<String, dynamic>? ?? {};
                              final fetchedImg = safeImageProvider(
                                  userData['profileImage'] as String?);
                              if (fetchedImg != null) {
                                return CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFE5E7EB),
                                  backgroundImage: fetchedImg,
                                );
                              }
                            }
                            return _initialsAvatar(name);
                          },
                        )
                      : _initialsAvatar(name),
            ],
          ),
          const SizedBox(height: 10),

          // ── Comment body ─────────────────────────────────────────────
          if (comment.isNotEmpty)
            Text(comment,
                textAlign: TextAlign.start,
                style: TextStyle(
                    fontSize: 13.5, height: 1.55, color: Colors.grey[700])),

          // ── Thank-you note (volunteer reviews) ───────────────────────
          if (isVolunteer && thankYou != null && thankYou.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote_rounded, size: 14, color: _kGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(thankYou,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[700])),
                  ),
                ],
              ),
            ),
          ],

          // ── Review photos gallery ────────────────────────────────────
          if (photos != null && photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => _showPhotoViewer(ctx, photos, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photos[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72, height: 72,
                        color: const Color(0xFFE5E7EB),
                        child: const Icon(Icons.broken_image_rounded,
                            color: Color(0xFF9CA3AF), size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ── Provider response (paid reviews only) ────────────────────
          if (!isVolunteer && response != null && response.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(l10n.expertProviderResponse,
                          style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Icon(Icons.subdirectory_arrow_left_rounded,
                          size: 14, color: Color(0xFF9CA3AF)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(response,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.5, color: Colors.grey[600])),
                ],
              ),
            ),
          ] else if (!isVolunteer && isProvider && docId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: _kPurple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2)),
                icon: const Icon(Icons.reply_rounded, size: 15),
                label: Text(l10n.expertAddReply,
                    style: const TextStyle(fontSize: 12)),
                onPressed: () =>
                    _showProviderReplyDialog(context, docId),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Initials-only fallback avatar for reviewers without a profile image.
  Widget _initialsAvatar(String name) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFE5E7EB),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF374151),
            fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Full-screen photo viewer overlay for review photos.
  void _showPhotoViewer(BuildContext context, List<String> photos, int initial) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _ReviewPhotoViewer(
        photos: photos,
        initialIndex: initial,
      ),
    ));
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
                  final replyErrorText = l10n.expertReplyError;
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
                        content: Text(replyErrorText),
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
    final isReady = _selectedDay != null && _selectedTimeSlot != null;
    final isSelf  = (FirebaseAuth.instance.currentUser?.uid ?? '') == widget.expertId;
    final canBook = isReady && !isSelf;

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
                        canBook ? () => _showBookingSummary(context, data, totalPrice, addOns: pricing.addOns, selectedAddOns: _selectedAddOnIndices) : null,
                    child: _isProcessing
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5)
                        : isSelf
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.block_rounded,
                                      color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('לא ניתן להזמין שירות מעצמך',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              )
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

    // Local copy of customer answers for booking requirements. Mutated by
    // BookingRequirementsForm; mirrored to _bookingReqValues on payment.
    final reqValues = Map<String, dynamic>.from(_bookingReqValues);

    // Pet Stay Tracker (v13.0.0): require a dog profile when the active
    // service has walk tracking or daily proof. Picker is rendered inline
    // in the sheet; payment button stays disabled until a dog is chosen.
    final bool isPetStayBooking =
        _serviceSchema.walkTracking || _serviceSchema.dailyProof;
    final bool isPensionBooking = _serviceSchema.dailyProof;
    DogProfile? selectedDog = _selectedDog;

    // End-date for pension — default to start+1. Re-read from state each
    // build so "edit" flows don't forget.
    DateTime? petStayEnd = _petStayEndDate ??
        (isPensionBooking && _selectedDay != null
            ? _selectedDay!.add(const Duration(days: 1))
            : null);

    // Number of nights (pension only). Mirrors petStayEnd - selectedDay.
    int nights = (isPensionBooking &&
            _selectedDay != null &&
            petStayEnd != null)
        ? petStayEnd.difference(_selectedDay!).inDays.clamp(1, 30)
        : 1;

    // Effective total price. For pension: per-night × nights. Else: as-is.
    double effectivePrice() =>
        (isPensionBooking ? price * nights : price).toDouble();

    // Returns true when every `required` booking requirement has a non-empty value.
    // Boarding (pension) skips validation — the form is hidden entirely.
    bool requirementsSatisfied() {
      if (isPensionBooking) return true;
      for (final r in _serviceSchema.bookingRequirements) {
        if (!r.required) continue;
        final v = reqValues[r.id];
        if (v == null) return false;
        if (v is String && v.trim().isEmpty) return false;
        if (v is num && v == 0) return false;
      }
      return true;
    }

    bool endDateOk() {
      if (!isPensionBooking) return true;
      if (_selectedDay == null || petStayEnd == null) return false;
      return !petStayEnd!.isBefore(_selectedDay!);
    }

    // Combined gate: requirements satisfied + (if pet stay) dog selected
    // + (if pension) valid end-date.
    bool canConfirm() =>
        requirementsSatisfied() &&
        (!isPetStayBooking || selectedDog != null) &&
        endDateOk();

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
            return _buildBookingSuccessView(sheetCtx, l10n, isDemo: isDemo);
          }

          // ── Booking summary form ──────────────────────────────────────────
          final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
          final screenH = MediaQuery.of(sheetCtx).size.height;
          return AbsorbPointer(
          absorbing: sheetBusy,
          child: Container(
        constraints: BoxConstraints(
          maxHeight: screenH * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
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
                  // ── Price Locked badge (home-services schemas) ────────────
                  if (_serviceSchema.priceLocked)
                    _summaryRow(
                      '🔒 מחיר נעול',
                      'מובטח אחרי אישור התמונות',
                      isGreen: true,
                    ),
                  // ── Deposit notice (high-ticket services) ─────────────────
                  if (_serviceSchema.depositPercent > 0)
                    _summaryRow(
                      'פיקדון מקדים',
                      '₪${(price * _serviceSchema.depositPercent / 100).toStringAsFixed(0)} '
                          '(${_serviceSchema.depositPercent.toStringAsFixed(0)}%)',
                    ),
                  if (isPensionBooking) ...[
                    _summaryRow('לילות', '$nights × ₪${price.toStringAsFixed(0)}'),
                  ],
                  const Divider(height: 16),
                  _summaryRow(l10n.expertSummaryRowTotal,
                      "₪${effectivePrice().toStringAsFixed(0)}",
                      isBold: true),
                ],
              ),
            ),
            // ── Pet Stay Tracker — nights stepper + end-date (pension only) ─
            if (isPensionBooking) ...[
              const SizedBox(height: 16),
              // Nights counter — primary control. Adjusts petStayEnd
              // automatically. Range 1-30 nights.
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.nights_stay_rounded,
                          color: Color(0xFF6366F1), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'מספר לילות',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    _NightStepperButton(
                      icon: Icons.remove_rounded,
                      onTap: nights > 1 && _selectedDay != null
                          ? () {
                              setSheetState(() {
                                nights -= 1;
                                petStayEnd = _selectedDay!
                                    .add(Duration(days: nights));
                                _petStayEndDate = petStayEnd;
                              });
                            }
                          : null,
                    ),
                    Container(
                      width: 44,
                      alignment: Alignment.center,
                      child: Text(
                        '$nights',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    _NightStepperButton(
                      icon: Icons.add_rounded,
                      onTap: nights < 30 && _selectedDay != null
                          ? () {
                              setSheetState(() {
                                nights += 1;
                                petStayEnd = _selectedDay!
                                    .add(Duration(days: nights));
                                _petStayEndDate = petStayEnd;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final firstAllowed =
                      _selectedDay ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        petStayEnd ?? firstAllowed.add(const Duration(days: 1)),
                    firstDate: firstAllowed,
                    lastDate:
                        firstAllowed.add(const Duration(days: 180)),
                  );
                  if (picked != null) {
                    setSheetState(() {
                      petStayEnd = picked;
                      _petStayEndDate = picked;
                      nights = picked
                          .difference(_selectedDay ?? picked)
                          .inDays
                          .clamp(1, 30);
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: endDateOk()
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.date_range_rounded,
                            color: Color(0xFF6366F1), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'תאריך סיום השהות',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              petStayEnd == null
                                  ? 'יש לבחור תאריך'
                                  : '${petStayEnd!.day}/${petStayEnd!.month}/${petStayEnd!.year}'
                                      ' · ${_selectedDay != null ? petStayEnd!.difference(_selectedDay!).inDays : 0} לילות',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left_rounded,
                          color: Color(0xFF9CA3AF)),
                    ],
                  ),
                ),
              ),
            ],
            // ── Pet Stay Tracker — dog picker (gated by schema flags) ─────
            if (isPetStayBooking) ...[
              const SizedBox(height: 16),
              DogPickerSection(
                selected: selectedDog,
                onChanged: (d) => setSheetState(() => selectedDog = d),
              ),
            ],
            // ── Booking requirements (contextual customer inputs) ─────────
            // Hidden for Home Boarding (pension) — the dog profile + nights
            // count + end date are the full picture; no extra description
            // is needed (per Home Boarding spec §2).
            if (!isPensionBooking &&
                _serviceSchema.bookingRequirements.isNotEmpty) ...[
              const SizedBox(height: 16),
              BookingRequirementsForm(
                requirements: _serviceSchema.bookingRequirements,
                initialValues: reqValues,
                onChanged: (vals) => setSheetState(() {
                  reqValues
                    ..clear()
                    ..addAll(vals);
                }),
              ),
            ],
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
                              penaltyPct.toString())
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
            // Validation hint when required booking info is missing.
            if (!requirementsSatisfied()) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 16, color: Color(0xFF92400E)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'יש למלא את כל השדות הנדרשים למעלה כדי להמשיך',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (sheetBusy || !canConfirm())
                          ? Colors.grey
                          : _kPurple,
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
              onPressed: (sheetBusy || !canConfirm())
                  ? null
                  : () async {
                      setSheetState(() => sheetBusy = true);
                      // Mirror customer answers + selected dog to state so
                      // the escrow transaction can persist them.
                      _bookingReqValues
                        ..clear()
                        ..addAll(reqValues);
                      _selectedDog = selectedDog;
                      final ok = await _processEscrowPayment(
                          context, effectivePrice(), policy, isDemo: isDemo);
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
              'AnySkill v$appVersion',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
        ),   // closes SingleChildScrollView
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
  //
  // Demo path (isDemo = true): the Firestore booking transaction is bypassed
  // entirely. We still render this success view so the customer believes the
  // booking went through. The wording is intentionally softer ("we'll update
  // you when the provider is available") to set expectations without revealing
  // that the profile is fake.
  Widget _buildBookingSuccessView(
    BuildContext ctx,
    AppLocalizations l10n, {
    bool isDemo = false,
  }) {
    final accentColor = isDemo
        ? const Color(0xFF6366F1) // indigo for demo
        : const Color(0xFF22C55E); // green for real bookings

    final title = isDemo
        ? 'ההזמנה התקבלה!'
        : 'ההזמנה בוצעה בהצלחה! 🎉';

    final subtitle = isDemo
        ? 'הזמנת את השירות. אנחנו כבר מעדכנים אותך אם נותן השירות פנוי.\n'
            'תקבל הודעה ברגע שיש תשובה.'
        : l10n.expertEscrowSuccess;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Animated icon circle ─────────────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDemo ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                color: accentColor,
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // ── Title ────────────────────────────────────────────────────────
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1B4B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (isDemo) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: Color(0xFF6366F1), size: 16),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'נשלח לך עדכון בקרוב',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 36),
          // ── Done button — only place pop() is called ─────────────────────
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'הבנתי ✓',
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
    final imgProvider  = safeImageProvider(profileImg);
    final name         = data['name'] as String? ?? widget.expertName;
    final isVerified   = data['isVerified'] == true;
    final isVolunteer  = data['isVolunteer'] == true || data['volunteerHeart'] == true;
    final serviceType  = data['serviceType'] as String? ?? '';
    final bio          = data['aboutMe'] as String? ?? data['bio'] as String? ?? '';
    final xp           = (data['xp'] as num? ?? 0).toInt();
    final rating       = data['rating'] ?? '5.0';
    final reviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    final jobsCount    =
        (data['completedJobsCount'] as num? ?? data['orderCount'] as num? ?? reviewsCount).toInt();
    // Video variables moved to _buildActionSquares (video card lives there now).

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
                          maxLines: 4,
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
                    // ── Volunteer counter (real-time stream) ──────
                    StreamBuilder<QuerySnapshot>(
                      stream: _volunteerCountStream(widget.expertId),
                      builder: (_, snap) {
                        final count = snap.hasData ? snap.data!.size : 0;
                        return Column(
                          children: [
                            const Divider(
                                height: 20,
                                color: Color(0xFFF3F4F6),
                                thickness: 1),
                            _expertStatRow(
                                label: 'התנדבויות בקהילה',
                                value: '$count',
                                icon: Icons.favorite_rounded,
                                iconColor: const Color(0xFFD4AF37)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ── RIGHT: profile photo + volunteer heart overlay ──────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: imgProvider != null
                        ? _kPurpleSoft
                        : const Color(0xFFE5E7EB),
                    backgroundImage: imgProvider,
                    child: imgProvider != null
                        ? null
                        : Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151)),
                      ),
                  ),
                  // ── Golden heart overlay for volunteers ──────────────────
                  if (isVolunteer)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite_rounded,
                            color: Color(0xFFD4AF37), size: 18),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Video section removed — video is now accessed via the action
          // squares below (Video + Gallery side-by-side).

          // ── XP Progress Bar (owner only) ────────────────────────────────
          if ((FirebaseAuth.instance.currentUser?.uid ?? '') == widget.expertId) ...[
            const SizedBox(height: 16),
            XpProgressBar(xp: xp),
          ],
        ],
      ),
    );
  }

  /// Real-time stream of completed community tasks where this expert volunteered.
  Stream<QuerySnapshot> _volunteerCountStream(String expertId) {
    return FirebaseFirestore.instance
        .collection('community_requests')
        .where('volunteerId', isEqualTo: expertId)
        .where('status', isEqualTo: 'completed')
        .limit(100)
        .snapshots();
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
    final gallery = (data['gallery'] as List? ?? []).cast<String>();

    // Video data
    final verifiedVideoUrl     = data['verificationVideoUrl'] as String? ?? '';
    final videoVerifiedByAdmin = data['videoVerifiedByAdmin'] as bool? ?? false;
    final hasVerifiedVideo     = videoVerifiedByAdmin && verifiedVideoUrl.isNotEmpty;
    final youtubeUrl           = data['videoUrl'] as String? ?? '';
    final videoId              = _extractYouTubeId(youtubeUrl);
    final hasAnyVideo          = hasVerifiedVideo || videoId != null;

    return Row(
      children: [
        // ── Video Introduction square ──────────────────────────────────
        Expanded(
          child: InkWell(
            onTap: hasAnyVideo
                ? () async {
                    final url = hasVerifiedVideo
                        ? verifiedVideoUrl
                        : (youtubeUrl.startsWith('http')
                            ? youtubeUrl
                            : 'https://www.youtube.com/watch?v=$videoId');
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  }
                : null,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      size: 32,
                      color: hasAnyVideo ? _kPurple : Colors.grey[300]),
                  const SizedBox(height: 10),
                  Text(
                    'וידאו היכרות',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasAnyVideo ? Colors.black : Colors.grey[300]!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // ── Work Gallery square ────────────────────────────────────────
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
        future: _loadProfileData(),
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

                                // ── Price List (category-specific) ────────
                                if (hasPriceList(data) &&
                                    (data['priceList'] as Map?)?.isNotEmpty == true)
                                  PriceListDisplay(
                                    priceList: Map<String, dynamic>.from(
                                        data['priceList'] as Map),
                                    userData: data,
                                    onSendQuote: (msg) => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                                receiverId: widget.expertId,
                                                receiverName: widget.expertName,
                                                initialMessage: msg))),
                                  ),
                                if (hasPriceList(data) &&
                                    (data['priceList'] as Map?)?.isNotEmpty == true)
                                  const SizedBox(height: 24),

                                // ── Booking calendar ──────────────────────
                                const Divider(height: 1),
                                const SizedBox(height: 24),
                                _sectionHeader(l10n.expertSectionSchedule),
                                _buildCalendar(unavail),
                                if (_selectedDay != null) ...[
                                  const SizedBox(height: 16),
                                  _buildTimeSlots(l10n, data),
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

// ═══════════════════════════════════════════════════════════════════════════
// Booking sheet — night stepper button (used by the multi-night pension picker)
// ═══════════════════════════════════════════════════════════════════════════

class _NightStepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NightStepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color:
                enabled ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Full-screen photo viewer for review photos (pinch-to-zoom + swipe)
// ═══════════════════════════════════════════════════════════════════════════

class _ReviewPhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;

  const _ReviewPhotoViewer({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_ReviewPhotoViewer> createState() => _ReviewPhotoViewerState();
}

class _ReviewPhotoViewerState extends State<_ReviewPhotoViewer> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Dismiss on background tap ──────────────────────────────
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.transparent),
          ),

          // ── Zoomable photo pages ──────────────────────────────────
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.photos[i],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Close button ──────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
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

          // ── Page indicator ────────────────────────────────────────
          if (widget.photos.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.photos.length, (i) =>
                  Container(
                    width: i == _current ? 20 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _current ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

