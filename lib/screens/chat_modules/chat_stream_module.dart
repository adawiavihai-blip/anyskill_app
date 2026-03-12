import 'package:cloud_firestore/cloud_firestore.dart';

class ChatStreamModule {
  // מחזיר את זרם ההודעות של חדר ספציפי
  static Stream<QuerySnapshot> getMessagesStream(String chatRoomId, {int limit = 50}) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  // מחזיר את זרם סטטוס העבודה (Jobs)
  static Stream<QuerySnapshot> getJobStatusStream(String chatRoomId) {
    return FirebaseFirestore.instance
        .collection('jobs')
        .where('chatRoomId', isEqualTo: chatRoomId)
        .snapshots();
  }
}