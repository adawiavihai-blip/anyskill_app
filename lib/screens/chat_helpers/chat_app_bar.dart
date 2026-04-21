import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/chat_theme_controller.dart';
import '../../utils/safe_image_provider.dart';
import 'chat_settings_sheet.dart';

/// Chat screen AppBar with live online status, synced avatar, and the
/// ⋮ settings-menu button (PR-3a).
///
/// The palette is read from [ChatThemeScope] so the AppBar flips between
/// light and dark — via a smooth [TweenAnimationBuilder] animation — along
/// with the rest of the chat body.
///
/// The support-center icon that used to live in the actions row was
/// removed in PR-3a; support is still reachable via the pinned entry at
/// the top of the Messages tab (Law 22).
class ChatAppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  final String receiverId;
  final String receiverName;

  const ChatAppBarWidget({
    super.key,
    required this.receiverId,
    required this.receiverName,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final scope = ChatThemeScope.of(context);
    final p = scope.palette;
    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(receiverId)
        .snapshots();

    return AppBar(
      backgroundColor: p.surfaceRaised,
      foregroundColor: p.textPrimary,
      elevation: 0,
      titleSpacing: 0,
      iconTheme: IconThemeData(color: p.textPrimary),
      title: StreamBuilder<DocumentSnapshot>(
        stream: userStream,
        builder: (_, snap) {
          final d = snap.data?.data() as Map<String, dynamic>? ?? {};
          final isOnline = d['isOnline'] as bool? ?? false;
          final photo = d['profileImage'] as String? ?? '';
          final lastSeen = d['lastSeen'] as Timestamp?;
          final subtitle =
              isOnline ? 'מחובר עכשיו' : _lastSeenLabel(lastSeen);

          return Row(
            children: [
              Stack(children: [
                _buildAvatar(photo, p),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFF22C55E)
                          : p.textMuted,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: p.surfaceRaised, width: 2),
                    ),
                  ),
                ),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      receiverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : p.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.more_vert_rounded,
              color: p.textSecondary, size: 22),
          tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
          onPressed: () => showChatSettingsSheet(context),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: p.border),
      ),
    );
  }

  Widget _buildAvatar(String photo, ChatPalette p) {
    final provider = safeImageProvider(photo);
    if (provider != null) {
      return CircleAvatar(
        radius: 19,
        backgroundColor: p.surfaceMuted,
        backgroundImage: provider,
      );
    }
    final letter = receiverName.trim().isNotEmpty
        ? receiverName.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  String _lastSeenLabel(Timestamp? ts) {
    if (ts == null) return 'לא פעיל';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 5) return 'נראה לאחרונה הרגע';
    if (diff.inHours < 1) return "נראה לפני ${diff.inMinutes} דק'";
    if (diff.inHours < 24) return "נראה לפני ${diff.inHours} שע'";
    return "נראה לפני ${diff.inDays} ימים";
  }
}
