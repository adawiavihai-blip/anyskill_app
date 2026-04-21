import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/safe_image_provider.dart';
import '../support_center_screen.dart';

/// Chat screen AppBar with live online status, real synced avatar, and
/// support button.
///
/// Avatar handling: routes through [safeImageProvider] so both HTTPS URLs
/// AND base64 onboarding photos render without crashing (Law 11).
/// Fallback is a purple gradient circle with the receiver's first letter,
/// matching the messages-upgrade spec.
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
    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(receiverId)
        .snapshots();

    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      titleSpacing: 0,
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
                _buildAvatar(photo),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFF22C55E)
                          : Colors.grey[300],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
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
                            : Colors.grey[500],
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
          icon: const Icon(Icons.support_agent_rounded,
              color: Color(0xFF9CA3AF), size: 22),
          tooltip: 'מרכז התמיכה',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SupportCenterScreen(),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade100),
      ),
    );
  }

  Widget _buildAvatar(String photo) {
    final provider = safeImageProvider(photo);
    if (provider != null) {
      return CircleAvatar(
        radius: 19,
        backgroundColor: const Color(0xFFEDE9FE),
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
