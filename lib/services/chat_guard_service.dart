import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of a guard check on a message string.
class ChatGuardResult {
  final bool   isFlagged;
  final String maskedText;
  final String flagType; // 'phone' | 'keyword' | 'both'

  const ChatGuardResult({
    required this.isFlagged,
    required this.maskedText,
    this.flagType = '',
  });
}

/// Anti-circumvention chat filter.
///
/// Detects Israeli phone numbers and bypass keywords (WhatsApp, cash, etc.)
/// in chat messages.  When found:
///   • The app shows a warning SnackBar.
///   • The sent message is automatically masked.
///   • Repeated attempts are logged to `activity_log` for the admin Live Feed.
class ChatGuardService {
  ChatGuardService._();

  // ── Patterns ─────────────────────────────────────────────────────────────

  /// Israeli mobile numbers: 05X-XXXXXXX with optional spaces / dashes / dots.
  /// Also catches common landline formats (02/03/04/08/09-XXXXXXX).
  static final _phoneRegex = RegExp(
    r'0(?:5[0-9]|[2-4]|[6-9])\d?[-\s.]?\d{3}[-\s.]?\d{4}',
    caseSensitive: false,
  );

  /// Forbidden bypass keywords — Hebrew + English.
  /// Matched without strict word boundaries to catch Hebrew (where \b doesn't
  /// apply to Unicode characters).
  static final _keywordRegex = RegExp(
    r'מזומן|וואטסאפ|בואטסאפ|טלפון שלי|מספר שלי|'
    r'(?:^|\s)ביט(?:\s|$)|'         // "ביט" surrounded by spaces (Bit payment)
    r'\b(?:cash|whatsapp|wa\.me|phone|outside|direct)\b',
    caseSensitive: false,
  );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns a [ChatGuardResult] indicating whether [text] contains forbidden
  /// patterns, and providing a masked copy safe to send.
  static ChatGuardResult check(String text) {
    final hasPhone   = _phoneRegex.hasMatch(text);
    final hasKeyword = _keywordRegex.hasMatch(text);

    if (!hasPhone && !hasKeyword) {
      return ChatGuardResult(isFlagged: false, maskedText: text);
    }

    String masked = text;
    if (hasPhone) {
      masked = masked.replaceAllMapped(
        _phoneRegex,
        (_) => '📵 [מספר חסוי]',
      );
    }
    if (hasKeyword) {
      masked = masked.replaceAllMapped(
        _keywordRegex,
        (_) => '[פרטים חסויים]',
      );
    }

    final type = (hasPhone && hasKeyword)
        ? 'both'
        : hasPhone
            ? 'phone'
            : 'keyword';

    return ChatGuardResult(isFlagged: true, maskedText: masked, flagType: type);
  }

  /// Writes a bypass-attempt warning to `activity_log` so it appears in the
  /// admin Live Feed tab.  Called after [attemptThreshold] repeated violations.
  static Future<void> logBypassAttempt({
    required String userId,
    required String userName,
    required String chatRoomId,
    required String flagType,
    required int    attemptCount,
  }) async {
    final label = flagType == 'phone'
        ? 'מספר טלפון'
        : flagType == 'keyword'
            ? 'מילת מפתח חסומה'
            : 'טלפון + מילת מפתח';

    await FirebaseFirestore.instance.collection('activity_log').add({
      'type':  'bypass_attempt',
      'title': '⚠️ ניסיון עקיפת הפלטפורמה',
      'detail':
          'משתמש $userName מנסה להעביר שיחה מחוץ לאפליקציה ($label) '
          '— ניסיון מספר $attemptCount',
      'userId':       userId,
      'chatRoomId':   chatRoomId,
      'attemptCount': attemptCount,
      'createdAt':    FieldValue.serverTimestamp(),
    });
  }

  // ── Log threshold ─────────────────────────────────────────────────────────

  /// Minimum number of flagged sends before an admin alert is fired.
  static const int attemptThreshold = 2;
}
