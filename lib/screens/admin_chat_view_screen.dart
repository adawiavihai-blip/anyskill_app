import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'chat_modules/chat_stream_module.dart';

/// Admin read-only chat view — lets admin watch a conversation between
/// a provider and customer, and inject a system message if needed.
class AdminChatViewScreen extends StatefulWidget {
  final String chatRoomId;
  final String providerName;
  final String customerName;

  const AdminChatViewScreen({
    super.key,
    required this.chatRoomId,
    required this.providerName,
    required this.customerName,
  });

  @override
  State<AdminChatViewScreen> createState() => _AdminChatViewScreenState();
}

class _AdminChatViewScreenState extends State<AdminChatViewScreen> {
  bool _sending = false;

  // ── Inject admin system message ───────────────────────────────────────────
  Future<void> _showInjectDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הזרקת הודעת מנהל'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'למשל: "System: אנא שמרו על שיח מקצועי."',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('שלח', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (!mounted) return;

    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
        'senderId':   'admin',
        'receiverId': '',
        'message':    '🛡️ System: ${ctrl.text.trim()}',
        'type':       'admin',
        'timestamp':  FieldValue.serverTimestamp(),
        'isRead':     false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הודעת מנהל נשלחה'),
            backgroundColor: Color(0xFF6366F1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Format timestamp ───────────────────────────────────────────────────────
  static String _formatTs(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('dd/MM HH:mm', 'he').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'צ\'אט — מצב צפייה',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.providerName} ↔ ${widget.customerName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_rounded,
                  color: Colors.redAccent),
              tooltip: 'הזרק הודעת מנהל',
              onPressed: _showInjectDialog,
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ChatStreamModule.getMessagesStream(widget.chatRoomId, limit: 100),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('אין הודעות בצ\'אט זה',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            reverse: true, // newest at bottom — stream is DESC
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d    = docs[i].data()! as Map<String, dynamic>;
              final text = d['message'] as String? ?? '';
              final type = d['type']    as String? ?? 'text';
              final ts   = d['createdAt'] as Timestamp? ?? d['timestamp'] as Timestamp?;
              final sid  = d['senderId'] as String? ?? '';

              final isAdmin   = type == 'admin';
              final isSystem  = sid == 'admin';

              // ── Admin system messages — centred red banner ─────────────
              if (isAdmin || isSystem) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              }

              // ── Determine bubble alignment ─────────────────────────────
              // If senderId matches the first segment of chatRoomId it's
              // the "left" user (provider); otherwise it's the "right" user.
              final parts = widget.chatRoomId.split('_');
              final isFirstUser = parts.isNotEmpty && sid == parts[0];

              final bgColor = isFirstUser
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF0F172A);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: isFirstUser
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isFirstUser)
                      _SenderAvatar(
                          label: widget.providerName.isNotEmpty
                              ? widget.providerName[0]
                              : 'P',
                          color: const Color(0xFF6366F1)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isFirstUser
                                  ? widget.providerName
                                  : widget.customerName,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 10),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              type == 'image' ? '📷 תמונה' : text,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTs(ts),
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!isFirstUser)
                      _SenderAvatar(
                          label: widget.customerName.isNotEmpty
                              ? widget.customerName[0]
                              : 'C',
                          color: const Color(0xFF0F172A)),
                  ],
                ),
              );
            },
          );
        },
      ),

      // ── Admin message inject FAB ─────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sending ? null : _showInjectDialog,
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.security_rounded, color: Colors.white),
        label: const Text('הודעת מנהל',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Small avatar circle beside each bubble ────────────────────────────────────
class _SenderAvatar extends StatelessWidget {
  final String label;
  final Color  color;
  const _SenderAvatar({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
