import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Chat service — v9.6.1 DETERMINISTIC & RESILIENT
///
/// IRON RULES:
///   1. Room ID = sorted UIDs joined by '_'. Deterministic on every platform.
///   2. ensureRoom creates the parent doc with BOTH users. Always.
///   3. sendMessage writes ONLY to messages subcollection.
///   4. The CF handles all parent doc metadata (lastMessage, unreadCount).
///   5. Every error is logged with the actual Firebase error code.
class ChatService {
  static final _functions = FirebaseFunctions.instance;

  /// Deterministic room ID — guaranteed same result on Web, iOS, Android.
  /// MUST be used everywhere instead of manual sort+join.
  static String getRoomId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  // Tracks which chat rooms have been confirmed to exist this session.
  static final Set<String> _confirmed = {};

  /// Creates the parent chat doc with `users` array containing BOTH UIDs.
  /// Uses set(merge:true) — idempotent, safe to call multiple times.
  ///
  /// CRITICAL: This MUST complete before any message write, because the
  /// Firestore rules for messages/{msgId} do get() on the parent doc
  /// to check if auth.uid is in the users array.
  static Future<bool> ensureRoom({
    required String chatRoomId,
    required String userId,
    required String otherUserId,
  }) async {
    if (_confirmed.contains(chatRoomId)) return true;

    // Guard: empty UIDs = broken auth state, will always fail rules
    if (userId.isEmpty || otherUserId.isEmpty) {
      debugPrint('[ChatService] ensureRoom BLOCKED: empty UID '
          '(userId=$userId, otherUserId=$otherUserId)');
      return false;
    }

    try {
      final ids = [userId, otherUserId]..sort();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .set({
        'users': ids, // SORTED — matches the room ID derivation
      }, SetOptions(merge: true));
      _confirmed.add(chatRoomId);
      debugPrint('[ChatService] ensureRoom OK: room=$chatRoomId');
      return true;
    } catch (e) {
      debugPrint('[ChatService] ensureRoom FAILED: $e');
      debugPrint('  room=$chatRoomId userId=$userId otherUserId=$otherUserId');
      return false;
    }
  }

  /// Sends a chat message. Returns `true` on success, `false` on failure.
  ///
  /// Step 1: Ensure parent doc exists (skipped if already confirmed).
  /// Step 2: Write message to subcollection (triggers CF for metadata).
  ///
  /// On any error, logs the full Firebase error code for debugging.
  static Future<bool> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    required String type,
  }) async {
    if (content.trim().isEmpty) return false;

    // Guard: empty UIDs
    if (senderId.isEmpty || receiverId.isEmpty) {
      debugPrint('[ChatService] sendMessage BLOCKED: empty UID');
      return false;
    }

    // Step 1: ensure parent doc (idempotent, skips if _confirmed)
    final ready = await ensureRoom(
      chatRoomId: chatRoomId,
      userId: senderId,
      otherUserId: receiverId,
    );
    if (!ready) {
      debugPrint('[ChatService] sendMessage ABORTED: ensureRoom failed');
      return false;
    }

    // Step 2: write message — retry once on transient errors
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 150));
          debugPrint('[ChatService] sendMessage retry #$attempt');
        }

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': senderId,
          'receiverId': receiverId,
          'message': content,
          'type': type,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });

        return true;
      } catch (e) {
        debugPrint('[ChatService] sendMessage ERROR (attempt $attempt): $e');
        debugPrint('  room=$chatRoomId sender=$senderId receiver=$receiverId');

        // If permission-denied, the parent doc may be corrupted/missing.
        // Clear _confirmed so next attempt re-creates it.
        final errStr = e.toString();
        if (errStr.contains('permission-denied') ||
            errStr.contains('PERMISSION_DENIED')) {
          debugPrint('[ChatService] Permission denied — clearing room cache');
          _confirmed.remove(chatRoomId);
        }

        // Retry on transient errors only
        if (attempt == 0 &&
            (errStr.contains('INTERNAL ASSERTION') ||
             errStr.contains('unavailable') ||
             errStr.contains('deadline-exceeded'))) {
          continue;
        }

        return false;
      }
    }
    return false;
  }

  /// Marks messages as read via Cloud Function (Admin SDK).
  static Future<void> markMessagesAsRead(
      String chatRoomId, String userId) async {
    try {
      await _functions
          .httpsCallable('processMarkAsRead')
          .call({'chatRoomId': chatRoomId, 'userId': userId});
    } catch (e) {
      debugPrint('[ChatService] markMessagesAsRead error: $e');
    }
  }

  /// Message stream (50 most recent, newest first).
  static Stream<QuerySnapshot> getMessagesStream(String chatRoomId,
      {int limit = 50}) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Unread count stream for a specific user in a specific chat.
  static Stream<int> getUnreadCountStream(String chatRoomId, String userId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return 0;
      final data = snap.data() ?? {};
      final raw = data['unreadCount_$userId'];
      return (raw is num) ? raw.toInt() : 0;
    });
  }
}
