import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';
import 'support_center_screen.dart';
import '../l10n/app_localizations.dart';
import '../widgets/skeleton_loader.dart';
import '../services/chat_service.dart';

class ChatListScreen extends StatefulWidget {
  final VoidCallback? onGoToSearch;
  const ChatListScreen({super.key, this.onGoToSearch});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
  String _searchQuery = "";

  // v9.6.4: Replaced snapshot stream with periodic polling (get()) to eliminate
  // concurrent Firestore listeners that caused INTERNAL ASSERTION FAILED on Web.
  List<QueryDocumentSnapshot> _chatDocs = [];
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchChats();
    // Poll every 10 seconds for new messages
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchChats());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Manual refresh — called on pull-to-refresh and when tab becomes visible.
  Future<void> _fetchChats() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: currentUserId)
          .limit(50)
          .get();
      if (!mounted) return;
      final docs = snap.docs.toList();
      // Sort by lastMessageTime descending (null = bottom)
      docs.sort((a, b) {
        final aData = a.data();
        final bData = b.data();
        final aTime = aData['lastMessageTime'] as Timestamp?;
        final bTime = bData['lastMessageTime'] as Timestamp?;
        return (bTime ?? Timestamp(0, 0)).compareTo(aTime ?? Timestamp(0, 0));
      });
      setState(() {
        _chatDocs = docs;
        _isLoading = false;
        _hasError = false;
      });
      _primeUserCache(docs);
    } catch (e) {
      debugPrint('[ChatList] _fetchChats error: $e');
      if (mounted && _chatDocs.isEmpty) {
        setState(() { _isLoading = false; _hasError = true; });
      }
    }
  }

  /// Public method so parent (HomeScreen) can trigger refresh on tab switch.
  void refresh() => _fetchChats();

  // ── User profile cache — avoids per-item Firestore reads on every rebuild ──
  final Map<String, Map<String, dynamic>> _userCache = {};

  /// Fetches user profiles for any IDs not already cached.
  /// Uses a single batched `whereIn` query (≤30 IDs per call) instead of N+1
  /// individual reads. Results land in `_userCache` and trigger one rebuild.
  void _primeUserCache(List<QueryDocumentSnapshot> chats) {
    final missing = <String>[];
    for (final doc in chats) {
      final users = ((doc.data() as Map)['users'] as List? ?? []);
      final other = users.firstWhere(
          (id) => id != currentUserId, orElse: () => '') as String;
      if (other.isNotEmpty && !_userCache.containsKey(other)) {
        missing.add(other);
      }
    }
    if (missing.isEmpty) return;
    _batchFetchUsers(missing);
  }

  Future<void> _batchFetchUsers(List<String> uids) async {
    final unique = uids.toSet().where((id) => !_userCache.containsKey(id)).toList();
    if (unique.isEmpty) return;
    // Process in chunks of 30 (Firestore whereIn limit)
    for (int i = 0; i < unique.length; i += 30) {
      final chunk = unique.sublist(i, (i + 30).clamp(0, unique.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          _userCache[doc.id] = doc.data();
        }
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('[ChatList] _batchFetchUsers error: $e');
      }
    }
  }

  /// v9.5.10: Mark all chats as read via CF — NEVER write to parent chat docs
  /// from the client (causes AsyncQueue deadlock with active listeners).
  Future<void> _markAllAsRead() async {
    try {
      final chats = await FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: currentUserId)
          .limit(50)
          .get();

      if (chats.docs.isEmpty) return;

      // Call the CF for each chat that has unread messages.
      // The CF resets unreadCount on the server side (no client write to parent doc).
      final futures = <Future>[];
      for (final doc in chats.docs) {
        final data = doc.data();
        if ((data['unreadCount_$currentUserId'] ?? 0) > 0) {
          futures.add(
            ChatService.markMessagesAsRead(doc.id, currentUserId),
          );
        }
      }
      await Future.wait(futures);

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
        // Delete messages in batched pages of 400 (well under the 500-write limit).
        // An unbounded .get() on a large chat room would OOM on low-end devices.
        const int pageSize = 400;
        bool hasMore = true;
        while (hasMore) {
          final page = await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .limit(pageSize)
              .get();
          if (page.docs.isEmpty) break;
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in page.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          hasMore = page.docs.length == pageSize;
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _hasError
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text('שגיאה בטעינת הצ\'אטים', style: TextStyle(color: Colors.grey[600])),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _fetchChats, child: const Text('נסה שוב')),
                        ],
                      ))
                    : _chatDocs.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _fetchChats,
                            child: ListView.separated(
                              itemCount: _chatDocs.length + 1,
                              padding: const EdgeInsets.only(bottom: 20),
                              separatorBuilder: (_, __) => Divider(
                                height: 1, thickness: 0.5,
                                indent: 90, endIndent: 16,
                                color: Colors.grey.shade100,
                              ),
                              itemBuilder: (context, index) {
                                // Index 0 = pinned Support entry
                                if (index == 0) {
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFF6366F1),
                                      child: Icon(Icons.support_agent_rounded,
                                          color: Colors.white, size: 22),
                                    ),
                                    title: const Text('תמיכה',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: const Text('צריך עזרה? דבר עם הצוות שלנו',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                                    trailing: const Icon(Icons.arrow_forward_ios_rounded,
                                        size: 14, color: Color(0xFF94A3B8)),
                                    onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const SupportCenterScreen())),
                                  );
                                }
                                final chatDoc  = _chatDocs[index - 1];
                                final chatData = chatDoc.data() as Map<String, dynamic>? ?? {};
                                final users    = chatData['users'] as List? ?? [];
                                final otherUserId = users.firstWhere(
                                    (id) => id != currentUserId, orElse: () => '') as String;

                                if (otherUserId.isEmpty) return const SizedBox.shrink();

                                final userData = _userCache[otherUserId];
                                if (userData == null) return const _ChatTileSkeleton();

                                final otherName = (userData['name'] ?? '') as String;
                                if (_searchQuery.isNotEmpty &&
                                    !otherName.toLowerCase().contains(_searchQuery)) {
                                  return const SizedBox.shrink();
                                }

                                return _buildChatTile(userData, chatData, chatDoc.id, otherUserId);
                              },
                            ),
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

    // v9.6.0: Typing indicators moved to subcollection in v9.5.5.
    // The parent doc no longer has typing_ fields. Typing is only shown
    // inside ChatScreen via the subcollection listener.
    // Cached image — used as the first-frame fallback before the stream fires.
    final String cachedImg = userData['profileImage'] as String? ?? '';
    final String name      = userData['name']         as String? ?? '';

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
            // Live avatar — streams the other user's doc so image + online
            // status always reflect Firestore even after profile updates.
            _LiveAvatar(
              userId:       otherId,
              fallbackImg:  cachedImg,
              fallbackName: name,
              isOnlineFallback: userData['isOnline'] == true,
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
                    lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unreadCount > 0 ? Colors.black : Colors.grey[600],
                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (unreadCount > 0)
              _PulsingUnreadBadge(count: unreadCount),
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

// ── Skeleton placeholder for a single chat tile ────────────────────────────
// Shown while the user cache is being primed (first load only).
// Same height as a real tile so the list doesn't jump on first data arrival.
class _ChatTileSkeleton extends StatelessWidget {
  const _ChatTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 60, height: 60, child: SkeletonBox(borderRadius: 30)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(height: 14, child: SkeletonBox(borderRadius: 4)),
                SizedBox(height: 6),
                SizedBox(height: 12, child: SkeletonBox(borderRadius: 4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing unread badge ───────────────────────────────────────────────────
// Replaces the static CircleAvatar — gently pulses to draw attention to
// unread messages without being intrusive.
class _PulsingUnreadBadge extends StatefulWidget {
  final int count;
  const _PulsingUnreadBadge({required this.count});

  @override
  State<_PulsingUnreadBadge> createState() => _PulsingUnreadBadgeState();
}

class _PulsingUnreadBadgeState extends State<_PulsingUnreadBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final Animation<double> _scale =
      Tween<double>(begin: 0.88, end: 1.10)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.40),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          widget.count > 99 ? '99+' : '${widget.count}',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── Static avatar for chat list tiles (v9.6.4) ─────────────────────────────
// v9.6.4: Replaced StreamBuilder per-tile with static cached data.
// Each _LiveAvatar was an individual Firestore snapshot listener — with 20 chats
// that's 20 extra listeners causing AsyncQueue overload. Now uses _userCache data.
class _LiveAvatar extends StatelessWidget {
  final String userId;
  final String fallbackImg;
  final String fallbackName;
  final bool   isOnlineFallback;

  const _LiveAvatar({
    required this.userId,
    required this.fallbackImg,
    required this.fallbackName,
    required this.isOnlineFallback,
  });

  @override
  Widget build(BuildContext context) {
    final photo   = fallbackImg.trim();
    final initial = fallbackName.isNotEmpty ? fallbackName[0].toUpperCase() : '?';

    return Stack(
      children: [
        SizedBox(
          width: 60, height: 60,
          child: ClipOval(
            child: photo.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photo, width: 60, height: 60, fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 200),
                    placeholder: (_, __) => _InitialFill(initial: initial),
                    errorWidget: (_, __, ___) => _InitialFill(initial: initial),
                  )
                : _InitialFill(initial: initial),
          ),
        ),
        if (isOnlineFallback)
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: Colors.green, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// Solid indigo fill with initial letter — shown while image loads or on error.
class _InitialFill extends StatelessWidget {
  final String initial;
  const _InitialFill({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEF2FF),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color:      Color(0xFF6366F1),
            fontWeight: FontWeight.bold,
            fontSize:   18,
          ),
        ),
      ),
    );
  }
}