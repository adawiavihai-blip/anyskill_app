import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../features/pet_stay/models/dog_profile.dart';
import '../features/pet_stay/models/pet_stay.dart';
import '../features/pet_stay/models/schedule_item.dart';
import '../features/pet_stay/services/pet_stay_service.dart';
import '../features/pet_stay/services/schedule_generator.dart';
import '../models/fitness_trainer_profile.dart'; // PricingPackage
import '../models/handyman_profile.dart'; // HandymanBookingPreferences
import '../models/motorcycle_tow_profile.dart'; // MotorcycleTowBookingPreferences
import '../screens/babysitter/babysitter_booking_block.dart'; // BabysitterBookingPreferences
import '../screens/cleaning/cleaning_booking_block.dart'; // CleaningBookingPreferences
import '../screens/delivery/delivery_booking_block.dart'; // DeliveryBookingPreferences
import '../screens/massage/build_your_treatment_block.dart'; // MassageBookingPreferences
import '../screens/pest_control/pest_booking_block.dart'; // PestControlBookingPreferences
import '../widgets/category_specs_widget.dart' show ServiceSchema;
import 'cancellation_policy_service.dart';

/// Sentinel string thrown inside the Firestore transaction when the
/// chosen booking slot is already taken. Caller maps this to a custom
/// UI dialog (see expert_profile_screen.dart `_processEscrowPayment`
/// catch block).
const String kBookingSlotConflict = '__SLOT_CONFLICT__';

/// Sentinel string thrown when the customer balance is below the
/// required deposit (or full price for non-deposit bookings). Caller
/// shows a Hebrew "insufficient balance" snackbar with the original
/// l10n-formatted message that was supplied in `BookingRequest`.
const String kBookingInsufficientBalance = '__INSUFFICIENT_BALANCE__';

/// Bundles all the state needed to execute an escrow booking.
///
/// Extracted from `_ExpertProfileScreenState._processEscrowPayment` in
/// §81 (2026-05-14). Pure parameter object — no callbacks, no `setState`
/// concerns. The screen builds this from its state fields and passes it
/// to [ExpertBookingService.processEscrow] which returns a
/// [BookingOutcome] the screen translates back to UI updates.
@immutable
class BookingRequest {
  const BookingRequest({
    required this.customerId,
    required this.customerName,
    required this.expertId,
    required this.expertName,
    required this.totalPrice,
    required this.cancellationPolicy,
    required this.selectedDay,
    required this.selectedTimeSlot,
    required this.serviceSchema,
    required this.lastSchemaCategory,
    required this.bookingReqValues,
    required this.transactionTitle,
    required this.systemMessage,
    this.massagePreferences,
    this.massageTotalPrice = 0,
    this.pestControlPreferences,
    this.pestControlTotalPrice = 0,
    this.deliveryPreferences,
    this.deliveryTotalPrice = 0,
    this.cleaningPreferences,
    this.cleaningTotalPrice = 0,
    this.handymanPreferences,
    this.handymanTotalPrice = 0,
    this.fitnessPackage,
    this.fitnessTotalPrice = 0,
    this.babysitterPreferences,
    this.babysitterTotalPrice = 0,
    this.motorcycleTowPreferences,
    this.motorcycleTowTotalPrice = 0,
    this.selectedDog,
    this.petStayEndDate,
  });

  final String customerId;
  final String customerName;
  final String expertId;
  final String expertName;
  final double totalPrice;
  final String cancellationPolicy;
  final DateTime selectedDay;
  final String selectedTimeSlot;
  final ServiceSchema serviceSchema;
  final String lastSchemaCategory;
  final Map<String, dynamic> bookingReqValues;
  final String transactionTitle;
  final String systemMessage;

  // CSM preferences — only one is non-null per booking in practice.
  final MassageBookingPreferences? massagePreferences;
  final double massageTotalPrice;
  final PestControlBookingPreferences? pestControlPreferences;
  final double pestControlTotalPrice;
  final DeliveryBookingPreferences? deliveryPreferences;
  final double deliveryTotalPrice;
  final CleaningBookingPreferences? cleaningPreferences;
  final double cleaningTotalPrice;
  final HandymanBookingPreferences? handymanPreferences;
  final double handymanTotalPrice;
  final PricingPackage? fitnessPackage;
  final double fitnessTotalPrice;
  final BabysitterBookingPreferences? babysitterPreferences;
  final double babysitterTotalPrice;
  final MotorcycleTowBookingPreferences? motorcycleTowPreferences;
  final double motorcycleTowTotalPrice;

