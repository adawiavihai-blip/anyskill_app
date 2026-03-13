import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/chat_service.dart';

class ChatLogicModule {
  // --- שליחת הודעה ---
  // הלקוח כותב רק את מסמך ההודעה. Cloud Function (sendchatnotification)
  // מעדכן את המטאדאטה (lastMessage, unreadCount, shards) בצד השרת.
  static Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    required String type,
  }) async {
    await ChatService.sendMessage(
      chatRoomId: chatRoomId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      type: type,
    );
  }

  // --- QA: מנגנון ה-V הכחול (סימון הודעות כנקראו) ---
  // הועבר ל-Callable Function (processMarkAsRead) — Admin SDK, ללא rate limits.
  // מאפס shards + שדה מדנורמלי + isRead על עד 100 הודעות בבת אחת.
  static Future<void> markMessagesAsRead(String chatRoomId, String currentUserId) async {
    await ChatService.markMessagesAsRead(chatRoomId, currentUserId);
  }

  // איפוס מונה הודעות (שימוש משני / fallback)
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
