import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatUIHelper {
  // עיצוב בועת הודעה כללית
  static Widget buildMessageBubble({
    required BuildContext context,
    required Map<String, dynamic> data,
    required bool isMe,
  }) {
    String type = data['type'] ?? 'text';
    String msg = data['message'] ?? "";
    var timestamp = data['timestamp'];
    bool isRead = data['isRead'] ?? false;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF007AFF) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          // QA: יישור לפי השולח
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _buildContentByType(type, msg, isMe),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTimestamp(timestamp, isMe),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all,
                    size: 15,
                    color: isRead ? Colors.cyanAccent : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // חלוקה לפי סוג הודעה - QA: פתרון לבעיית ה-Build ב-Web
  static Widget _buildContentByType(String type, String msg, bool isMe) {
    switch (type) {
      case 'image':
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            msg,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      case 'location':
        return InkWell(
          onTap: () => launchUrl(Uri.parse(msg)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 20),
              const SizedBox(width: 5),
              Text(
                "צפה במיקום",
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.blue,
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      default:
        // QA: שימוש ב-TextAlign במקום TextDirection עוקף את שגיאת הקומפילציה
        return Text(
          msg,
          textAlign: TextAlign.right, 
          style: TextStyle(
            color: isMe ? Colors.white : Colors.black87,
            fontSize: 16,
          ),
        );
    }
  }

  // עיצוב הזמן בתחתית הבועה
  static Widget _buildTimestamp(dynamic timestamp, bool isMe) {
    if (timestamp == null) return const SizedBox.shrink();
    
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      date = DateTime.now();
    }
    
    String time = DateFormat('HH:mm').format(date);
    
    return Text(
      time,
      style: TextStyle(
        fontSize: 10,
        color: isMe ? Colors.white70 : Colors.grey,
      ),
    );
  }

  // עיצוב הודעת מערכת
  static Widget buildSystemAlert(String msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ),
    );
  }
}