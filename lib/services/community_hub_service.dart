/// AnySkill — Community Hub Service
///
/// Manages the lifecycle of community help requests:
///   - Creating requests (anyone — customers AND providers)
///   - Claiming requests (volunteers, atomic transaction)
///   - Completing requests (confirmed by requester)
///   - 3× XP award on verified completion (450 XP)
///   - Badge progression: Starter → Pillar → Angel
///   - Volunteer Heart management (permanent once earned)
///   - Anti-fraud checks (cooldown, reciprocal, daily cap)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'gamification_service.dart';

class CommunityHubService {
  CommunityHubService._();

  static final _db = FirebaseFirestore.instance;

  // ── Constants ──────────────────────────────────────────────────────────────

  /// XP awarded per community task (3× standard volunteer reward of 150).
  static const int communityXpReward = 450;

  /// Same-user cooldown (days).
  static const int sameUserCooldownDays = 30;

  /// Reciprocal block window (days).
  static const int reciprocalBlockDays = 30;

  /// Daily community XP cap (allows 2 tasks/day at 450 each).
  static const int dailyCommunityXpCap = 900;

  /// Min review length for completion confirmation (proof of work).
  static const int minReviewLength = 10;

  /// Minimum minutes between match (startedAt) and "I Finished" to prevent
  /// instant fake completions.
  static const int minTaskDurationMinutes = 15;

  // ── Badge Thresholds ───────────────────────────────────────────────────────

  static const int starterThreshold = 1;
  static const int pillarThreshold = 5;
  static const int angelThreshold = 10;

  // ── Requester Types ────────────────────────────────────────────────────────

  static const List<Map<String, dynamic>> requesterTypes = [
    {'id': 'elderly', 'label': 'קשישים', 'emoji': '👴'},
    {'id': 'lone_soldier', 'label': 'חיילים בודדים', 'emoji': '🎖️'},
    {'id': 'struggling_family', 'label': 'משפחות נזקקות', 'emoji': '👨‍👩‍👧'},
    {'id': 'general', 'label': 'כללי', 'emoji': '🤝'},
  ];

  // ── Help Categories ────────────────────────────────────────────────────────

  static const List<Map<String, dynamic>> helpCategories = [
    {'id': 'repair', 'label': 'תיקונים'},
    {'id': 'cleaning', 'label': 'ניקיון'},
    {'id': 'delivery', 'label': 'הובלות'},
    {'id': 'teaching', 'label': 'שיעורים'},
    {'id': 'tech', 'label': 'טכנולוגיה'},
    {'id': 'cooking', 'label': 'בישול'},
    {'id': 'companionship', 'label': 'ליווי וחברות'},
    {'id': 'other', 'label': 'אחר'},
  ];

  /// Icon mapping for categories.
  static IconData categoryIcon(String catId) {
    switch (catId) {
      case 'repair':
        return Icons.build_rounded;
      case 'cleaning':
        return Icons.cleaning_services_rounded;
      case 'delivery':
        return Icons.local_shipping_rounded;
      case 'teaching':
        return Icons.school_rounded;
      case 'tech':
        return Icons.computer_rounded;
      case 'cooking':
        return Icons.restaurant_rounded;
      case 'companionship':
        return Icons.favorite_rounded;
      default:
        return Icons.more_horiz_rounded;
    }
  }

  /// Icon mapping for requester types.
  static IconData requesterTypeIcon(String typeId) {
    switch (typeId) {
      case 'elderly':
        return Icons.elderly_rounded;
      case 'lone_soldier':
        return Icons.military_tech_rounded;
      case 'struggling_family':
        return Icons.family_restroom_rounded;
      default:
        return Icons.people_rounded;
    }
  }

