// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../support_center_screen.dart';

/// Chat screen AppBar with live online status, receiver name, and support button.
///
/// Extracted from chat_screen.dart (Phase 6 refactor).
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
      title: Row(
        children: [
          // Avatar with live online dot
          StreamBuilder<DocumentSnapshot>(
            stream: userStream,
            builder: (_, snap) {
              final d        = snap.data?.data() as Map<String, dynamic>? ?? {};
              final isOnline = d['isOnline'] as bool? ?? false;
              final photo    = d['profileImage'] as String? ?? '';

              return Stack(children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFFEDE9FE),
                  backgroundImage: photo.isNotEmpty
                      ? CachedNetworkImageProvider(photo)
                      : null,
                  child: photo.isEmpty
                      ? Text(
                          receiverName.isNotEmpty ? receiverName[0] : '?',
                          style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey[300],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ]);
            },
          ),

          const SizedBox(width: 10),

          // Name + last-seen subtitle
          StreamBuilder<DocumentSnapshot>(
            stream: userStream,
            builder: (_, snap) {
              final d        = snap.data?.data() as Map<String, dynamic>? ?? {};
              final isOnline = d['isOnline']  as bool?      ?? false;
              final lastSeen = d['lastSeen']  as Timestamp?;
              final subtitle = isOnline
                  ? 'מחובר עכשיו'
                  : _lastSeenLabel(lastSeen);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(receiverName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: isOnline ? Colors.green : Colors.grey[400]),
                  ),
                ],
              );
            },
          ),
        ],
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

  String _lastSeenLabel(Timestamp? ts) {
    if (ts == null) return 'לא פעיל';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 5)  return 'נראה לאחרונה הרגע';
    if (diff.inHours  < 1)   return "נראה לפני ${diff.inMinutes} דק'";
    if (diff.inHours  < 24)  return "נראה לפני ${diff.inHours} שע'";
    return "נראה לפני ${diff.inDays} ימים";
  }
}
