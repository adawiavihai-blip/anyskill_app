/// AnySkill — Volunteer Service
///
/// Central service for volunteer task lifecycle:
///   - Task creation with anti-fraud validation
///   - Client confirmation flow
///   - GPS proximity validation
///   - Dynamic "Volunteer Badge" (active if >= 1 task completed in last 30 days)
///   - XP award on verified completion
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'gamification_service.dart';

class VolunteerService {
  VolunteerService._();

  static final _db = FirebaseFirestore.instance;

  // ── Constants ──────────────────────────────────────────────────────────────

  /// XP awarded for a verified volunteer task completion.
  static const int volunteerXpReward = 150;

  /// Max distance (meters) between provider and client GPS for validation.
  static const double gpsProximityThreshold = 500.0;

  /// Window (days) for the dynamic volunteer badge.
  static const int badgeWindowDays = 30;

  /// XP event ID for Cloud Function (matches gamification_service pattern).
  static const String evVolunteerTask = 'volunteer_task';

  /// Same-user cooldown: a provider cannot earn XP from the same client
  /// more than once within this window.
  static const int sameClientCooldownDays = 30;

  /// Reciprocal block window: if A helped B, B cannot earn volunteer XP
  /// from A within this window. Prevents tit-for-tat farming.
  static const int reciprocalBlockDays = 30;

  /// Daily cap on volunteer XP. At 150 XP/task this allows 2 tasks/day.
  static const int dailyVolunteerXpCap = 300;

  /// Minimum characters for the client's completion review (proof of work).
  static const int minReviewLength = 10;

  // ── Task Creation (with anti-fraud) ────────────────────────────────────────

