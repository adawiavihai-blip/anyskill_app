import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// שירות הצ'אט — שכבת הגישה לנתונים עבור כל פעולות הצ'אט
///
/// עיקרון מרכזי: הלקוח כותב רק את מסמך ההודעה.
/// Cloud Function (sendchatnotification) מעדכן את כל המטאדאטה:
///   • lastMessage, lastMessageTime, lastSenderId
///   • unreadCount_$uid (שדה מדנורמלי)
///   • unread_shards/{uid}_{0..4} (distributed counter)
///
/// [markMessagesAsRead] מבוצע ע"י Callable Function (processMarkAsRead)
/// דרך Admin SDK — ללא מגבלות rate של הלקוח.
class ChatService {
  static final _db = FirebaseFirestore.instance;
  static final _functions = FirebaseFunctions.instance;

  // ── שליחת הודעה — כתיבת מסמך ההודעה בלבד ──────────────────────────────────
  // המטאדאטה (lastMessage, unreadCount) מתעדכנת ע"י sendchatnotification CF
  static Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    required String type,
  }) async {
    if (content.trim().isEmpty) return;

    try {
      await _db
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': senderId,
        'receiverId': receiverId,
        'message': content, // שם השדה 'message' (לא 'text') לפי קונבנציית הפרויקט
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint("ChatService Error - sendMessage: $e");
    }
  }

  // ── סימון הודעות כנקראו — דרך Callable Function ─────────────────────────────
  // Admin SDK: ללא rate limits, מאפס shards + שדה מדנורמלי + isRead על ההודעות
  // שגיאה לא קריטית — ההודעות יסומנו בקריאה הבאה
  static Future<void> markMessagesAsRead(String chatRoomId, String userId) async {
    try {
      await _functions
          .httpsCallable('processMarkAsRead')
          .call({'chatRoomId': chatRoomId, 'userId': userId});
    } catch (e) {
      debugPrint("ChatService Error - markMessagesAsRead: $e");
    }
  }

  // ── זרם הודעות (50 הודעות אחרונות, מהחדשה לישנה) ───────────────────────────
  static Stream<QuerySnapshot> getMessagesStream(String chatRoomId,
      {int limit = 50}) {
    return _db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── זרם מונה הודעות שלא נקראו (מהשדה המדנורמלי — ללא קריאת shards) ─────────
  // נתיב הקריאה לא השתנה — chat_list_screen ו-home_screen ממשיכים לעבוד ישירות
  static Stream<int> getUnreadCountStream(String chatRoomId, String userId) {
    return _db
        .collection('chats')
        .doc(chatRoomId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return 0;
      final data = snap.data() ?? {};
      return (data['unreadCount_$userId'] as int?) ?? 0;
    });
  }
}
