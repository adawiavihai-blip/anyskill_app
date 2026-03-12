import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// יבוא המודולים
import 'chat_modules/location_module.dart';
import 'chat_modules/image_module.dart';
import 'chat_modules/audio_module.dart';
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

  @override
  void initState() {
    super.initState();
    List<String> ids = [currentUserId, widget.receiverId];
    ids.sort();
    chatRoomId = ids.join("_");
    
    _handleMarkAsRead();
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
    ChatLogicModule.markMessagesAsRead(chatRoomId, currentUserId);
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
        bool isDone = status == 'expert_completed' || status == 'paid_escrow';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDone ? Colors.green[50] : Colors.amber[50],
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Icon(isDone ? Icons.check_circle : Icons.security, 
                   color: isDone ? Colors.green : Colors.amber[900]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDone ? "העבודה הסתיימה! אשר שחרור תשלום." : "התשלום מוגן בחשבון נאמנות",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              if (!isExpert && isDone)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, 
                    padding: const EdgeInsets.symmetric(horizontal: 10)
                  ),
                  onPressed: () async {
                    // 1. גלגל טעינה - מבטיח שהשם יישמר לפני סגירת הטרנזקציה
                    showDialog(
                      context: context, 
                      barrierDismissible: false, 
                      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white))
                    );

                    // 2. 🔥 QA: שליפת השם בזמן אמת מה-DB
                    String realName = await _getCurrentUserName();

                    // 3. ביצוע התשלום
                    bool success = await PaymentModule.releaseEscrowFunds(
                      jobId: jobDoc.id, 
                      expertId: jobData['expertId'] ?? widget.receiverId, 
                      expertName: widget.receiverName, 
                      customerName: realName, // השם המלא ששלפנו עכשיו
                      totalAmount: (jobData['totalAmount'] ?? 0.0).toDouble(),
                    );

                    if (mounted) Navigator.pop(context); // סגירת גלגל טעינה

                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("התשלום שוחרר בהצלחה!"), backgroundColor: Colors.green)
                      );
                    }
                  },
                  child: const Text("אשר ושחרר", style: TextStyle(color: Colors.white, fontSize: 12)),
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