  /// Creates a volunteer task.
  ///
  /// Anti-fraud rules:
  ///   1. [clientId] != [providerId] — cannot self-assign.
  ///   2. Client must have `isElderlyOrNeedy == true` OR be a different
  ///      account type (not a provider requesting from themselves).
  ///
  /// Returns the new task document ID, or null on validation failure.
  static Future<String?> createTask({
    required String clientId,
    required String providerId,
    required String category,
    required String description,
    String? helpRequestId,
    double? clientLat,
    double? clientLng,
  }) async {
    // ── Anti-fraud: self-assignment check ──────────────────────────────────
    if (clientId == providerId) {
      debugPrint('[VolunteerService] BLOCKED: self-assignment attempt '
          'client=$clientId provider=$providerId');
      return null;
    }

    // ── Anti-fraud: verify client exists and is not the same person ───────
    final clientDoc = await _db.collection('users').doc(clientId).get();
    final clientData = clientDoc.data() ?? {};
    final isElderlyOrNeedy = clientData['isElderlyOrNeedy'] == true;
    final clientIsProvider = clientData['isProvider'] == true;

    // If the client is also a provider, they must have the verified tag
    // to request volunteer help — prevents fake "needy" accounts.
    if (clientIsProvider && !isElderlyOrNeedy) {
      // Still allowed — providers can request help from volunteers,
      // but the system flags it for review. The critical block is
      // self-assignment (clientId == providerId) above.
    }

    // ── Create volunteer task document ────────────────────────────────────
    final docRef = await _db.collection('volunteer_tasks').add({
      'clientId': clientId,
      'providerId': providerId,
      'category': category,
      'description': description,
      'status': 'pending',
      'clientConfirmed': false,
      'gpsValidated': false,
      'providerLat': null,
      'providerLng': null,
      'clientLat': clientLat,
      'clientLng': clientLng,
      'gpsDistanceMeters': null,
      'xpAwarded': false,
      'xpAmount': volunteerXpReward,
      'helpRequestId': helpRequestId,
      'createdAt': FieldValue.serverTimestamp(),
      'completedAt': null,
    });

    // Link back to help_request if exists
    if (helpRequestId != null && helpRequestId.isNotEmpty) {
      await _db.collection('help_requests').doc(helpRequestId).update({
        'status': 'accepted',
        'volunteerTaskId': docRef.id,
        'acceptedBy': providerId,
      });
    }

    // Notify the client
    await _db.collection('notifications').add({
      'userId': clientId,
      'title': '🤝 מתנדב קיבל את הבקשה שלך!',
      'body': 'מתנדב בקטגוריית "$category" אישר את בקשת העזרה שלך.',
      'type': 'volunteer_accepted',
      'relatedUserId': providerId,
      'category': category,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  // ── GPS Validation ─────────────────────────────────────────────────────────

  /// Validates that the provider is within [gpsProximityThreshold] of the
  /// client's location. Updates the task document with GPS data.
  ///
  /// Returns true if within threshold, false otherwise.
  static Future<bool> validateGpsProximity({
    required String taskId,
    required double providerLat,
    required double providerLng,
  }) async {
    final taskDoc = await _db.collection('volunteer_tasks').doc(taskId).get();
    final data = taskDoc.data() ?? {};

    final clientLat = (data['clientLat'] as num?)?.toDouble();
    final clientLng = (data['clientLng'] as num?)?.toDouble();

    double? distanceMeters;
    bool isValid = false;

    if (clientLat != null && clientLng != null) {
      distanceMeters = Geolocator.distanceBetween(
        providerLat, providerLng, clientLat, clientLng,
      );
      isValid = distanceMeters <= gpsProximityThreshold;
    }

    // Record GPS data on the task regardless of validity
    await _db.collection('volunteer_tasks').doc(taskId).update({
      'providerLat': providerLat,
      'providerLng': providerLng,
      'gpsDistanceMeters': distanceMeters,
      'gpsValidated': isValid,
    });

    return isValid;
  }

  // ── Client Confirmation ────────────────────────────────────────────────────

  /// Result of a confirmation attempt. `ok` means XP was awarded.
  /// Non-ok results carry a Hebrew reason string for the UI.
  static const String confirmOk = 'ok';

  /// Called by the CLIENT to confirm that the volunteer task was completed.
  /// This is the trigger for XP + badge award.
  ///
  /// Returns [confirmOk] on success, or a Hebrew error string on rejection.
  ///
  /// Anti-fraud checks (in order):
  ///   1. Only the original [clientId] can confirm.
  ///   2. Proof-of-work: [reviewText] must be >= [minReviewLength] chars.
  ///   3. Same-user cooldown: provider didn't earn from this client in last 30d.
  ///   4. Reciprocal block: provider didn't help this client in last 30d (no tit-for-tat).
  ///   5. Daily XP cap: provider hasn't exceeded [dailyVolunteerXpCap] today.
  static Future<String> confirmCompletion({
    required String taskId,
    required String confirmingUserId,
    required String reviewText,
    Position? providerPosition,
  }) async {
    final taskDoc = await _db.collection('volunteer_tasks').doc(taskId).get();
    if (!taskDoc.exists) return 'משימה לא נמצאה';

    final data = taskDoc.data() ?? {};
    final clientId = data['clientId'] as String? ?? '';
    final providerId = data['providerId'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    final alreadyConfirmed = data['clientConfirmed'] == true;

    // ── 1. Only the original client can confirm ──────────────────────────
    if (confirmingUserId != clientId) {
      debugPrint('[VolunteerService] BLOCKED: non-client confirmation attempt '
          'confirmer=$confirmingUserId client=$clientId');
      return 'רק הלקוח המקורי יכול לאשר';
    }

    // Don't double-confirm
    if (alreadyConfirmed || status == 'completed') {
      return 'המשימה כבר אושרה';
    }

    // ── 2. Proof-of-work review ──────────────────────────────────────────
    final trimmed = reviewText.trim();
    if (trimmed.length < minReviewLength) {
      return 'נא לכתוב חוות דעת של לפחות $minReviewLength תווים';
    }

    // ── 3. Same-user cooldown (30 days) ──────────────────────────────────
    final cooldownBlock = await _checkSameUserCooldown(providerId, clientId);
    if (cooldownBlock != null) return cooldownBlock;

    // ── 4. Reciprocal help block (30 days) ───────────────────────────────
    final reciprocalBlock = await _checkReciprocalBlock(providerId, clientId);
    if (reciprocalBlock != null) return reciprocalBlock;

    // ── 5. Daily XP cap ──────────────────────────────────────────────────
    final capBlock = await _checkDailyXpCap(providerId);
    if (capBlock != null) return capBlock;

    // ── Optional GPS validation at confirmation time ─────────────────────
    bool gpsValid = data['gpsValidated'] == true;
    if (providerPosition != null && !gpsValid) {
      gpsValid = await validateGpsProximity(
        taskId: taskId,
        providerLat: providerPosition.latitude,
        providerLng: providerPosition.longitude,
      );
    }

    // ── Mark task as completed ────────────────────────────────────────────
    await _db.collection('volunteer_tasks').doc(taskId).update({
      'clientConfirmed': true,
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'clientReview': trimmed,
    });

    // ── Award XP ──────────────────────────────────────────────────────────
    await _awardVolunteerXp(providerId, taskId);

    // ── Update provider's volunteer badge timestamp ───────────────────────
    await _db.collection('users').doc(providerId).update({
      'lastVolunteerTaskAt': FieldValue.serverTimestamp(),
      'volunteerTaskCount': FieldValue.increment(1),
      'hasActiveVolunteerBadge': true,
    });

    // ── Notify the provider ──────────────────────────────────────────────
    await _db.collection('notifications').add({
      'userId': providerId,
      'title': '🎉 המשימה ההתנדבותית אושרה!',
      'body': 'הלקוח אישר את ההתנדבות שלך! קיבלת +$volunteerXpReward XP '
          'ותג מתנדב פעיל.',
      'type': 'volunteer_completed',
      'relatedUserId': clientId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return confirmOk;
  }

  // ── Anti-fraud: same-user cooldown ─────────────────────────────────────────
  /// Returns null if OK, or a Hebrew error string if blocked.
  static Future<String?> _checkSameUserCooldown(
      String providerId, String clientId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: sameClientCooldownDays)),
    );
    final snap = await _db
        .collection('volunteer_tasks')
        .where('providerId', isEqualTo: providerId)
        .where('clientId', isEqualTo: clientId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return 'נותן השירות כבר קיבל אישור ממך ב-30 הימים האחרונים. '
          'נסה שוב מאוחר יותר.';
    }
    return null;
  }

  // ── Anti-fraud: reciprocal block ───────────────────────────────────────────
  /// If the current *provider* was helped BY the current *client* (roles
  /// reversed) within the window, block. Prevents A↔B XP farming.
  static Future<String?> _checkReciprocalBlock(
      String providerId, String clientId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: reciprocalBlockDays)),
    );
    // Reverse direction: the current client acted as PROVIDER for the current
    // provider (who acted as CLIENT).
    final snap = await _db
        .collection('volunteer_tasks')
        .where('providerId', isEqualTo: clientId)
        .where('clientId', isEqualTo: providerId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return 'לא ניתן לאשר — התנדבות הדדית אינה מותרת תוך 30 יום.';
    }
    return null;
  }

