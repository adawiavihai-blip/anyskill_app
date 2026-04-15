// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/offline_message_queue.dart';
import '../../widgets/skeleton_loader.dart';
import '../chat_modules/chat_ui_helper.dart';
import '../chat_modules/chat_stream_module.dart';
import '../expert_profile_screen.dart';

/// Renders the chat message list with error/loading states.
///
/// Extracted from chat_screen.dart (Phase 6 refactor).
/// v12.2: merges locally-pending messages from [OfflineMessageQueue] so
/// offline/in-flight messages render with a clock icon immediately.
class ChatMessageList extends StatelessWidget {
  final String chatRoomId;
  final String currentUserId;
  final String receiverId;
  final String receiverName;
  final String currentUserName;
  final String currentUserImageUrl;
  final String receiverImageUrl;
  final ScrollController scrollController;
  final VoidCallback onMessagesLoaded;

  const ChatMessageList({
    super.key,
    required this.chatRoomId,
    required this.currentUserId,
    required this.receiverId,
    required this.receiverName,
    required this.currentUserName,
    required this.currentUserImageUrl,
    required this.receiverImageUrl,
    required this.scrollController,
    required this.onMessagesLoaded,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: ChatStreamModule.getMessagesStream(chatRoomId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[ChatScreen] Message stream error: ${snapshot.error}');
          return _MessagesErrorState(onRetry: () {
            // No-op: stream rebuild handled by parent
          });
        }
        if (!snapshot.hasData) {
          return _MessagesSkeleton();
        }
        final docs = snapshot.data!.docs;
        if (docs.isNotEmpty) onMessagesLoaded();

        // Rebuild whenever the local outbox changes (enqueue / send-ok / failed).
        return AnimatedBuilder(
          animation: OfflineMessageQueue.instance,
          builder: (context, _) {
            // Build a single merged list: server docs + pending stubs.
            // Both are ordered newest-first to match the ListView.reverse layout.
            final pending = OfflineMessageQueue.instance
                .pendingFor(chatRoomId)
                .map((m) => _MergedItem.pending(m))
                .toList();
            final remote = docs
                .map((d) => _MergedItem.remote(
                    d.data() as Map<String, dynamic>? ?? {}))
                .toList();
            final items = [...pending, ...remote];

            return ListView.builder(
              controller: scrollController,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final d    = item.data;
                final isMe = d['senderId'] == currentUserId;
                final isSys = d['senderId'] == 'system' ||
                    d['type'] == 'system_alert';

                if (isSys) {
                  return ChatUIHelper.buildSystemAlert(
                      d['message']?.toString() ?? '');
                }

                return ChatUIHelper.buildMessageBubble(
                  context: context,
                  data:    d,
                  isMe:    isMe,
                  currentUserId:  currentUserId,
                  chatRoomId:     chatRoomId,
                  senderName:     isMe ? currentUserName : receiverName,
                  senderImageUrl: isMe ? currentUserImageUrl : receiverImageUrl,
                  onPaymentTap: isMe
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExpertProfileScreen(
                                expertId:   receiverId,
                                expertName: receiverName,
                              ),
                            ),
                          ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Unified wrapper so remote Firestore docs and local pending messages can
/// flow through the same bubble builder without per-call branching.
class _MergedItem {
  final Map<String, dynamic> data;
  _MergedItem._(this.data);

  factory _MergedItem.remote(Map<String, dynamic> d) => _MergedItem._(d);
  factory _MergedItem.pending(PendingMessage m) => _MergedItem._(m.toDocMap());
}

/// Error state shown when the messages stream fails.
class _MessagesErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _MessagesErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 48, color: Color(0xFF6B7280)),
            const SizedBox(height: 12),
            const Text('שגיאה בטעינת ההודעות',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text('נסה לרענן את הדף או לחזור לרשימת ההודעות',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('נסה שוב'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton bubbles shown while the first Firestore page loads.
class _MessagesSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final bubbles = <(double, bool)>[
      (w * 0.55, true),
      (w * 0.40, false),
      (w * 0.68, true),
      (w * 0.32, false),
      (w * 0.50, true),
      (w * 0.62, false),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      children: bubbles.map((item) {
        final (double width, bool isMe) = item;
        return Padding(
          padding: EdgeInsets.only(
              top: 4, bottom: 4,
              left:  isMe ? 60 : 10,
              right: isMe ? 10 : 60),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: SizedBox(
              width: width, height: 40,
              child: const SkeletonBox(borderRadius: 18),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// "X is typing..." bubble with animated dots.
class ChatTypingBubble extends StatelessWidget {
  final String receiverName;
  const ChatTypingBubble({super.key, required this.receiverName});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 60, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(18),
            topRight:    Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft:  Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$receiverName מקליד',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(width: 8),
            const TypingDots(),
          ],
        ),
      ),
    );
  }
}

/// Animated three-dot typing indicator.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      );
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: -5).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width:  5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
