import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// יבוא המודולים
import 'chat_modules/location_module.dart';
import 'chat_modules/image_module.dart';

import 'chat_modules/payment_module.dart';
import 'chat_modules/chat_ui_helper.dart';
import 'chat_modules/chat_logic_module.dart';
import 'chat_modules/safety_module.dart';    
import 'chat_modules/chat_stream_module.dart'; 

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? currentUserName; 

  const ChatScreen({
    super.key, 
    required this.receiverId, 
    required this.receiverName,
    this.currentUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
  late String chatRoomId;
  bool _isUploading = false;
  Timer? _markAsReadDebounce;

  @override
  void initState() {
    super.initState();
    List<String> ids = [currentUserId, widget.receiverId];
    ids.sort();
    chatRoomId = ids.join("_");

    // Reset badge immediately on enter — no debounce, no CF dependency
    FirebaseFirestore.instance.collection('chats').doc(chatRoomId).update({
      'unreadCount_$currentUserId': 0,
    }).catchError((_) {});

    _handleMarkAsRead(); // debounced CF call — marks individual messages as isRead: true
  }

  @override
  void dispose() {
    _markAsReadDebounce?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  // --- 🔥 QA: שליפת השם המלא המדויק מה-Database (FirstName + LastName) ---
  Future<String> _getCurrentUserName() async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        
        String fullName = (data['name'] ?? "").toString().trim();

        if (fullName.isNotEmpty) return fullName;
      }
    } catch (e) {
      debugPrint("QA Error fetching name: $e");
    }
    
    // גיבוי אחרון אם ה-DB לא זמין
    return widget.currentUserName ?? "לקוח";
  }

  void _handleMarkAsRead() {
    // דיבאונס — מונע קריאות חוזרות לכל הודעה נכנסת
    // Callable Function תופעל פעם אחת לאחר שנייה של דממה
    _markAsReadDebounce?.cancel();
    _markAsReadDebounce = Timer(const Duration(seconds: 1), () {
      ChatLogicModule.markMessagesAsRead(chatRoomId, currentUserId);
    });
  }

  Future<void> _send(String content, String type) async {
    if (!await SafetyModule.hasInternet()) {
      if (mounted) SafetyModule.showError(context, "אין חיבור לאינטרנט.");
      return;
    }

    ChatLogicModule.sendMessage(
      chatRoomId: chatRoomId,
      senderId: currentUserId,
      receiverId: widget.receiverId,
      content: content,
      type: type,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(widget.receiverName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          _buildJobStatusBanner(),
          Expanded(child: _buildMessagesList()),
          if (_isUploading) const LinearProgressIndicator(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildJobStatusBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: ChatStreamModule.getJobStatusStream(chatRoomId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();

        var jobDoc = snapshot.data!.docs.first;
        var jobData = jobDoc.data() as Map<String, dynamic>;
        String status = jobData['status'] ?? "";

        if (status == 'completed' || status == 'הושלם') return const SizedBox.shrink();

        bool isExpert = jobData['expertId'] == currentUserId;

        // ── Expert sees "mark done" when job is in escrow ──────────────────
        if (isExpert && status == 'paid_escrow') {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Icon(Icons.security, color: Colors.amber[900]),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text("התשלום מוגן בנאמנות — סמן כשתסיים",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('jobs')
                        .doc(jobDoc.id)
                        .update({
                      'status': 'expert_completed',
                      'expertCompletedAt': FieldValue.serverTimestamp(),
                    });
                    await FirebaseFirestore.instance
                        .collection('chats')
                        .doc(chatRoomId)
                        .collection('messages')
                        .add({
                      'senderId': 'system',
                      'message':
                          '✅ המומחה סיים את העבודה! לחץ על "אשר ושחרר" כדי לשחרר את התשלום.',
                      'type': 'text',
                      'timestamp': FieldValue.serverTimestamp(),
                    });
                  },
                  child: const Text("סיימתי",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          );
        }

        // ── Customer sees "release" only after expert marks done ───────────
        if (!isExpert && status == 'expert_completed') {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text("המומחה סיים! אשר לשחרור התשלום.",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (c) => const Center(
                          child: CircularProgressIndicator(color: Colors.white)),
                    );

                    String realName = await _getCurrentUserName();

                    bool success = await PaymentModule.releaseEscrowFunds(
                      jobId: jobDoc.id,
                      expertId: jobData['expertId'] ?? widget.receiverId,
                      expertName: widget.receiverName,
                      customerName: realName,
                      totalAmount: (jobData['totalAmount'] ??
                              jobData['totalPaidByCustomer'] ?? 0.0)
                          .toDouble(),
                    );

                    if (mounted) navigator.pop();

                    if (success && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text("התשלום שוחרר בהצלחה!"),
                            backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text("אשר ושחרר",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          );
        }

        // ── Neutral banner for any other active status ─────────────────────
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Icon(Icons.security, color: Colors.amber[900]),
              const SizedBox(width: 10),
              const Expanded(
                child: Text("התשלום מוגן בחשבון נאמנות",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: ChatStreamModule.getMessagesStream(chatRoomId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isNotEmpty) _handleMarkAsRead();

        return ListView.builder(
          reverse: true,
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var d = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            bool isMe = d['senderId'] == currentUserId;
            if (d['type'] == 'system_alert') return ChatUIHelper.buildSystemAlert(d['message'] ?? "");

            return ChatUIHelper.buildMessageBubble(
              context: context,
              data: d,
              isMe: isMe,
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.image_outlined), onPressed: () async {
            setState(() => _isUploading = true);
            String? url = await ImageModule.uploadImage(chatRoomId);
            if (url != null) _send(url, 'image');
            setState(() => _isUploading = false);
          }),
          IconButton(icon: const Icon(Icons.location_on_outlined), onPressed: () async {
            String? url = await LocationModule.getMapUrl();
            if (url != null) _send(url, 'location');
          }),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(25)),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: "הודעה...", border: InputBorder.none),
              ),
            ),
          ),
          const SizedBox(width: 5),
          CircleAvatar(
            backgroundColor: const Color(0xFF007AFF),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: () {
                if (_messageController.text.trim().isNotEmpty) {
                  _send(_messageController.text.trim(), 'text');
                  _messageController.clear();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}