  // Pet stay (multi-night boarding / dog walker)
  final DogProfile? selectedDog;
  final DateTime? petStayEndDate;
}

/// Result of an escrow booking attempt. Sealed-style — exactly one of:
///   • [success]            — booking committed; UI can switch to success view.
///   • [insufficientBalance]— customer wallet < required deposit/total.
///   • [slotConflict]       — another customer grabbed the slot mid-flight.
///   • [error]              — anything else (Firestore down, etc.).
@immutable
class BookingOutcome {
  const BookingOutcome._(this.kind, {this.jobId, this.chatRoomId, this.errorMessage});

  factory BookingOutcome.success(String jobId, String chatRoomId) =>
      BookingOutcome._(BookingOutcomeKind.success,
          jobId: jobId, chatRoomId: chatRoomId);
  factory BookingOutcome.insufficientBalance() =>
      const BookingOutcome._(BookingOutcomeKind.insufficientBalance);
  factory BookingOutcome.slotConflict() =>
      const BookingOutcome._(BookingOutcomeKind.slotConflict);
  factory BookingOutcome.error(String message) =>
      BookingOutcome._(BookingOutcomeKind.error, errorMessage: message);

  final BookingOutcomeKind kind;
  final String? jobId;
  final String? chatRoomId;
  final String? errorMessage;

  bool get isSuccess => kind == BookingOutcomeKind.success;
}

enum BookingOutcomeKind {
  success,
  insufficientBalance,
  slotConflict,
  error,
}

/// Pure business-logic service for expert bookings.
///
/// Extracted from `_ExpertProfileScreenState` in §81. No UI dependencies,
/// no `BuildContext`, no `setState`. The screen owns:
///   • Profile completeness check (ProfileGuard)
///   • Self-booking block
///   • `_isProcessing` flag toggling
///   • Snackbar / dialog rendering based on the returned [BookingOutcome]
///   • Pet stay schedule items written via WriteBatch AFTER the main tx
///     (see [processEscrow]'s return value — caller passes the schedule
///     items to [writePetStayScheduleBatched])
///   • System chat message (see [sendSystemMessage])
///
/// This service holds the SHAPE OF THE MONEY contract:
///   1. Read admin fee + customer balance inside the tx
///   2. Compute deposit + remaining
///   3. Check balance; throw [kBookingInsufficientBalance] if short
///   4. Check slot collision; throw [kBookingSlotConflict] if taken
///   5. Atomic writes: job + platform_earnings + transactions + slot
///      + (optional) pet stay snapshot
///   6. Outside tx (best-effort): write pet stay schedule + system chat msg
class ExpertBookingService {
  ExpertBookingService._();