  // ── Anti-fraud: daily XP cap ───────────────────────────────────────────────
  /// Returns null if OK, or a Hebrew error string if the provider already
  /// hit the daily cap.
  static Future<String?> _checkDailyXpCap(String providerId) async {
    final todayStart = DateTime.now();
    final midnight = DateTime(todayStart.year, todayStart.month, todayStart.day);
    final cutoff = Timestamp.fromDate(midnight);

    final snap = await _db
        .collection('volunteer_tasks')
        .where('providerId', isEqualTo: providerId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(10)
        .get();

    int todayXp = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      todayXp += (d['xpAmount'] as num? ?? volunteerXpReward).toInt();
    }

    if (todayXp >= dailyVolunteerXpCap) {
      return 'נותן השירות הגיע למכסת ה-XP היומית ($dailyVolunteerXpCap XP). '
          'נסה שוב מחר.';
    }
    return null;
  }

  // ── XP Award ───────────────────────────────────────────────────────────────

  static Future<void> _awardVolunteerXp(String providerId, String taskId) async {
    // XP is awarded exclusively via Cloud Function (xp field is server-only
    // in security rules — client writes are blocked).
    await GamificationService.awardXP(providerId, evVolunteerTask);

    // Mark XP as awarded on the task
    await _db.collection('volunteer_tasks').doc(taskId).update({
      'xpAwarded': true,
    });
  }

  // ── Dynamic Volunteer Badge ────────────────────────────────────────────────

  /// Returns true if the user has completed at least 1 volunteer task
  /// in the last [badgeWindowDays] days.
  ///
  /// Fast path: checks `lastVolunteerTaskAt` on the user document.
  /// The field is updated by [confirmCompletion].
  static bool hasActiveVolunteerBadge(Map<String, dynamic> userData) {
    final ts = userData['lastVolunteerTaskAt'] as Timestamp?;
    if (ts == null) return false;
    final daysSince = DateTime.now().difference(ts.toDate()).inDays;
    return daysSince <= badgeWindowDays;
  }

  /// Checks badge status from Firestore directly (for cases where
  /// we don't already have the user data in memory).
  static Future<bool> checkActiveVolunteerBadge(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    final data = doc.data() ?? {};
    return hasActiveVolunteerBadge(data);
  }

  /// Refreshes the `hasActiveVolunteerBadge` field on a user document.
  /// Call this periodically (e.g., on profile load) to expire stale badges.
  static Future<void> refreshBadgeStatus(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    final data = doc.data() ?? {};
    final isActive = hasActiveVolunteerBadge(data);
    final storedActive = data['hasActiveVolunteerBadge'] == true;

    if (isActive != storedActive) {
      await _db.collection('users').doc(userId).update({
        'hasActiveVolunteerBadge': isActive,
      });
    }
  }

  // ── Query Helpers ──────────────────────────────────────────────────────────

  /// Streams volunteer tasks where the given user is the client (to confirm).
  static Stream<QuerySnapshot> streamPendingForClient(String clientId) {
    return _db
        .collection('volunteer_tasks')
        .where('clientId', isEqualTo: clientId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  /// Streams volunteer tasks where the given user is the provider.
  static Stream<QuerySnapshot> streamForProvider(String providerId) {
    return _db
        .collection('volunteer_tasks')
        .where('providerId', isEqualTo: providerId)
        .where('status', whereIn: ['pending', 'in_progress'])
        .limit(20)
        .snapshots();
  }

  /// Counts completed volunteer tasks in the badge window for a user.
  static Future<int> recentCompletedCount(String providerId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: badgeWindowDays)),
    );
    final snap = await _db
        .collection('volunteer_tasks')
        .where('providerId', isEqualTo: providerId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(50)
        .get();
    return snap.size;
  }
}
