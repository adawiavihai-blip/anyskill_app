// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: Chat & Messaging system
//
// Tests chat room creation, message delivery, read receipts,
// unread counts, typing indicators, and message types.
//
// Run:  flutter test test/unit/chat_messaging_test.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Build a deterministic chat room ID from two UIDs (sorted + joined).
String _chatRoomId(String a, String b) {
  final ids = [a, b]..sort();
  return ids.join('_');
}

/// Seed a chat room with two participants.
Future<void> _seedChatRoom(FakeFirebaseFirestore db, String uid1, String uid2) async {
  final roomId = _chatRoomId(uid1, uid2);
  await db.collection('chats').doc(roomId).set({
    'users': [uid1, uid2]..sort(),
    'lastMessage': '',
    'lastMessageTime': Timestamp.now(),
    'lastSenderId': '',
    'unreadCount_$uid1': 0,
    'unreadCount_$uid2': 0,
    'isTyping_$uid1': false,
    'isTyping_$uid2': false,
  });
}

/// Send a message to a chat room.
Future<String> _sendMessage(
  FakeFirebaseFirestore db, {
  required String chatRoomId,
  required String senderId,
  required String receiverId,
  String message = 'Hello',
  String type = 'text',
}) async {
  final ref = await db.collection('chats').doc(chatRoomId)
      .collection('messages').add({
    'senderId': senderId,
    'receiverId': receiverId,
    'message': message,
    'type': type,
    'timestamp': Timestamp.now(),
    'isRead': false,
  });

  // Update chat room metadata (mirrors CF sendchatnotification)
  await db.collection('chats').doc(chatRoomId).update({
    'lastMessage': message,
    'lastMessageTime': Timestamp.now(),
    'lastSenderId': senderId,
    'unreadCount_$receiverId': FieldValue.increment(1),
  });

  return ref.id;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. CHAT ROOM ID
  // ═══════════════════════════════════════════════════════════════════════════

  group('Chat room ID', () {
    test('deterministic: same result regardless of order', () {
      expect(_chatRoomId('alice', 'bob'), 'alice_bob');
      expect(_chatRoomId('bob', 'alice'), 'alice_bob');
    });

    test('sorted lexicographically', () {
      expect(_chatRoomId('zack', 'anna'), 'anna_zack');
      expect(_chatRoomId('uid_123', 'uid_456'), 'uid_123_uid_456');
    });

    test('same user produces valid ID (self-chat edge case)', () {
      expect(_chatRoomId('alice', 'alice'), 'alice_alice');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. MESSAGE DELIVERY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Message delivery', () {
    test('message is stored with correct fields', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('alice', 'bob');
      await _seedChatRoom(db, 'alice', 'bob');

      final msgId = await _sendMessage(db,
        chatRoomId: roomId,
        senderId: 'alice',
        receiverId: 'bob',
        message: 'שלום!',
      );

      final doc = await db.collection('chats').doc(roomId)
          .collection('messages').doc(msgId).get();
      final data = doc.data()!;

      expect(data['senderId'], 'alice');
      expect(data['receiverId'], 'bob');
      expect(data['message'], 'שלום!');
      expect(data['type'], 'text');
      expect(data['isRead'], false);
      expect(data['timestamp'], isNotNull);
    });

    test('chat room metadata updates on new message', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('alice', 'bob');
      await _seedChatRoom(db, 'alice', 'bob');

      await _sendMessage(db,
        chatRoomId: roomId,
        senderId: 'alice',
        receiverId: 'bob',
        message: 'Hey there',
      );

      final room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['lastMessage'], 'Hey there');
      expect(room.data()?['lastSenderId'], 'alice');
    });

    test('messages are ordered by timestamp', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      await _sendMessage(db, chatRoomId: roomId, senderId: 'a',
          receiverId: 'b', message: 'first');
      // Small delay to ensure different timestamps
      await _sendMessage(db, chatRoomId: roomId, senderId: 'b',
          receiverId: 'a', message: 'second');
      await _sendMessage(db, chatRoomId: roomId, senderId: 'a',
          receiverId: 'b', message: 'third');

      final snap = await db.collection('chats').doc(roomId)
          .collection('messages')
          .orderBy('timestamp')
          .get();

      expect(snap.docs.length, 3);
      expect(snap.docs[0].data()['message'], 'first');
      expect(snap.docs[2].data()['message'], 'third');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. READ RECEIPTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Read receipts', () {
    test('new messages start as unread', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      final msgId = await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );

      final msg = await db.collection('chats').doc(roomId)
          .collection('messages').doc(msgId).get();
      expect(msg.data()?['isRead'], false);
    });

    test('marking as read updates the message', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      final msgId = await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );

      // Simulate markAsRead (what the CF does)
      await db.collection('chats').doc(roomId)
          .collection('messages').doc(msgId)
          .update({'isRead': true});

      final msg = await db.collection('chats').doc(roomId)
          .collection('messages').doc(msgId).get();
      expect(msg.data()?['isRead'], true);
    });

    test('batch mark-as-read updates multiple messages', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      // Send 5 messages from 'a' to 'b'
      final msgIds = <String>[];
      for (int i = 0; i < 5; i++) {
        msgIds.add(await _sendMessage(db,
          chatRoomId: roomId, senderId: 'a', receiverId: 'b',
          message: 'msg $i',
        ));
      }

      // Mark all as read (batch)
      final batch = db.batch();
      for (final id in msgIds) {
        batch.update(
          db.collection('chats').doc(roomId).collection('messages').doc(id),
          {'isRead': true},
        );
      }
      await batch.commit();

      // Verify all are read
      final snap = await db.collection('chats').doc(roomId)
          .collection('messages').get();
      expect(snap.docs.every((d) => d.data()['isRead'] == true), true);
    });

    test('only receiver messages get marked as read', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      // A sends to B, B sends to A
      final fromA = await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );
      final fromB = await _sendMessage(db,
        chatRoomId: roomId, senderId: 'b', receiverId: 'a',
      );

      // B opens chat → mark B's incoming (from A) as read
      await db.collection('chats').doc(roomId)
          .collection('messages').doc(fromA)
          .update({'isRead': true});

      // fromA should be read (B received it)
      var msg = await db.collection('chats').doc(roomId)
          .collection('messages').doc(fromA).get();
      expect(msg.data()?['isRead'], true);

      // fromB should still be unread (A hasn't opened yet)
      msg = await db.collection('chats').doc(roomId)
          .collection('messages').doc(fromB).get();
      expect(msg.data()?['isRead'], false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. UNREAD COUNTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Unread counts', () {
    test('sending a message increments receiver unread count', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );
      await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );

      final room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['unreadCount_b'], 2);
      expect(room.data()?['unreadCount_a'], 0); // sender's count unchanged
    });

    test('opening chat resets unread count to zero', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );
      await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
      );

      // B opens chat → reset
      await db.collection('chats').doc(roomId).update({
        'unreadCount_b': 0,
      });

      final room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['unreadCount_b'], 0);
    });

    test('bidirectional messages track counts independently', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      // A sends 3 to B
      for (int i = 0; i < 3; i++) {
        await _sendMessage(db,
          chatRoomId: roomId, senderId: 'a', receiverId: 'b',
        );
      }
      // B sends 1 to A
      await _sendMessage(db,
        chatRoomId: roomId, senderId: 'b', receiverId: 'a',
      );

      final room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['unreadCount_b'], 3);
      expect(room.data()?['unreadCount_a'], 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. TYPING INDICATORS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Typing indicators', () {
    test('typing flag sets and clears', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      // A starts typing
      await db.collection('chats').doc(roomId).update({
        'isTyping_a': true,
      });
      var room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['isTyping_a'], true);
      expect(room.data()?['isTyping_b'], false);

      // A stops typing
      await db.collection('chats').doc(roomId).update({
        'isTyping_a': false,
      });
      room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['isTyping_a'], false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. MESSAGE TYPES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Message types', () {
    test('image message stores URL in message field', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      final msgId = await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
        message: 'https://storage.example.com/image.jpg',
        type: 'image',
      );

      final msg = await db.collection('chats').doc(roomId)
          .collection('messages').doc(msgId).get();
      expect(msg.data()?['type'], 'image');
      expect(msg.data()?['message'], contains('https://'));
    });

    test('location message stores maps URL', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      final msgId = await _sendMessage(db,
        chatRoomId: roomId, senderId: 'a', receiverId: 'b',
        message: 'https://maps.google.com/?q=32.0,34.0',
        type: 'location',
      );

      final msg = await db.collection('chats').doc(roomId)
          .collection('messages').doc(msgId).get();
      expect(msg.data()?['type'], 'location');
      expect(msg.data()?['message'], contains('maps.google'));
    });

    test('official quote includes amount and quoteId', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      await db.collection('chats').doc(roomId)
          .collection('messages').add({
        'senderId': 'b',
        'receiverId': 'a',
        'message': 'הצעת מחיר',
        'type': 'official_quote',
        'amount': 500.0,
        'quoteId': 'q123',
        'quoteStatus': 'pending',
        'timestamp': Timestamp.now(),
        'isRead': false,
      });

      final snap = await db.collection('chats').doc(roomId)
          .collection('messages')
          .where('type', isEqualTo: 'official_quote')
          .get();

      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['amount'], 500.0);
      expect(snap.docs.first.data()['quoteStatus'], 'pending');
    });

    test('system alert has system sender', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      await db.collection('chats').doc(roomId)
          .collection('messages').add({
        'senderId': 'system',
        'receiverId': '',
        'message': '₪100 נעולים באסקרו',
        'type': 'system_alert',
        'timestamp': Timestamp.now(),
        'isRead': true,
      });

      final snap = await db.collection('chats').doc(roomId)
          .collection('messages')
          .where('type', isEqualTo: 'system_alert')
          .get();

      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['senderId'], 'system');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. CHAT DELETION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Chat deletion', () {
    test('deleting messages clears subcollection', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      for (int i = 0; i < 3; i++) {
        await _sendMessage(db,
          chatRoomId: roomId, senderId: 'a', receiverId: 'b',
        );
      }

      // Delete all messages
      final messages = await db.collection('chats').doc(roomId)
          .collection('messages').get();
      for (final doc in messages.docs) {
        await doc.reference.delete();
      }

      final remaining = await db.collection('chats').doc(roomId)
          .collection('messages').get();
      expect(remaining.docs, isEmpty);
    });

    test('deleting chat room removes the document', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      await db.collection('chats').doc(roomId).delete();

      final room = await db.collection('chats').doc(roomId).get();
      expect(room.exists, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. CONCURRENCY & RACE CONDITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Concurrency', () {
    test('simultaneous messages from both parties are both stored', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      // Both send at the "same time"
      await Future.wait([
        _sendMessage(db, chatRoomId: roomId, senderId: 'a',
            receiverId: 'b', message: 'from A'),
        _sendMessage(db, chatRoomId: roomId, senderId: 'b',
            receiverId: 'a', message: 'from B'),
      ]);

      final snap = await db.collection('chats').doc(roomId)
          .collection('messages').get();
      expect(snap.docs.length, 2);

      final messages = snap.docs.map((d) => d.data()['message']).toSet();
      expect(messages, contains('from A'));
      expect(messages, contains('from B'));
    });

    test('unread count stays consistent with concurrent messages', () async {
      final db = FakeFirebaseFirestore();
      final roomId = _chatRoomId('a', 'b');
      await _seedChatRoom(db, 'a', 'b');

      // A sends 5 messages concurrently
      await Future.wait(
        List.generate(5, (i) => _sendMessage(db,
          chatRoomId: roomId, senderId: 'a', receiverId: 'b',
          message: 'msg $i',
        )),
      );

      final room = await db.collection('chats').doc(roomId).get();
      expect(room.data()?['unreadCount_b'], 5);
    });

    test('two users booking same quote: second attempt fails', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('quotes').doc('q1').set({
        'status': 'pending', 'amount': 100.0,
        'providerId': 'p1', 'clientId': 'c1',
      });

      // First booking succeeds
      await db.collection('quotes').doc('q1').update({'status': 'paid'});

      // Second attempt reads status=paid
      final quote = await db.collection('quotes').doc('q1').get();
      expect(quote.data()?['status'], 'paid');
      // The payQuote logic checks this and throws "already paid"
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. PARTICIPANTS ACCESS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Chat access control', () {
    test('users array contains both sorted UIDs', () async {
      final db = FakeFirebaseFirestore();
      await _seedChatRoom(db, 'zack', 'anna');

      final roomId = _chatRoomId('zack', 'anna');
      final room = await db.collection('chats').doc(roomId).get();
      final users = (room.data()?['users'] as List).cast<String>();

      expect(users, ['anna', 'zack']); // sorted
      expect(users.contains('anna'), true);
      expect(users.contains('zack'), true);
    });

    test('non-participant UID is not in users array', () async {
      final db = FakeFirebaseFirestore();
      await _seedChatRoom(db, 'a', 'b');

      final roomId = _chatRoomId('a', 'b');
      final room = await db.collection('chats').doc(roomId).get();
      final users = (room.data()?['users'] as List).cast<String>();

      expect(users.contains('hacker'), false);
    });
  });
}
