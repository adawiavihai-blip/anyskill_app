import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/support_center_screen.dart';

/// Maps raw Firebase/platform exceptions to friendly Hebrew messages
/// and navigates to the internal Support Chat (not WhatsApp).
///
/// Usage:
/// ```dart
/// try { ... } catch (e) {
///   ErrorMapper.show(context, e);
/// }
/// ```
class ErrorMapper {
  ErrorMapper._();

  /// Extracts a short error code string for the automated support message.
  static String _errorCode(Object error) {
    if (error is FirebaseException) return error.code;
    if (error is FirebaseAuthException) return error.code;
    final s = error.toString();
    if (s.contains('SocketException')) return 'network_error';
    if (s.contains('TimeoutException')) return 'timeout';
    // Truncate raw message to avoid huge strings
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }

  /// Converts any exception to a user-friendly Hebrew message.
  static String messageFor(Object error) {
    final msg = error.toString();

    // ── Firestore errors ──────────────────────────────────────────────────
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'היי, נראה שיש לנו תקלה קטנה בחיבור הפרופיל שלך. '
              'נסה לרענן את הדף או לחץ לדבר עם תמיכה.';
        case 'unavailable':
          return 'השירות לא זמין כרגע. בדוק את החיבור לאינטרנט ונסה שוב.';
        case 'not-found':
          return 'המידע המבוקש לא נמצא. ייתכן שנמחק או שהכתובת שגויה.';
        case 'already-exists':
          return 'פריט זה כבר קיים במערכת.';
        case 'resource-exhausted':
          return 'יותר מדי בקשות. נסה שוב בעוד מספר שניות.';
        case 'deadline-exceeded':
          return 'הבקשה לקחה יותר מדי זמן. בדוק את האינטרנט ונסה שוב.';
        case 'cancelled':
          return 'הפעולה בוטלה. נסה שוב.';
        case 'unauthenticated':
          return 'נראה שפג תוקף החיבור שלך. נסה להתנתק ולהתחבר מחדש.';
        default:
          return 'אירעה שגיאה (${error.code}). אנא נסה שוב מאוחר יותר.';
      }
    }

    // ── Firebase Auth errors ──────────────────────────────────────────────
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'לא נמצא חשבון עם הפרטים האלה. נסה להירשם.';
        case 'wrong-password':
          return 'הסיסמה שגויה. נסה שוב או אפס סיסמה.';
        case 'too-many-requests':
          return 'יותר מדי ניסיונות. נסה שוב בעוד מספר דקות.';
        case 'network-request-failed':
          return 'בעיית חיבור לאינטרנט. בדוק את הרשת ונסה שוב.';
        case 'invalid-verification-code':
          return 'קוד האימות שגוי. בדוק שהזנת את הקוד הנכון.';
        case 'session-expired':
          return 'קוד האימות פג תוקף. בקש קוד חדש.';
        default:
          return 'שגיאת התחברות (${error.code}). נסה שוב.';
      }
    }

    // ── Network / timeout ─────────────────────────────────────────────────
    if (msg.contains('SocketException') || msg.contains('NetworkError')) {
      return 'אין חיבור לאינטרנט. בדוק את הרשת ונסה שוב.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'הבקשה לקחה יותר מדי זמן. נסה שוב.';
    }

    // ── Generic payment errors ────────────────────────────────────────────
    if (msg.contains('payment')) {
      return 'בעיה בתהליך התשלום. נסה שוב או פנה לתמיכה.';
    }

    // ── Generic fallback ──────────────────────────────────────────────────
    return 'משהו השתבש. אנא נסה שוב או פנה לתמיכה.';
  }

  /// Shows a SnackBar with the friendly Hebrew message + "Talk to Support" button
  /// that opens the **internal** Support Chat (creates a ticket with the error
  /// pre-filled as the first message).
  static void show(BuildContext context, Object error, {bool showSupport = true}) {
    final message = messageFor(error);
    final errorCode = _errorCode(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(message,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, height: 1.4)),
            if (showSupport) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  // Dismiss snackbar first
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  // Open internal support chat with error context
                  _openSupportChat(context, errorCode, message);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.support_agent_rounded,
                        size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('לחץ כאן לדבר עם תמיכה',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        )),
                  ],
                ),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  /// Opens the internal Support Center and auto-creates a ticket with the
  /// error context pre-filled as the first message.
  static void _openSupportChat(
      BuildContext context, String errorCode, String friendlyMessage) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final userName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'משתמש';

    // Create the support ticket immediately with error context,
    // then navigate to the chat screen.
    _createErrorTicket(uid, userName, errorCode, friendlyMessage).then((ticketId) {
      if (ticketId != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TicketChatScreen(
              ticketId: ticketId,
              category: 'error_report',
              isAdmin: false,
            ),
          ),
        );
      } else if (context.mounted) {
        // Fallback: open the support center normally
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SupportCenterScreen(),
          ),
        );
      }
    });
  }

  /// Creates a support ticket with the error pre-filled as the first message.
  /// Returns the ticket ID on success, null on failure.
  static Future<String?> _createErrorTicket(
      String uid, String userName, String errorCode, String friendlyMessage) async {
    if (uid.isEmpty) return null;
    try {
      final db = FirebaseFirestore.instance;
      final ticketRef = await db.collection('support_tickets').add({
        'userId': uid,
        'userName': userName,
        'jobId': null,
        'category': 'error_report',
        'subject': 'שגיאה אוטומטית: $errorCode',
        'status': 'open',
        'evidenceUrls': <String>[],
        'assignedAdmin': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Write automated error context as the first message
      await ticketRef.collection('messages').add({
        'senderId': uid,
        'senderName': 'מערכת (אוטומטי)',
        'isAdmin': false,
        'message': '🔴 דיווח שגיאה אוטומטי\n\n'
            'קוד: $errorCode\n'
            'הודעה: $friendlyMessage\n\n'
            'המשתמש לחץ "דבר עם תמיכה" מתוך הודעת השגיאה.',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return ticketRef.id;
    } catch (e) {
      debugPrint('[ErrorMapper] Failed to create error ticket: $e');
      return null;
    }
  }
}
