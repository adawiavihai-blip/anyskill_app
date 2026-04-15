/// AnyTasks 3.0 — Core Service
///
/// Manages the full task lifecycle:
///   - createTask()         — customer posts a new task + pays into escrow
///   - claimTask()          — provider claims an open task (atomic transaction)
///   - startWork()          — provider starts work (claimed → in_progress)
///   - submitProof()        — provider uploads proof (in_progress → proof_submitted)
///   - confirmCompletion()  — customer confirms + releases escrow
///   - openDispute()        — customer disputes proof (blocks auto-release)
///   - cancelTask()         — either party cancels (penalty logic applied)
///   - Stream methods for UI (open feed, my tasks, single task)
///
/// Follows the singleton pattern of CommunityHubService.
/// Escrow reuses the existing `jobs` collection pipeline.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/anytask.dart';
import 'anytask_antifraud_service.dart';
import 'anytask_cancellation_service.dart';

class AnytaskService {
  AnytaskService._();

  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ── Constants ──────────────────────────────────────────────────────────

  /// Auto-release window: hours after proof upload before auto-release.
  static const int autoReleaseHours = 48;

  /// Open task TTL: tasks with no claim expire after this many days.
  static const int openTaskTtlDays = 7;

  /// Minimum task amount (₪).
  static const double minTaskAmount = 10.0;

  // ═══════════════════════════════════════════════════════════════════════
  // CREATE TASK
  // ═══════════════════════════════════════════════════════════════════════

