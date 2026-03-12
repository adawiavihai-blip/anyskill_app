import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChatLogicModule {
  // --- שליחת הודעה (עם עדכון Batch) ---
  static Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    required String type,
  }) async {
    if (content.trim().isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      
      // 1. יצירת רפרנס להודעה חדשה
      DocumentReference messageRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .doc();

      batch.set(messageRef, {
        'senderId': senderId,
        'receiverId': receiverId,
        'message': content,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false, // הודעה חדשה תמיד מתחילה כ"לא נקראה"
      });

      // 2. עדכון ה"שיחה" (Last Message ומונה הודעות למקבל)
      DocumentReference chatRef = FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
      batch.set(chatRef, {
        'lastMessage': type == 'text' ? content : 'שלח/ה $type',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount_$receiverId': FieldValue.increment(1),
        'lastSenderId': senderId,
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      debugPrint("QA Error - Send Message: $e");
    }
  }

  // --- QA: מנגנון ה-V הכחול (סימון הודעות כנקראו) ---
  // פונקציה זו עוברת על כל ההודעות שהמשתמש הנוכחי קיבל ומסמנת אותן כנקראו
  static Future<void> markMessagesAsRead(String chatRoomId, String currentUserId) async {
    try {
      // שליפת הודעות שלא נקראו שבהן אני המקבל
      final unreadQuery = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .where('receiverId', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      if (unreadQuery.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in unreadQuery.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      // איפוס המונה בשיחה עצמה
      DocumentReference chatRef = FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
      batch.update(chatRef, {'unreadCount_$currentUserId': 0});

      await batch.commit();
      debugPrint("QA Success: Marked ${unreadQuery.docs.length} messages as read");
    } catch (e) {
      debugPrint("QA Error - Mark As Read: $e");
    }
  }

  // איפוס מונה הודעות (שימוש משני)
  static Future<void> resetUnreadCount(String chatRoomId, String userId) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatRoomId).update({
        'unreadCount_$userId': 0,
      });
    } catch (e) {
      debugPrint("QA Error - Reset Count: $e");
    }
  }
}