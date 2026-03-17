import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';
import '../l10n/app_localizations.dart';

class ChatListScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const ChatListScreen({super.key, this.onGoToSearch});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
  String _searchQuery = "";

  Future<void> _markAllAsRead() async {
    try {
      final chats = await FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: currentUserId)
          .limit(50)
          .get();

      if (chats.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in chats.docs) {
        final data = doc.data();
        if ((data['unreadCount_$currentUserId'] ?? 0) > 0) {
          batch.update(doc.reference, {'unreadCount_$currentUserId': 0});
        }
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).markAllReadSuccess), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("markAllAsRead error: $e");
    }
  }

  void _deleteEntireChat(String chatId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(context).deleteChatTitle, textAlign: TextAlign.start),
        content: Text(AppLocalizations.of(context).deleteChatContent, textAlign: TextAlign.start),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).deleteChatConfirm, style: const TextStyle(color: Colors.white)),
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).deleteChatSuccess)));
        }
      } catch (e) {
        debugPrint("Error deleting chat: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (currentUserId.isEmpty) return Scaffold(body: Center(child: Text(l10n.notLoggedIn)));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(l10n.chatListTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: Colors.black)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all, color: Colors.blue),
            tooltip: l10n.markAllReadTooltip,
            onPressed: _markAllAsRead,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('users', arrayContains: currentUserId)
                  .limit(50)
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
                        String otherName = userData['name'] ?? AppLocalizations.of(context).chatUserDefault;

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
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).chatSearchHint,
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> userData, Map<String, dynamic> chatData, String chatId, String otherId) {
    // הגנה על שדות ה-Message
    final l10nTile = AppLocalizations.of(context);
    String lastMsg = chatData['lastMessage'] ?? l10nTile.chatLastMessageDefault;
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
          builder: (context) => ChatScreen(receiverId: otherId, receiverName: userData['name'] ?? AppLocalizations.of(context).chatUserDefault))),
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
                      Text(userData['name'] ?? l10nTile.chatUserDefault,
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
                PopupMenuItem(value: 'del', child: Text(AppLocalizations.of(context).deleteChatTitle, style: const TextStyle(color: Colors.red)))
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).chatEmptyState,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).searchPlaceholder,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.search, color: Colors.white),
              label: Text(AppLocalizations.of(context).searchTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: widget.onGoToSearch ?? () {},
            ),
          ],
        ),
      ),
    );
  }
}