  /// Creates a new AnyTask and locks the amount in escrow.
  ///
  /// Returns the task document ID on success, or a Hebrew error string.
  static Future<String> createTask({
    required String title,
    required String description,
    required String category,
    required double amount,
    String? locationText,
    GeoPoint? location,
    bool requiresPhysical = false,
    DateTime? deadline,
    String proofType = 'photo',
    bool isUrgent = false,
    String? creatorDeviceId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'יש להתחבר תחילה';

    final trimTitle = title.trim();
    final trimDesc  = description.trim();

    if (trimTitle.length < 3) return 'כותרת חייבת להכיל לפחות 3 תווים';
    if (trimDesc.length < 10) return 'תיאור חייב להכיל לפחות 10 תווים';
    if (amount < minTaskAmount) return 'סכום מינימלי: ₪${minTaskAmount.toStringAsFixed(0)}';

    try {
      final adminSettingsRef = _db
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings');

      String? createdTaskId;

      await _db.runTransaction((tx) async {
        // ── Read required docs ─────────────────────────────────────────
        final clientDoc  = await tx.get(_db.collection('users').doc(user.uid));
        final adminDoc   = await tx.get(adminSettingsRef);

        final clientData = clientDoc.data() ?? {};
        final clientBalance = (clientData['balance'] as num? ?? 0).toDouble();
        final clientName    = clientData['name'] as String? ?? user.displayName ?? '';
        final clientImage   = clientData['profileImage'] as String?;

        if (clientBalance < amount) {
          throw Exception('אין מספיק יתרה. נדרש: ₪${amount.toStringAsFixed(0)}');
        }

        final feePct = ((adminDoc.data() ?? {})['feePercentage'] as num? ?? 0.10).toDouble();
        final commission    = double.parse((amount * feePct).toStringAsFixed(2));
        final netToProvider = double.parse((amount - commission).toStringAsFixed(2));

        // ── Create task document ───────────────────────────────────────
        final taskRef = _db.collection('anytasks').doc();
        createdTaskId = taskRef.id;

        tx.set(taskRef, {
          'creatorId':          user.uid,
          'creatorName':        clientName,
          'creatorImage':       clientImage,
          'title':              trimTitle,
          'description':        trimDesc,
          'category':           category,
          'amount':             amount,
          'currency':           'ILS',
          'location':           location,
          'locationText':       locationText,
          'requiresPhysical':   requiresPhysical,
          'deadline':           deadline != null ? Timestamp.fromDate(deadline) : null,
          'proofType':          proofType,
          'providerId':         null,
          'providerName':       null,
          'providerImage':      null,
          'status':             AnyTaskStatus.open,
          'claimedAt':          null,
          'chatRoomId':         null,
          'commission':         commission,
          'netToProvider':      netToProvider,
          'jobId':              null,
          'proofText':          null,
          'proofPhotoUrl':      null,
          'proofUploadedAt':    null,
          'autoReleaseDate':    null,
          'autoReleased':       false,
          'completedAt':        null,
          'confirmedByCreator': false,
          'cancelledAt':        null,
          'cancelledBy':        null,
          'creatorDeviceId':    creatorDeviceId,
          'disputedAt':         null,
          'disputeReason':      null,
          'disputeResolution':  null,
          'viewCount':          0,
          'isUrgent':           isUrgent,
          'source':             'app',
          'createdAt':          FieldValue.serverTimestamp(),
          'updatedAt':          FieldValue.serverTimestamp(),
        });

        // ── Deduct client balance (escrow lock) ────────────────────────
        tx.update(_db.collection('users').doc(user.uid), {
          'balance': FieldValue.increment(-amount),
        });

        // ── Transaction log ────────────────────────────────────────────
        tx.set(_db.collection('transactions').doc(), {
          'senderId':     user.uid,
          'senderName':   clientName,
          'receiverId':   'escrow',
          'receiverName': 'AnyTasks Escrow',
          'amount':       amount,
          'type':         'anytask_escrow_lock',
          'taskId':       taskRef.id,
          'payoutStatus': 'pending',
          'timestamp':    FieldValue.serverTimestamp(),
        });
      });

      // ── Activity log (outside transaction) ─────────────────────────
      if (createdTaskId != null) {
        await _logActivity(createdTaskId!, user.uid, 'creator', 'created',
            'Task created: $trimTitle (₪${amount.toStringAsFixed(0)})');
      }

      return createdTaskId ?? 'שגיאה ביצירת המשימה';
    } on FirebaseException catch (e) {
      debugPrint('[AnytaskService] createTask FirebaseException: $e');
      return e.message ?? 'שגיאת מסד נתונים';
    } catch (e) {
      debugPrint('[AnytaskService] createTask error: $e');
      return e.toString().replaceAll('Exception: ', '');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CLAIM TASK (Atomic Transaction)
  // ═══════════════════════════════════════════════════════════════════════

  /// Provider claims an open task. Uses Firestore transaction for atomicity.
  /// Returns null on success, or a Hebrew error string.
  static Future<String?> claimTask({
    required String taskId,
    required String providerId,
    required String providerName,
    String? providerImage,
  }) async {
    // ── Pre-checks (outside transaction for efficiency) ──────────────
    final suspensionError = await AnytaskAntifraudService.checkSuspension(providerId);
    if (suspensionError != null) return suspensionError;

    try {
      final docRef = _db.collection('anytasks').doc(taskId);

      final result = await _db.runTransaction<String?>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return 'המשימה לא נמצאה';

        final data = snap.data() ?? {};
        final status    = data['status'] as String? ?? '';
        final creatorId = data['creatorId'] as String? ?? '';

        // Self-assignment block
        final selfBlock = AnytaskAntifraudService.blockSelfAssignment(
          creatorId: creatorId,
          providerId: providerId,
        );
        if (selfBlock != null) return selfBlock;

        // Must be open
        if (status != AnyTaskStatus.open) {
          return 'המשימה כבר נתפסה על ידי מישהו אחר';
        }

        // ── Create chat room ───────────────────────────────────────────
        final uids = [creatorId, providerId]..sort();
        final chatRoomId = '${uids[0]}_${uids[1]}';

        tx.update(docRef, {
          'providerId':    providerId,
          'providerName':  providerName,
          'providerImage': providerImage,
          'status':        AnyTaskStatus.claimed,
          'claimedAt':     FieldValue.serverTimestamp(),
          'chatRoomId':    chatRoomId,
          'updatedAt':     FieldValue.serverTimestamp(),
        });

        // Ensure chat room exists
        tx.set(
          _db.collection('chats').doc(chatRoomId),
          {
            'users': [creatorId, providerId],
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return null; // success
      });

      if (result != null) return result;

      // ── Post-transaction: notifications + activity log + system msg ──
      final taskDoc = await docRef.get();
      final taskData = taskDoc.data() ?? {};
      final creatorId  = taskData['creatorId'] as String? ?? '';
      final title      = taskData['title'] as String? ?? '';
      final chatRoomId = taskData['chatRoomId'] as String? ?? '';

      // Device collision check (non-blocking)
      AnytaskAntifraudService.checkDeviceCollision(
        creatorDeviceId: taskData['creatorDeviceId'] as String?,
        providerId: providerId,
      );

      // Notification to creator
      await _db.collection('notifications').add({
        'userId':        creatorId,
        'title':         '🎯 מישהו תפס את המשימה שלך!',
        'body':          '$providerName תפס/ה את "$title"',
        'type':          'anytask_claimed',
        'relatedUserId': providerId,
        'isRead':        false,
        'createdAt':     FieldValue.serverTimestamp(),
      });

      // System message in chat
      if (chatRoomId.isNotEmpty) {
        await _db
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId':  'system',
          'message':   '🎯 $providerName תפס/ה את המשימה "$title"! אפשר להתחיל לתאם.',
          'type':      'system_alert',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await _logActivity(taskId, providerId, 'provider', 'claimed', providerName);

      return null;
    } catch (e) {
      debugPrint('[AnytaskService] claimTask error: $e');
      return 'שגיאה בתפיסת המשימה. נסה שוב.';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // START WORK
  // ═══════════════════════════════════════════════════════════════════════

  /// Provider transitions task from claimed → in_progress.
  static Future<String?> startWork(String taskId, String providerId) async {
    try {
      final docRef = _db.collection('anytasks').doc(taskId);
      final snap   = await docRef.get();
      if (!snap.exists) return 'המשימה לא נמצאה';

      final data   = snap.data() ?? {};
      final status = data['status'] as String? ?? '';
      final docProviderId = data['providerId'] as String? ?? '';

      if (providerId != docProviderId) return 'רק נותן השירות שתפס יכול להתחיל';
      if (status != AnyTaskStatus.claimed) return 'המשימה לא בסטטוס מתאים';

      await docRef.update({
        'status':    AnyTaskStatus.inProgress,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _logActivity(taskId, providerId, 'provider', 'started', 'Work started');
      return null;
    } catch (e) {
      debugPrint('[AnytaskService] startWork error: $e');
      return 'שגיאה בהתחלת העבודה';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SUBMIT PROOF
  // ═══════════════════════════════════════════════════════════════════════

  /// Provider submits proof of completion (photo URL + optional text).
  /// Transitions: in_progress → proof_submitted.
  /// Sets autoReleaseDate = now + 48 hours.
  static Future<String?> submitProof({
    required String taskId,
    required String providerId,
    required String proofPhotoUrl,
    String? proofText,
  }) async {
    try {
      final docRef = _db.collection('anytasks').doc(taskId);
      final snap   = await docRef.get();
      if (!snap.exists) return 'המשימה לא נמצאה';

      final data   = snap.data() ?? {};
      final status = data['status'] as String? ?? '';
      final docProviderId = data['providerId'] as String? ?? '';
      final creatorId     = data['creatorId'] as String? ?? '';
      final title         = data['title'] as String? ?? '';
      final providerName  = data['providerName'] as String? ?? 'נותן השירות';

      if (providerId != docProviderId) return 'רק נותן השירות שתפס יכול לשלוח הוכחה';
      if (status != AnyTaskStatus.inProgress && status != AnyTaskStatus.claimed) {
        return 'המשימה לא בסטטוס פעיל';
      }
      if (proofPhotoUrl.isEmpty) return 'יש לצרף תמונת הוכחה';

      final now = DateTime.now();
      final autoRelease = now.add(const Duration(hours: autoReleaseHours));

      await docRef.update({
        'status':          AnyTaskStatus.proofSubmitted,
        'proofPhotoUrl':   proofPhotoUrl,
        'proofText':       proofText?.trim(),
        'proofUploadedAt': FieldValue.serverTimestamp(),
        'autoReleaseDate': Timestamp.fromDate(autoRelease),
        'updatedAt':       FieldValue.serverTimestamp(),
      });

      // Notify creator
      await _db.collection('notifications').add({
        'userId':        creatorId,
        'title':         '📸 $providerName סיים/ה את המשימה!',
        'body':          'יש לך 48 שעות לאשר או לפתוח מחלוקת ב"$title"',
        'type':          'anytask_proof_submitted',
        'relatedUserId': providerId,
        'isRead':        false,
        'createdAt':     FieldValue.serverTimestamp(),
      });

      await _logActivity(taskId, providerId, 'provider', 'proof_uploaded', 'Proof submitted');
      return null;
    } catch (e) {
      debugPrint('[AnytaskService] submitProof error: $e');
      return 'שגיאה בשליחת ההוכחה';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONFIRM COMPLETION (Customer releases escrow)
  // ═══════════════════════════════════════════════════════════════════════

  /// Customer confirms the task is done. Releases escrow to provider.
  /// Transitions: proof_submitted → completed.
  static Future<String?> confirmCompletion(String taskId, String creatorId) async {
    try {
      final docRef = _db.collection('anytasks').doc(taskId);
      final snap   = await docRef.get();
      if (!snap.exists) return 'המשימה לא נמצאה';

      final data   = snap.data() ?? {};
      final status = data['status'] as String? ?? '';
      final docCreatorId = data['creatorId'] as String? ?? '';
      final providerId   = data['providerId'] as String? ?? '';
      final commission    = (data['commission'] as num? ?? 0).toDouble();
      final netToProvider = (data['netToProvider'] as num? ?? 0).toDouble();
      final title         = data['title'] as String? ?? '';

      if (creatorId != docCreatorId) return 'רק מפרסם המשימה יכול לאשר';
      if (status != AnyTaskStatus.proofSubmitted) return 'המשימה לא בסטטוס מתאים לאישור';

      // ── Release escrow via batch ──────────────────────────────────────
      final batch = _db.batch();

      // Mark task as completed
      batch.update(docRef, {
        'status':             AnyTaskStatus.completed,
        'confirmedByCreator': true,
        'completedAt':        FieldValue.serverTimestamp(),
        'updatedAt':          FieldValue.serverTimestamp(),
      });

      // Credit provider balance
      batch.update(_db.collection('users').doc(providerId), {
        'balance':        FieldValue.increment(netToProvider),
        'pendingBalance': FieldValue.increment(-netToProvider),
      });

      // Platform commission
      batch.set(_db.collection('platform_earnings').doc(), {
        'taskId':         taskId,
        'amount':         commission,
        'sourceExpertId': providerId,
        'timestamp':      FieldValue.serverTimestamp(),
        'status':         'settled',
        'source':         'anytask',
      });

      // Transaction record
      batch.set(_db.collection('transactions').doc(), {
        'senderId':     'escrow',
        'senderName':   'AnyTasks Escrow',
        'receiverId':   providerId,
        'receiverName': data['providerName'] ?? '',
        'amount':       netToProvider,
        'type':         'anytask_escrow_release',
        'taskId':       taskId,
        'payoutStatus': 'completed',
        'timestamp':    FieldValue.serverTimestamp(),
      });

      // Admin system balance
      batch.set(
        _db.collection('admin').doc('admin').collection('settings').doc('settings'),
        {'totalPlatformBalance': FieldValue.increment(commission)},
        SetOptions(merge: true),
      );

      await batch.commit();

      // ── Score recovery for provider ───────────────────────────────────
      await AnytaskCancellationService.recoverScore(providerId);

      // ── Update provider completed count ───────────────────────────────
      await _db.collection('users').doc(providerId).update({
        'anytaskCompletedCount': FieldValue.increment(1),
      });

      // ── Notify provider ───────────────────────────────────────────────
      await _db.collection('notifications').add({
        'userId':        providerId,
        'title':         '💰 קיבלת תשלום על "$title"!',
        'body':          '₪${netToProvider.toStringAsFixed(0)} הועברו לארנק שלך',
        'type':          'anytask_payment_released',
        'relatedUserId': creatorId,
        'isRead':        false,
        'createdAt':     FieldValue.serverTimestamp(),
      });

      await _logActivity(taskId, creatorId, 'creator', 'confirmed',
          'Payment released: ₪${netToProvider.toStringAsFixed(0)}');

      return null;
    } catch (e) {
      debugPrint('[AnytaskService] confirmCompletion error: $e');
      return 'שגיאה באישור המשימה. נסה שוב.';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OPEN DISPUTE
  // ═══════════════════════════════════════════════════════════════════════

  /// Customer disputes the proof. Blocks auto-release.
  /// Transitions: proof_submitted → disputed.
  static Future<String?> openDispute({
    required String taskId,
    required String creatorId,
    required String reason,
  }) async {
    if (reason.trim().length < 10) return 'נא לתאר את הבעיה (לפחות 10 תווים)';

    try {
      final docRef = _db.collection('anytasks').doc(taskId);
      final snap   = await docRef.get();
      if (!snap.exists) return 'המשימה לא נמצאה';

      final data   = snap.data() ?? {};
      final status = data['status'] as String? ?? '';
      final docCreatorId = data['creatorId'] as String? ?? '';
      final providerId   = data['providerId'] as String? ?? '';
      final title        = data['title'] as String? ?? '';

      if (creatorId != docCreatorId) return 'רק מפרסם המשימה יכול לפתוח מחלוקת';
      if (status != AnyTaskStatus.proofSubmitted) return 'ניתן לפתוח מחלוקת רק לאחר שליחת הוכחה';

      await docRef.update({
        'status':            AnyTaskStatus.disputed,
        'disputedAt':        FieldValue.serverTimestamp(),
        'disputeReason':     reason.trim(),
        'autoReleaseDate':   null, // block auto-release
        'updatedAt':         FieldValue.serverTimestamp(),
      });

      // Notify provider
      await _db.collection('notifications').add({
        'userId':        providerId,
        'title':         '⚠️ נפתחה מחלוקת על "$title"',
        'body':          'הלקוח פתח מחלוקת. צוות AnySkill יבדוק בקרוב.',
        'type':          'anytask_disputed',
        'relatedUserId': creatorId,
        'isRead':        false,
        'createdAt':     FieldValue.serverTimestamp(),
      });

      await _logActivity(taskId, creatorId, 'creator', 'disputed', reason.trim());
      return null;
    } catch (e) {
      debugPrint('[AnytaskService] openDispute error: $e');
      return 'שגיאה בפתיחת מחלוקת';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CANCEL TASK
  // ═══════════════════════════════════════════════════════════════════════

  /// Cancels a task with penalty logic. Returns null on success or error string.
  static Future<String?> cancelTask({
    required String taskId,
    required String cancelledBy, // UID
  }) async {
    try {
      final docRef = _db.collection('anytasks').doc(taskId);
      final snap   = await docRef.get();
      if (!snap.exists) return 'המשימה לא נמצאה';

      final data       = snap.data() ?? {};
      final status     = data['status'] as String? ?? '';
      final creatorId  = data['creatorId'] as String? ?? '';
      final providerId = data['providerId'] as String?;
      final amount     = (data['amount'] as num? ?? 0).toDouble();
      final claimedAt  = (data['claimedAt'] as Timestamp?)?.toDate();

      // Determine role
      final role = cancelledBy == creatorId ? 'creator' : 'provider';

      // Calculate penalty
      final penalty = AnytaskCancellationService.calculatePenalty(
        cancelledBy: role,
        status: status,
        claimedAt: claimedAt,
      );

      // Block if proof already submitted
      if (penalty.tier == 'blocked') return penalty.description;

      // Calculate refund
      final feeAmount = double.parse((amount * penalty.feeFraction).toStringAsFixed(2));
      final refundAmount = double.parse((amount - feeAmount).toStringAsFixed(2));

      final batch = _db.batch();

      // Update task
      batch.update(docRef, {
        'status':             AnyTaskStatus.cancelled,
        'cancelledAt':        FieldValue.serverTimestamp(),
        'cancelledBy':        role,
        'cancellationReason': penalty.description,
        'penaltyAmount':      feeAmount,
        'penaltyAppliedTo':   cancelledBy,
        'updatedAt':          FieldValue.serverTimestamp(),
      });

      // Refund creator (minus any fee)
      if (refundAmount > 0) {
        batch.update(_db.collection('users').doc(creatorId), {
          'balance': FieldValue.increment(refundAmount),
        });
      }

      // If provider was assigned, clear their pending balance
      if (providerId != null && providerId.isNotEmpty) {
        final netToProvider = (data['netToProvider'] as num? ?? 0).toDouble();
        batch.update(_db.collection('users').doc(providerId), {
          'pendingBalance': FieldValue.increment(-netToProvider),
        });
      }

      // Platform keeps the fee
      if (feeAmount > 0) {
        batch.set(
          _db.collection('admin').doc('admin').collection('settings').doc('settings'),
          {'totalPlatformBalance': FieldValue.increment(feeAmount)},
          SetOptions(merge: true),
        );
        batch.set(_db.collection('platform_earnings').doc(), {
          'taskId':    taskId,
          'amount':    feeAmount,
          'timestamp': FieldValue.serverTimestamp(),
          'status':    'cancellation_fee',
          'source':    'anytask',
        });
      }

      // Refund transaction record
      batch.set(_db.collection('transactions').doc(), {
        'senderId':     'escrow',
        'senderName':   'AnyTasks Escrow',
        'receiverId':   creatorId,
        'receiverName': data['creatorName'] ?? '',
        'amount':       refundAmount,
        'type':         'anytask_refund',
        'taskId':       taskId,
        'payoutStatus': 'completed',
        'timestamp':    FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Apply score penalty (async, non-blocking)
      if (penalty.scoreImpact != 0) {
        AnytaskCancellationService.applyPenalty(
          taskId: taskId,
          userId: cancelledBy,
          penalty: penalty,
          taskAmount: amount,
        );
      }

      // Notify the other party
      final otherUserId = role == 'creator' ? providerId : creatorId;
      if (otherUserId != null && otherUserId.isNotEmpty) {
        await _db.collection('notifications').add({
          'userId':    otherUserId,
          'title':     '❌ משימה בוטלה',
          'body':      'המשימה "${data['title']}" בוטלה על ידי ${role == 'creator' ? 'המפרסם' : 'נותן השירות'}.',
          'type':      'anytask_cancelled',
          'isRead':    false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _logActivity(taskId, cancelledBy, role, 'cancelled', penalty.tier);
      return null;
    } catch (e) {
      debugPrint('[AnytaskService] cancelTask error: $e');
      return 'שגיאה בביטול המשימה';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STREAMS
  // ═══════════════════════════════════════════════════════════════════════

  /// Streams open tasks, optionally filtered by category.
  static Stream<QuerySnapshot> streamOpenTasks({String? category}) {
    Query query = _db
        .collection('anytasks')
        .where('status', isEqualTo: AnyTaskStatus.open)
        .orderBy('createdAt', descending: true)
        .limit(30);

    if (category != null && category.isNotEmpty) {
      query = _db
          .collection('anytasks')
          .where('status', isEqualTo: AnyTaskStatus.open)
          .where('category', isEqualTo: category)
          .orderBy('createdAt', descending: true)
          .limit(30);
    }

    return query.snapshots();
  }

  /// Streams tasks created by this user (as customer).
  static Stream<QuerySnapshot> streamMyCreatedTasks(String userId) {
    return _db
        .collection('anytasks')
        .where('creatorId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Streams tasks assigned to this user (as provider).
  static Stream<QuerySnapshot> streamMyProviderTasks(String userId) {
    return _db
        .collection('anytasks')
        .where('providerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Streams active tasks for this provider (non-terminal statuses).
  static Stream<QuerySnapshot> streamMyActiveProviderTasks(String userId) {
    return _db
        .collection('anytasks')
        .where('providerId', isEqualTo: userId)
        .where('status', whereIn: AnyTaskStatus.active.toList())
        .limit(20)
        .snapshots();
  }

  /// Streams a single task document for real-time detail view.
  static Stream<DocumentSnapshot> streamTask(String taskId) {
    return _db.collection('anytasks').doc(taskId).snapshots();
  }

  /// One-shot fetch for a single task.
  static Future<AnyTask?> getTask(String taskId) async {
    try {
      final snap = await _db.collection('anytasks').doc(taskId).get();
      if (!snap.exists) return null;
      return AnyTask.fromFirestore(snap);
    } catch (e) {
      debugPrint('[AnytaskService] getTask error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIVITY LOG
  // ═══════════════════════════════════════════════════════════════════════

  static Future<void> _logActivity(
    String taskId,
    String actorId,
    String actorRole,
    String action,
    String? details,
  ) async {
    try {
      await _db
          .collection('anytasks')
          .doc(taskId)
          .collection('activity')
          .add({
        'actorId':   actorId,
        'actorRole': actorRole,
        'action':    action,
        'details':   details,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AnytaskService] _logActivity error: $e');
    }
  }
}