  /// Runs the atomic escrow booking transaction.
  ///
  /// Returns [BookingOutcome.success] with the new jobId on success.
  /// On failure returns one of the other [BookingOutcome] variants —
  /// the UI maps the outcome to the right snackbar/dialog.
  ///
  /// IMPORTANT: pet stay schedule items are captured during the tx but
  /// written via [writePetStayScheduleBatched] AFTER tx commit, because
  /// long pension stays (180 days × 5 items = 900 items) blow past
  /// Firestore's 500-op transaction limit.
  static Future<BookingOutcome> processEscrow(BookingRequest req) async {
    final firestore = FirebaseFirestore.instance;
    final customerRef = firestore.collection('users').doc(req.customerId);
    final adminSettingsRef = firestore
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    // Build chat room id (deterministic sort-then-join).
    final ids = [req.customerId, req.expertId]..sort();
    final chatRoomId = ids.join('_');

    // Slot key (matches the legacy format exactly).
    final slotKey = '${req.expertId}_'
        '${req.selectedDay.year}'
        '${req.selectedDay.month.toString().padLeft(2, '0')}'
        '${req.selectedDay.day.toString().padLeft(2, '0')}_'
        '${req.selectedTimeSlot.replaceAll(':', '').replaceAll(' ', '')}';
    final slotRef = firestore.collection('bookingSlots').doc(slotKey);

    final cancelDeadline = CancellationPolicyService.deadline(
      policy: req.cancellationPolicy,
      appointmentDate: req.selectedDay,
      timeSlot: req.selectedTimeSlot,
    );

    final jobRef = firestore.collection('jobs').doc();

    // Pet Stay capture (written AFTER tx commits — see writePetStayScheduleBatched).
    String? petStayJobIdCaptured;
    List<ScheduleItem> petStaySchedule = const [];

    try {
      await firestore.runTransaction((tx) async {
        // READ: admin fee
        final adminSnap = await tx.get(adminSettingsRef);
        final feePercentage =
            ((adminSnap.data() ?? {})['feePercentage'] as num? ?? 0.10)
                .toDouble();
        final commission = double.parse(
            (req.totalPrice * feePercentage).toStringAsFixed(2));
        final expertNet =
            double.parse((req.totalPrice - commission).toStringAsFixed(2));

        // READ: customer balance
        final customerSnap = await tx.get(customerRef);
        final customerData = customerSnap.data() ?? {};
        final currentBalance =
            (customerData['balance'] ?? 0.0).toDouble();

        // Deposit math (v12.1.0 §3c)
        final depositAmount = req.serviceSchema.depositPercent > 0
            ? double.parse(
                (req.totalPrice *
                        req.serviceSchema.depositPercent /
                        100)
                    .toStringAsFixed(2))
            : 0.0;
        final paidAtBooking =
            depositAmount > 0 ? depositAmount : req.totalPrice;
        final remainingAmount = double.parse(
            (req.totalPrice - paidAtBooking).toStringAsFixed(2));

        if (currentBalance < paidAtBooking) {
          throw kBookingInsufficientBalance;
        }

        // READ + WRITE: slot collision check
        final slotSnap = await tx.get(slotRef);
        if (slotSnap.exists) {
          throw kBookingSlotConflict;
        }
        tx.set(slotRef, {
          'expertId': req.expertId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // WRITE: job document with all CSM preferences
        tx.set(jobRef, _buildJobPayload(
          req: req,
          jobId: jobRef.id,
          chatRoomId: chatRoomId,
          customerData: customerData,
          totalPrice: req.totalPrice,
          paidAtBooking: paidAtBooking,
          depositAmount: depositAmount,
          remainingAmount: remainingAmount,
          commission: commission,
          expertNet: expertNet,
          cancelDeadline: cancelDeadline,
        ));

        // Pet Stay snapshot (frozen copy + schedule generation)
        if ((req.serviceSchema.walkTracking ||
                req.serviceSchema.dailyProof) &&
            req.selectedDog != null) {
          final isPension = req.serviceSchema.dailyProof;
          final isDogWalker =
              req.serviceSchema.walkTracking && !req.serviceSchema.dailyProof;
          final endDate = isPension
              ? (req.petStayEndDate ??
                  req.selectedDay.add(const Duration(days: 1)))
              : req.selectedDay;
          final petStay = PetStay.initial(
            dog: req.selectedDog!,
            customerId: req.customerId,
            expertId: req.expertId,
            startDate: req.selectedDay,
            endDate: endDate,
            isPension: isPension,
            isDogWalker: isDogWalker,
          );
          PetStayService.instance.writeInitialSnapshotInTransaction(
            tx: tx,
            jobId: jobRef.id,
            snapshot: petStay,
          );
          petStayJobIdCaptured = jobRef.id;
          petStaySchedule = ScheduleGenerator.generate(
            dog: req.selectedDog!,
            startDate: req.selectedDay,
            endDate: endDate,
            customerId: req.customerId,
            expertId: req.expertId,
            isPension: isPension,
          );
        }

        // WRITE: decrement customer balance (deposit only, or full)
        tx.update(customerRef,
            {'balance': FieldValue.increment(-paidAtBooking)});

        // WRITE: platform commission record
        tx.set(firestore.collection('platform_earnings').doc(), {
          'jobId': jobRef.id,
          'amount': commission,
          'sourceExpertId': req.expertId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending_escrow',
        });

        // WRITE: wallet transaction log
        tx.set(firestore.collection('transactions').doc(), {
          'userId': req.customerId,
          'amount': -paidAtBooking,
          'title': depositAmount > 0
              ? '${req.transactionTitle} (פיקדון)'
              : req.transactionTitle,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'escrow',
        });
      });
    } on String catch (sentinel) {
      if (sentinel == kBookingInsufficientBalance) {
        return BookingOutcome.insufficientBalance();
      }
      if (sentinel == kBookingSlotConflict) {
        return BookingOutcome.slotConflict();
      }
      return BookingOutcome.error(sentinel);
    } catch (e) {
      debugPrint('[ExpertBookingService] Booking error: $e');
      return BookingOutcome.error(e.toString());
    }

    // Best-effort: write pet stay schedule items via WriteBatch.
    // Failure here does NOT roll back the booking — provider sees an
    // empty checklist and admin can regenerate.
    if (petStayJobIdCaptured != null && petStaySchedule.isNotEmpty) {
      try {
        await PetStayService.instance.writeScheduleItemsBatched(
          jobId: petStayJobIdCaptured!,
          items: petStaySchedule,
        );
      } catch (e) {
        debugPrint('[PetStay] schedule batch write failed: $e');
      }
    }

    return BookingOutcome.success(jobRef.id, chatRoomId);
  }

  /// Sends the post-booking system chat message ("₪X locked in escrow,
  /// work can begin!"). Best-effort — failure logged but doesn't fail
  /// the booking. Called by the screen AFTER [processEscrow] succeeds.
  static Future<void> sendSystemMessage({
    required String chatRoomId,
    required String customerId,
    required String expertId,
    required String message,
  }) async {
    final chatRef =
        FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
    // Ensure chat doc exists with both participants (rules check this).
    await chatRef.set(
      {'users': [customerId, expertId]},
      SetOptions(merge: true),
    );
    await chatRef.collection('messages').add({
      'senderId': 'system',
      'message': message,
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Demo booking flow — no real escrow, just logs the demand signal +
  /// notifies admins + writes a `demo_bookings` record.
  ///
  /// Returns `true` on success (caller switches to demo-aware success
  /// view). All steps are wrapped in try/catch so partial failures don't
  /// break the UX.
  static Future<bool> handleDemoBooking({
    required String customerId,
    required String expertId,
    required String expertName,
    required DateTime? selectedDay,
    required String? selectedTimeSlot,
    required String defaultCustomerName,
    required String customerNotificationBody,
  }) async {
    final db = FirebaseFirestore.instance;

    // 1. Read customer profile (best-effort)
    String customerName = defaultCustomerName;
    String customerImage = '';
    String customerPhone = '';
    try {
      final doc = await db.collection('users').doc(customerId).get();
      final cd = doc.data() ?? {};
      customerName = cd['name'] as String? ?? defaultCustomerName;
      customerImage = cd['profileImage'] as String? ?? '';
      customerPhone = cd['phone'] as String? ?? '';
    } catch (_) {}

    // 2. Format slot
    final dateStr = selectedDay != null
        ? '${selectedDay.day.toString().padLeft(2, '0')}/'
            '${selectedDay.month.toString().padLeft(2, '0')}/'
            '${selectedDay.year}'
        : '';
    final timeStr = selectedTimeSlot ?? '';

    // 3. Demo expert price + category
    double totalAmount = 0;
    String demoCategory = '';
    try {
      final demoDoc = await db.collection('users').doc(expertId).get();
      final dd = demoDoc.data() ?? {};
      totalAmount = (dd['pricePerHour'] as num? ?? 150).toDouble();
      final parent = dd['parentCategory'] as String? ?? '';
      final sub = dd['subCategoryName'] as String? ?? '';
      demoCategory = parent.isNotEmpty && sub.isNotEmpty
          ? '$parent › $sub'
          : (parent.isNotEmpty
              ? parent
              : (dd['serviceType'] as String? ?? ''));
    } catch (_) {}

    // 4. demo_bookings record
    try {
      await db.collection('demo_bookings').add({
        'customerId': customerId,
        'customerName': customerName,
        'customerImage': customerImage,
        'customerPhone': customerPhone,
        'demoExpertId': expertId,
        'demoExpertName': expertName,
        'demoExpertCategory': demoCategory,
        'selectedDate': dateStr,
        'selectedTime': timeStr,
        'totalAmount': totalAmount,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[demo_booking] write failed: $e');
    }

    // 5. activity_log entry
    try {
      await db.collection('activity_log').add({
        'type': 'demo_booking_attempt',
        'expertId': expertId,
        'expertName': expertName,
        'userId': customerId,
        'createdAt': FieldValue.serverTimestamp(),
        'priority': 'high',
        'title': '🔥 לקוח ניסה להזמין נותן שירות דמו',
        'detail':
            '$customerName רוצה להזמין את $expertName ($demoCategory)',
        'expireAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      });
    } catch (_) {}

    // 6. Fan-out admin notifications (max 10)
    try {
      final adminsSnap = await db
          .collection('users')
          .where('isAdmin', isEqualTo: true)
          .limit(10)
          .get();
      final batch = db.batch();
      for (final adminDoc in adminsSnap.docs) {
        batch.set(db.collection('notifications').doc(), {
          'userId': adminDoc.id,
          'type': 'demo_booking_attempt',
          'title': '🔥 ניסיון הזמנה לפרופיל דמו',
          'body':
              '$customerName רוצה להזמין את $expertName${dateStr.isNotEmpty ? " ל-$dateStr $timeStr" : ""}',
          'isRead': false,
          'priority': 'high',
          'data': {
            'demoExpertId': expertId,
            'customerId': customerId,
            'customerPhone': customerPhone,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (adminsSnap.docs.isNotEmpty) await batch.commit();
    } catch (e) {
      debugPrint('[demo_booking] notify admins failed: $e');
    }

    // 7. Notify the customer
    try {
      await db.collection('notifications').add({
        'userId': customerId,
        'type': 'demo_booking_received',
        'title': '⏳ הזמנתך התקבלה',
        'body': customerNotificationBody,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    return true;
  }

  /// Build the `jobs/{id}` payload with all CSM-specific preferences
  /// + schema flags + booking requirements + deposit fields.
  static Map<String, dynamic> _buildJobPayload({
    required BookingRequest req,
    required String jobId,
    required String chatRoomId,
    required Map<String, dynamic> customerData,
    required double totalPrice,
    required double paidAtBooking,
    required double depositAmount,
    required double remainingAmount,
    required double commission,
    required double expertNet,
    required DateTime? cancelDeadline,
  }) {
    final payload = <String, dynamic>{
      'jobId': jobId,
      'chatRoomId': chatRoomId,
      'customerId': req.customerId,
      'customerName': customerData['name'] ?? '',
      'expertId': req.expertId,
      'expertName': req.expertName,
      'totalPaidByCustomer': paidAtBooking,
      'totalAmount': totalPrice,
      'commissionAmount': commission,
      'netAmountForExpert': expertNet,
      'appointmentDate': req.selectedDay,
      'appointmentTime': req.selectedTimeSlot,
      'status': 'paid_escrow',
      'createdAt': FieldValue.serverTimestamp(),
      'cancellationPolicy': req.cancellationPolicy,
      'expertServiceType': req.lastSchemaCategory,
    };
    if (cancelDeadline != null) {
      payload['cancellationDeadline'] = Timestamp.fromDate(cancelDeadline);
    }
    if (req.bookingReqValues.isNotEmpty) {
      payload['bookingRequirementValues'] =
          Map<String, dynamic>.from(req.bookingReqValues);
    }
    if (depositAmount > 0) {
      payload['depositAmount'] = depositAmount;
      payload['depositPercent'] = req.serviceSchema.depositPercent;
      payload['paidAtBooking'] = paidAtBooking;
      payload['remainingAmount'] = remainingAmount;
      payload['depositPaidAt'] = FieldValue.serverTimestamp();
    }
    if (req.serviceSchema.walkTracking) payload['flagWalkTracking'] = true;
    if (req.serviceSchema.dailyProof) payload['flagDailyProof'] = true;
    if (req.serviceSchema.priceLocked) payload['flagPriceLocked'] = true;
    if (req.serviceSchema.requireVisualDiagnosis) {
      payload['flagRequireVisualDiagnosis'] = true;
    }

    // CSM preferences — at most one is non-null per booking.
    // Each writes both its prefs map AND a priceBreakdown.
    void addCsm(String prefsKey, Map<String, dynamic>? prefs, double base) {
      if (prefs == null) return;
      payload[prefsKey] = prefs;
      payload['priceBreakdown'] = {'basePrice': base, 'total': totalPrice};
    }

    addCsm('massagePreferences',
        req.massagePreferences?.toMap(), req.massageTotalPrice);
    addCsm('pestControlPreferences',
        req.pestControlPreferences?.toMap(), req.pestControlTotalPrice);
    addCsm('deliveryPreferences',
        req.deliveryPreferences?.toMap(), req.deliveryTotalPrice);
    addCsm('cleaningPreferences',
        req.cleaningPreferences?.toMap(), req.cleaningTotalPrice);
    addCsm('handymanPreferences',
        req.handymanPreferences?.toMap(), req.handymanTotalPrice);
    addCsm('babysitterPreferences',
        req.babysitterPreferences?.toMap(), req.babysitterTotalPrice);
    addCsm('motorcycleTowPreferences',
        req.motorcycleTowPreferences?.toMap(),
        req.motorcycleTowTotalPrice);

    // Fitness has a different shape (PricingPackage, not BookingPreferences).
    if (req.fitnessPackage != null) {
      final pkg = req.fitnessPackage!;
      payload['fitnessTrainerPreferences'] = {
        'packageId': pkg.id,
        'packageName': pkg.name,
        'packageType': pkg.type.name,
        'sessions': pkg.sessions,
        'durationMinutes': pkg.durationMinutes,
        'price': pkg.price,
        if (pkg.discount != null) 'discount': pkg.discount,
        'isPopular': pkg.isPopular,
      };
      payload['priceBreakdown'] = {
        'basePrice': req.fitnessTotalPrice,
        'total': totalPrice,
      };
    }

    return payload;
  }
}
