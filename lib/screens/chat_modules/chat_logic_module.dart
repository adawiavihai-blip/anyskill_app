import '../../services/chat_service.dart';

class ChatLogicModule {
  // --- שליחת הודעה ---
  // הלקוח כותב רק את מסמך ההודעה. Cloud Function (sendchatnotification)
  // מעדכן את המטאדאטה (lastMessage, unreadCount, shards) בצד השרת.
  /// Returns `true` on success, `false` on failure.
  static Future<bool> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    required String type,
  }) async {
    return ChatService.sendMessage(
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

  // v9.5.9: Unread reset goes through the CF (markMessagesAsRead).
  // NEVER write to the parent chat doc from the client — it causes
  // AsyncQueue deadlocks with the active snapshot listeners.
  static Future<void> resetUnreadCount(String chatRoomId, String userId) async {
    await ChatService.markMessagesAsRead(chatRoomId, userId);
  }
}
