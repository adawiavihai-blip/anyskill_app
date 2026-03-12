import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
  String _searchQuery = "";

  void _deleteEntireChat(String chatId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("מחיקת שיחה", textAlign: TextAlign.right),
        content: const Text("האם אתה בטוח שברצונך למחוק את כל היסטוריית השיחה?", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ביטול")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("מחק", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        var messages = await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').get();
        for (var doc in messages.docs) {
          await doc.reference.delete();
        }
        await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("השיחה נמחקה")));
        }
      } catch (e) {
        debugPrint("Error deleting chat: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId.isEmpty) return const Scaffold(body: Center(child: Text("נא להתחבר מחדש")));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text("הודעות", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: Colors.black)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: false,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('users', arrayContains: currentUserId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();

                var chats = snapshot.data!.docs;

                // מיון בטוח - מונע קריסה אם חסר זמן
                chats.sort((a, b) {
                  var aData = a.data() as Map<String, dynamic>? ?? {};
                  var bData = b.data() as Map<String, dynamic>? ?? {};
                  var aTime = aData['lastMessageTime'] as Timestamp?;
                  var bTime = bData['lastMessageTime'] as Timestamp?;
                  return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
                });

                return ListView.builder(
                  itemCount: chats.length,
                  padding: const EdgeInsets.only(bottom: 20),
                  itemBuilder: (context, index) {
                    var chatDoc = chats[index];
                    var chatData = chatDoc.data() as Map<String, dynamic>? ?? {};
                    List users = chatData['users'] ?? [];
                    String otherUserId = users.firstWhere((id) => id != currentUserId, orElse: () => "");

                    if (otherUserId.isEmpty) return const SizedBox.shrink();

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
                      builder: (context, userSnap) {
                        if (userSnap.connectionState == ConnectionState.waiting) return const SizedBox();
                        var userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                        String otherName = userData['name'] ?? "משתמש";

                        if (_searchQuery.isNotEmpty && !otherName.toLowerCase().contains(_searchQuery)) {
                          return const SizedBox.shrink();
                        }

                        return _buildChatTile(userData, chatData, chatDoc.id, otherUserId);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
        ),
        child: TextField(
          onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
          decoration: const InputDecoration(
            hintText: "חפש שיחה...",
            prefixIcon: Icon(Icons.search, color: Colors.grey),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> userData, Map<String, dynamic> chatData, String chatId, String otherId) {
    // הגנה על שדות ה-Message
    String lastMsg = chatData['lastMessage'] ?? "הודעה חדשה";
    Timestamp? lastTime = chatData['lastMessageTime'];
    
    // שליחת ה-ID הנכון לבדיקת הודעות שלא נקראו
    int unreadCount = 0;
    try {
      unreadCount = chatData['unreadCount_$currentUserId'] ?? 0;
    } catch (e) {
      unreadCount = 0;
    }

    bool isTyping = chatData['typing_$otherId'] ?? false;
    String imgUrl = userData['profileImage'] ?? "";

    String timeStr = "";
    if (lastTime != null) {
      DateTime dt = lastTime.toDate();
      timeStr = (DateTime.now().difference(dt).inDays == 0) ? DateFormat('HH:mm').format(dt) : DateFormat('dd/MM').format(dt);
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (context) => ChatScreen(receiverId: otherId, receiverName: userData['name'] ?? "משתמש"))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: (imgUrl.isNotEmpty && imgUrl.startsWith('http')) ? NetworkImage(imgUrl) : null,
                  child: (imgUrl.isEmpty || !imgUrl.startsWith('http')) ? const Icon(Icons.person, color: Colors.grey) : null,
                ),
                if (userData['isOnline'] == true)
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 14, height: 14,
                      decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(userData['name'] ?? "משתמש", 
                        style: TextStyle(
                          fontWeight: unreadCount > 0 ? FontWeight.w900 : FontWeight.bold, 
                          fontSize: 16,
                          color: Colors.black87
                        )
                      ),
                      Text(timeStr, style: TextStyle(color: unreadCount > 0 ? Colors.blue : Colors.grey, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isTyping ? "מקליד..." : lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isTyping ? Colors.green : (unreadCount > 0 ? Colors.black : Colors.grey[600]),
                      fontWeight: (unreadCount > 0 || isTyping) ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: CircleAvatar(
                  radius: 10, 
                  backgroundColor: Colors.blue, 
                  child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
              onSelected: (v) => _deleteEntireChat(chatId),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'del', child: Text("מחק שיחה", style: TextStyle(color: Colors.red)))
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("אין הודעות עדיין", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}