  /// Color mapping for requester types.
  static Color requesterTypeColor(String typeId) {
    switch (typeId) {
      case 'elderly':
        return const Color(0xFFEF4444);
      case 'lone_soldier':
        return const Color(0xFF6366F1);
      case 'struggling_family':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF10B981);
    }
  }

  /// Hebrew label for requester type.
  static String requesterTypeLabel(String typeId) {
    for (final t in requesterTypes) {
      if (t['id'] == typeId) return t['label'] as String;
    }
    return 'כללי';
  }

  /// Color for urgency level.
  static Color urgencyColor(String urgency) {
    switch (urgency) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF10B981);
    }
  }

  /// Hebrew label for urgency level.
  static String urgencyLabel(String urgency) {
    switch (urgency) {
      case 'high':
        return 'דחוף';
      case 'medium':
        return 'בינוני';
      default:
        return 'רגיל';
    }
  }

  // ── Create Request ─────────────────────────────────────────────────────────

  /// Creates a new community help request.
  /// Anyone (customer or provider) can create a request.
  static Future<String?> createRequest({
    required String requesterId,
    required String requesterName,
    required String title,
    required String description,
    required String category,
    required String requesterType,
    required String urgency,
    bool isAnonymous = false,
    GeoPoint? location,
    String? requesterImage,
    DateTime? targetDate,
  }) async {
    try {
      final docRef = await _db.collection('community_requests').add({
        'requesterId': requesterId,
        'requesterName': isAnonymous ? 'אנונימי' : requesterName,
        'requesterImage': isAnonymous ? null : requesterImage,
        'volunteerId': null,
        'volunteerName': null,
        'title': title,
        'description': description,
        'category': category,
        'requesterType': requesterType,
        'status': 'open',
        'urgency': urgency,
        'isAnonymous': isAnonymous,
        'location': location,
        'targetDate': targetDate != null
            ? Timestamp.fromDate(targetDate)
            : null,
        'createdAt': FieldValue.serverTimestamp(),
        'claimedAt': null,
        'completedAt': null,
        'volunteerReview': null,
      });

      // Notify matching volunteers
      await _notifyVolunteers(category, requesterId, title, urgency);

      return docRef.id;
    } catch (e) {
      debugPrint('[CommunityHub] createRequest error: $e');
      return null;
    }
  }

  // ── Active statuses for volunteer tasks ─────────────────────────────────────

  /// All statuses that represent an active (non-terminal) community task.
  static const Set<String> activeStatuses = {
    'accepted',
    'in_progress',
    'pending_confirmation',
  };

  // ── Claim Request (Atomic Transaction) ─────────────────────────────────────

  /// Volunteer claims an open request. Uses a Firestore transaction to
  /// ensure only one volunteer can claim (first-come-first-served).
  /// Status transitions: open → accepted (waiting for requester to confirm start).
  ///
  /// Returns null on success, or a Hebrew error string on failure.
  static Future<String?> claimRequest({
    required String requestId,
    required String volunteerId,
    required String volunteerName,
  }) async {
    try {
      final docRef = _db.collection('community_requests').doc(requestId);

      final result = await _db.runTransaction<String?>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return 'הבקשה לא נמצאה';

        final data = snap.data() ?? {};
        final status = data['status'] as String? ?? '';
        final requesterId = data['requesterId'] as String? ?? '';

        // Self-claim block
        if (volunteerId == requesterId) {
          return 'לא ניתן להתנדב לבקשה שלך';
        }

        // Already claimed
        if (status != 'open') {
          final claimedBy = data['volunteerName'] as String? ?? 'מתנדב';
          return 'הבקשה כבר נתפסה על ידי $claimedBy';
        }

        tx.update(docRef, {
          'volunteerId': volunteerId,
          'volunteerName': volunteerName,
          'status': 'accepted',
          'claimedAt': FieldValue.serverTimestamp(),
        });

        return null; // success
      });

      if (result != null) return result;

      // Post-transaction: send notification to requester
      final requestDoc = await docRef.get();
      final requestData = requestDoc.data() ?? {};
      final requesterId = requestData['requesterId'] as String? ?? '';
      final title = requestData['title'] as String? ?? '';

      await _db.collection('notifications').add({
        'userId': requesterId,
        'title': '🤝 מתנדב/ת אישר/ה את הבקשה שלך!',
        'body': '$volunteerName רוצה לעזור ב"$title" — אשר/י כדי להתחיל',
        'type': 'community_claimed',
        'relatedUserId': volunteerId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return null; // success
    } catch (e) {
      debugPrint('[CommunityHub] claimRequest error: $e');
      return 'שגיאה בתפיסת הבקשה';
    }
  }

  // ── Confirm Start (Requester approves volunteer) ──────────────────────────

  /// Called by the REQUESTER to approve the matched volunteer and start work.
  /// Status transitions: accepted → in_progress.
  ///
  /// Returns null on success, or a Hebrew error string on failure.
  static Future<String?> confirmStart({
    required String requestId,
    required String requesterId,
  }) async {
    try {
      final docRef = _db.collection('community_requests').doc(requestId);
      final snap = await docRef.get();
      if (!snap.exists) return 'הבקשה לא נמצאה';

      final data = snap.data() ?? {};
      final docRequesterId = data['requesterId'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      final volunteerId = data['volunteerId'] as String? ?? '';
      final title = data['title'] as String? ?? '';

      if (requesterId != docRequesterId) {
        return 'רק מי שביקש את העזרה יכול לאשר';
      }
      if (status != 'accepted') {
        return 'הבקשה לא בסטטוס הנכון לאישור התחלה';
      }

      await docRef.update({
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
      });

      // Notify volunteer that work can begin
      if (volunteerId.isNotEmpty) {
        await _db.collection('notifications').add({
          'userId': volunteerId,
          'title': '✅ הפונה אישר/ה — אפשר להתחיל!',
          'body': 'הבקשה "$title" אושרה. אפשר להתחיל לעזור!',
          'type': 'community_started',
          'relatedUserId': requesterId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return null;
    } catch (e) {
      debugPrint('[CommunityHub] confirmStart error: $e');
      return 'שגיאה באישור ההתחלה';
    }
  }

  // ── Mark Task Done (Volunteer signals completion) ─────────────────────────

  /// Called by the VOLUNTEER to signal they finished helping.
  /// Status transitions: in_progress → pending_confirmation.
  ///
  /// Requires [completionPhotoUrl] — a Firebase Storage URL of the uploaded
  /// evidence photo. The photo is displayed to the requester during confirmation.
  ///
  /// Enforces a minimum duration of [minTaskDurationMinutes] since the task
  /// was started (startedAt) to prevent instant fake completions.
  ///
  /// Returns null on success, or a Hebrew error string on failure.
  static Future<String?> markTaskDone({
    required String requestId,
    required String volunteerId,
    required String completionPhotoUrl,
  }) async {
    try {
      final docRef = _db.collection('community_requests').doc(requestId);
      final snap = await docRef.get();
      if (!snap.exists) return 'הבקשה לא נמצאה';

      final data = snap.data() ?? {};
      final docVolunteerId = data['volunteerId'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      final requesterId = data['requesterId'] as String? ?? '';
      final title = data['title'] as String? ?? '';
      final volunteerName = data['volunteerName'] as String? ?? 'מתנדב/ת';

      if (volunteerId != docVolunteerId) {
        return 'רק המתנדב/ת יכול/ה לסמן סיום';
      }
      if (status != 'in_progress') {
        return 'הבקשה לא בסטטוס פעיל';
      }

      // ── Photo evidence is mandatory ──────────────────────────────────
      if (completionPhotoUrl.isEmpty) {
        return 'יש לצלם תמונת הוכחה של העבודה שבוצעה';
      }

      // ── Timing guard: at least 15 min since match (startedAt) ────────
      final startedAt = data['startedAt'] as Timestamp?;
      if (startedAt != null) {
        final elapsed =
            DateTime.now().difference(startedAt.toDate()).inMinutes;
        if (elapsed < minTaskDurationMinutes) {
          final remaining = minTaskDurationMinutes - elapsed;
          return 'יש להמתין עוד $remaining דקות לפני סימון סיום '
              '(מינימום $minTaskDurationMinutes דקות מתחילת המשימה)';
        }
      }

      await docRef.update({
        'status': 'pending_confirmation',
        'markedDoneAt': FieldValue.serverTimestamp(),
        'completionPhotoUrl': completionPhotoUrl,
      });

      // Notify requester to confirm
      if (requesterId.isNotEmpty) {
        await _db.collection('notifications').add({
          'userId': requesterId,
          'title': '🔔 $volunteerName סיים/ה לעזור!',
          'body': 'אנא אשר/י שקיבלת עזרה ב"$title"',
          'type': 'community_pending_confirmation',
          'relatedUserId': volunteerId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return null;
    } catch (e) {
      debugPrint('[CommunityHub] markTaskDone error: $e');
      return 'שגיאה בסימון הסיום';
    }
  }

  // ── Complete Request (Requester Confirms) ──────────────────────────────────

  /// Called by the REQUESTER to confirm that help was received ("Confirm & Thank").
  /// Status transitions: pending_confirmation → completed.
  ///
  /// Uses **optimistic completion** pattern:
  ///   1. Validate preconditions (status, review length, anti-fraud)
  ///   2. Mark request as `completed` FIRST (what the user sees)
  ///   3. Award XP + update volunteer profile as best-effort
  ///   4. If secondary writes fail, the card still disappears — admin can fix rewards later
  ///
  /// Returns: `'ok'` on full success, `'ok_partial'` if status changed but
  /// rewards failed, or a Hebrew error string on hard rejection.
  static Future<String> completeRequest({
    required String requestId,
    required String confirmingUserId,
    required String reviewText,
    String? thankYouNote,
  }) async {
    // ── 1. Read the request doc ──────────────────────────────────────────
    final docRef = _db.collection('community_requests').doc(requestId);
    Map<String, dynamic> data;
    try {
      final snap = await docRef.get();
      if (!snap.exists) return 'הבקשה לא נמצאה';
      data = snap.data() ?? {};
    } catch (e) {
      debugPrint('[CommunityHub] completeRequest: doc read failed: $e');
      return 'שגיאה בטעינת הבקשה. בדוק את החיבור לאינטרנט ונסה שוב.';
    }

    final requesterId = data['requesterId'] as String? ?? '';
    final volunteerId = data['volunteerId'] as String? ?? '';
    final requesterName = data['requesterName'] as String? ?? '';
    final status = data['status'] as String? ?? '';

    // ── 2. Precondition checks (pure logic — cannot throw) ───────────────
    if (confirmingUserId != requesterId) {
      return 'רק מי שביקש את העזרה יכול לאשר';
    }
    if (status != 'pending_confirmation') {
      if (status == 'completed') return 'הבקשה כבר הושלמה';
      if (status == 'in_progress') return 'המתנדב/ת עדיין לא סימנ/ה סיום';
      return 'הבקשה לא בסטטוס הנכון לאישור';
    }
    final trimmed = reviewText.trim();
    if (trimmed.length < minReviewLength) {
      return 'נא לכתוב חוות דעת של לפחות $minReviewLength תווים';
    }

    // ── 3. Anti-fraud checks (FAIL-SAFE: allow on error, log for admin) ──
    // If a query fails (missing index, network, permission), we log the
    // failure but ALLOW the completion. False negatives are preferable to
    // blocking legitimate users. Admin can audit via error_logs.
    try {
      final cooldownBlock = await _checkSameUserCooldown(volunteerId, requesterId);
      if (cooldownBlock != null) return cooldownBlock;
    } catch (e) {
      debugPrint('[CommunityHub] anti-fraud: cooldown check failed (allowing): $e');
    }

    try {
      final reciprocalBlock = await _checkReciprocalBlock(volunteerId, requesterId);
      if (reciprocalBlock != null) return reciprocalBlock;
    } catch (e) {
      debugPrint('[CommunityHub] anti-fraud: reciprocal check failed (allowing): $e');
    }

    try {
      final capBlock = await _checkDailyXpCap(volunteerId);
      if (capBlock != null) return capBlock;
    } catch (e) {
      debugPrint('[CommunityHub] anti-fraud: daily cap check failed (allowing): $e');
    }

    // ── 4. CRITICAL: Mark request as completed FIRST ─────────────────────
    // This is the operation the user cares about. Once this succeeds, the
    // card disappears from the active stream. Secondary writes (XP, badges)
    // are best-effort below.
    final updateData = <String, dynamic>{
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'volunteerReview': trimmed,
    };
    if (thankYouNote != null && thankYouNote.trim().isNotEmpty) {
      updateData['thankYouNote'] = thankYouNote.trim();
      updateData['thankYouAuthor'] = requesterName;
    }

    try {
      await docRef.update(updateData);
    } catch (e) {
      debugPrint('[CommunityHub] CRITICAL: status update to completed failed: $e');
      return 'שגיאה בעדכון סטטוס הבקשה. נסה שוב.';
    }

    // ── From here on, the request IS completed. Card will disappear. ─────
    // Any failure below is non-blocking — we return 'ok' or 'ok_partial'
    // so the UI shows success/celebration regardless.

    bool rewardsOk = true;

    // ── 5. Award 3× XP to volunteer (via Cloud Function — bypasses rules) ─
    try {
      await _awardCommunityXp(volunteerId, requestId);
    } catch (e) {
      debugPrint('[CommunityHub] _awardCommunityXp failed (non-blocking): $e');
      rewardsOk = false;
    }

    // ── 6. Update volunteer heart + badges + communityXP (cross-user write) ─
    try {
      await _updateVolunteerProfile(volunteerId);
    } catch (e) {
      debugPrint('[CommunityHub] _updateVolunteerProfile failed (non-blocking): $e');
      rewardsOk = false;
      // Log for admin follow-up
      try {
        await _db.collection('error_logs').add({
          'type': 'community_reward_failure',
          'requestId': requestId,
          'volunteerId': volunteerId,
          'error': e.toString(),
          'timestamp': FieldValue.serverTimestamp(),
          'expireAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 30))),
        });
      } catch (_) {}
    }

    // ── 7. Notify volunteer (non-blocking) ───────────────────────────────
    final notePreview = (thankYouNote != null && thankYouNote.trim().isNotEmpty)
        ? ' "${thankYouNote.trim()}"'
        : '';
    try {
      await _db.collection('notifications').add({
        'userId': volunteerId,
        'title': '🎉 ההתנדבות אושרה — קיבלת +$communityXpReward XP!',
        'body': 'תודה על העזרה!$notePreview קיבלת $communityXpReward XP ותג מתנדב.',
        'type': 'community_completed',
        'relatedUserId': requesterId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CommunityHub] notification write failed (non-critical): $e');
    }

    return rewardsOk ? 'ok' : 'ok_partial';
  }

  /// Called by the REQUESTER to reject the pending_confirmation
  /// and return the task to in_progress ("Not Yet" button).
  ///
  /// Returns null on success, or a Hebrew error string on failure.
  static Future<String?> rejectCompletion({
    required String requestId,
    required String requesterId,
  }) async {
    try {
      final docRef = _db.collection('community_requests').doc(requestId);
      final snap = await docRef.get();
      if (!snap.exists) return 'הבקשה לא נמצאה';

      final data = snap.data() ?? {};
      final docRequesterId = data['requesterId'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      final volunteerId = data['volunteerId'] as String? ?? '';
      final title = data['title'] as String? ?? '';

      if (requesterId != docRequesterId) {
        return 'רק מי שביקש את העזרה יכול לדחות';
      }
      if (status != 'pending_confirmation') {
        return 'הבקשה לא בסטטוס ממתין לאישור';
      }

      await docRef.update({
        'status': 'in_progress',
        'markedDoneAt': FieldValue.delete(),
      });

      // Notify volunteer
      if (volunteerId.isNotEmpty) {
        await _db.collection('notifications').add({
          'userId': volunteerId,
          'title': '🔄 הפונה ציין/ה שהעזרה עוד לא הושלמה',
          'body': 'הבקשה "$title" חזרה לסטטוס פעיל',
          'type': 'community_not_yet',
          'relatedUserId': requesterId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return null;
    } catch (e) {
      debugPrint('[CommunityHub] rejectCompletion error: $e');
      return 'שגיאה בדחיית האישור';
    }
  }

  // ── Cancel Request ─────────────────────────────────────────────────────────

  /// Cancel a request (by the requester). Allowed from: open, accepted, in_progress.
  /// NOT allowed from pending_confirmation or completed.
  static Future<String?> cancelRequest(String requestId, String userId) async {
    final doc = await _db.collection('community_requests').doc(requestId).get();
    final data = doc.data() ?? {};
    if (data['requesterId'] != userId) return 'אין הרשאה לבטל בקשה זו';

    final status = data['status'] as String? ?? '';
    if (status == 'pending_confirmation') {
      return 'לא ניתן לבטל — המתנדב/ת סימנ/ה סיום. אשר/י או דחה/י.';
    }
    if (status == 'completed' || status == 'cancelled') {
      return 'הבקשה כבר ${status == 'completed' ? 'הושלמה' : 'בוטלה'}';
    }

    final volunteerId = data['volunteerId'] as String?;

    await _db.collection('community_requests').doc(requestId).update({
      'status': 'cancelled',
    });

    // Notify volunteer if already claimed
    if (volunteerId != null && volunteerId.isNotEmpty) {
      await _db.collection('notifications').add({
        'userId': volunteerId,
        'title': 'בקשת העזרה בוטלה',
        'body': 'הבקשה "${data['title']}" בוטלה על ידי הפונה.',
        'type': 'community_cancelled',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return null;
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Streams open community requests, optionally filtered by requester type.
  static Stream<QuerySnapshot> streamOpenRequests({String? requesterType}) {
    Query query = _db
        .collection('community_requests')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(50);

    if (requesterType != null && requesterType.isNotEmpty) {
      query = _db
          .collection('community_requests')
          .where('status', isEqualTo: 'open')
          .where('requesterType', isEqualTo: requesterType)
          .orderBy('createdAt', descending: true)
          .limit(50);
    }

    return query.snapshots();
  }

  /// Streams requests created by this user (as requester).
  static Stream<QuerySnapshot> streamMyRequests(String userId) {
    return _db
        .collection('community_requests')
        .where('requesterId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Streams active requests where this user is the REQUESTER
  /// (accepted, in_progress, pending_confirmation).
  /// Used in the "Request Help" tab to show the requester what needs action.
  static Stream<QuerySnapshot> streamMyActiveRequests(String userId) {
    return _db
        .collection('community_requests')
        .where('requesterId', isEqualTo: userId)
        .where('status', whereIn: activeStatuses.toList())
        .limit(20)
        .snapshots();
  }

  /// Streams active tasks for this volunteer (accepted, in_progress, pending_confirmation).
  static Stream<QuerySnapshot> streamMyVolunteerTasks(String userId) {
    return _db
        .collection('community_requests')
        .where('volunteerId', isEqualTo: userId)
        .where('status', whereIn: activeStatuses.toList())
        .limit(20)
        .snapshots();
  }

  /// Streams completed community tasks for a volunteer (for Community Impact profile section).
  /// Returns docs with thankYouNote to display on the volunteer's profile.
  static Stream<QuerySnapshot> streamCommunityImpact(String userId) {
    return _db
        .collection('community_requests')
        .where('volunteerId', isEqualTo: userId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(20)
        .snapshots();
  }

  /// Counts total completed community tasks for a user (as volunteer).
  static Future<int> completedTaskCount(String userId) async {
    final snap = await _db
        .collection('community_requests')
        .where('volunteerId', isEqualTo: userId)
        .where('status', isEqualTo: 'completed')
        .limit(100)
        .get();
    return snap.size;
  }

  // ── Badge & Heart Helpers ──────────────────────────────────────────────────

  /// Returns true if the user has the permanent volunteer heart.
  static bool hasVolunteerHeart(Map<String, dynamic> userData) {
    return userData['volunteerHeart'] == true;
  }

  /// Returns the highest badge earned from the list.
  static String? getHighestBadge(List<dynamic>? badges) {
    if (badges == null || badges.isEmpty) return null;
    if (badges.contains('angel')) return 'angel';
    if (badges.contains('pillar')) return 'pillar';
    if (badges.contains('starter')) return 'starter';
    return null;
  }

  /// Hebrew label for a badge.
  static String badgeLabelHe(String badge) {
    switch (badge) {
      case 'starter':
        return 'מתחיל';
      case 'pillar':
        return 'עמוד תווך';
      case 'angel':
        return 'מלאך';
      default:
        return badge;
    }
  }

  /// Icon for a badge.
  static IconData badgeIcon(String badge) {
    switch (badge) {
      case 'starter':
        return Icons.favorite_rounded;
      case 'pillar':
        return Icons.shield_rounded;
      case 'angel':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.favorite_rounded;
    }
  }

  /// Color for a badge.
  static Color badgeColor(String badge) {
    switch (badge) {
      case 'starter':
        return const Color(0xFFEC4899);
      case 'pillar':
        return const Color(0xFF6366F1);
      case 'angel':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF10B981);
    }
  }

  /// Hebrew label for request status.
  static String statusLabelHe(String status, {String? volunteerName}) {
    switch (status) {
      case 'open':
        return 'ממתין למתנדב';
      case 'accepted':
        return volunteerName != null
            ? '$volunteerName רוצה לעזור — אשר/י'
            : 'ממתין לאישור התחלה';
      case 'in_progress':
        return volunteerName != null ? 'בטיפול — $volunteerName' : 'בטיפול';
      case 'pending_confirmation':
        return volunteerName != null
            ? '$volunteerName סיים/ה — ממתין לאישורך'
            : 'ממתין לאישור סיום';
      case 'completed':
        return 'הושלם';
      case 'cancelled':
        return 'בוטל';
      default:
        return status;
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────────────

  /// Awards 3× XP to the volunteer via Cloud Function (3 calls × 150).
  /// CF calls use Admin SDK so they bypass Firestore rules.
  static Future<void> _awardCommunityXp(
      String volunteerId, String requestId) async {
    // Call the volunteer_task event 3 times for 3× XP (150 × 3 = 450).
    // Each call is atomic within the CF transaction.
    for (int i = 0; i < 3; i++) {
      await GamificationService.awardXP(volunteerId, 'volunteer_task');
    }
  }

  /// Updates volunteer's heart, badges, community XP, and task count
  /// in a SINGLE Firestore write. All 6 fields must be in the
  /// `onlyFields()` allowlist in firestore.rules (volunteer badge rule).
  static Future<void> _updateVolunteerProfile(String volunteerId) async {
    final count = await completedTaskCount(volunteerId);

    final badges = <String>[];
    if (count >= starterThreshold) badges.add('starter');
    if (count >= pillarThreshold) badges.add('pillar');
    if (count >= angelThreshold) badges.add('angel');

    await _db.collection('users').doc(volunteerId).update({
      'volunteerHeart': true,
      'communityBadges': badges,
      'communityXP': FieldValue.increment(communityXpReward),
      'lastVolunteerTaskAt': FieldValue.serverTimestamp(),
      'volunteerTaskCount': FieldValue.increment(1),
      'hasActiveVolunteerBadge': true,
    });
  }

  /// Notifies matching online volunteers about a new request.
  static Future<void> _notifyVolunteers(
    String category,
    String requesterId,
    String title,
    String urgency,
  ) async {
    final volunteersSnap = await _db
        .collection('users')
        .where('isVolunteer', isEqualTo: true)
        .where('isOnline', isEqualTo: true)
        .limit(30)
        .get();

    int count = 0;
    for (final doc in volunteersSnap.docs) {
      if (doc.id == requesterId) continue; // skip self
      if (count >= 20) break; // max notifications

      await _db.collection('notifications').add({
        'userId': doc.id,
        'title': urgency == 'high'
            ? '🚨 בקשת עזרה דחופה!'
            : '🤝 בקשת עזרה חדשה!',
        'body': '$title — תוכל/י לעזור?',
        'type': 'community_request',
        'relatedUserId': requesterId,
        'category': category,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
    }
  }

  // ── Anti-Fraud Checks ──────────────────────────────────────────────────────

  static Future<String?> _checkSameUserCooldown(
      String volunteerId, String requesterId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: sameUserCooldownDays)),
    );
    final snap = await _db
        .collection('community_requests')
        .where('volunteerId', isEqualTo: volunteerId)
        .where('requesterId', isEqualTo: requesterId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return 'כבר עזרת לאדם הזה ב-30 הימים האחרונים. נסה שוב מאוחר יותר.';
    }
    return null;
  }

  static Future<String?> _checkReciprocalBlock(
      String volunteerId, String requesterId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: reciprocalBlockDays)),
    );
    // Reverse direction: requesterId helped volunteerId recently
    final snap = await _db
        .collection('community_requests')
        .where('volunteerId', isEqualTo: requesterId)
        .where('requesterId', isEqualTo: volunteerId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return 'לא ניתן לאשר — עזרה הדדית אינה מותרת תוך 30 יום.';
    }
    return null;
  }

  static Future<String?> _checkDailyXpCap(String volunteerId) async {
    final midnight = DateTime.now();
    final todayStart =
        DateTime(midnight.year, midnight.month, midnight.day);
    final cutoff = Timestamp.fromDate(todayStart);

    final snap = await _db
        .collection('community_requests')
        .where('volunteerId', isEqualTo: volunteerId)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: cutoff)
        .limit(10)
        .get();

    final todayXp = snap.size * communityXpReward;
    if (todayXp >= dailyCommunityXpCap) {
      return 'הגעת למכסת ה-XP היומית ($dailyCommunityXpCap XP). נסה שוב מחר.';
    }
    return null;
  }
}
