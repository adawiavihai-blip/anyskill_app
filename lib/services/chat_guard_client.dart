import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Client-side wrapper for the `checkChatMessage` Cloud Function (Section 46
/// Phase 2). Call [check] before sending any text message; branch the UI
/// on [ChatGuardCheckResult.action].
///
/// **Kill-switch first.** When the admin sets
/// `chat_guard_settings/main.enabled = false`, the CF returns immediately
/// with `skipped: true` + `action: 'allowed'` and zero side effects.
/// That's why this service is safe to wire into the chat send path even
/// before the admin opts in — it's a no-op until they flip the toggle.
///
/// **Failure-open by design.** If the CF call throws (network down, region
/// cold start, App Check misconfig, etc.) the client falls back to
/// `action: 'allowed'` so a guard outage never blocks the user from
/// sending a message. The console gets a one-line warning.
class ChatGuardClient {
  ChatGuardClient._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  /// Returns the guard's decision on [message]. Pass [chatId] + [receiverId]
  /// when available so the incident log can resolve the conversation.
  static Future<ChatGuardCheckResult> check({
    required String message,
    String? chatId,
    String? receiverId,
  }) async {
    if (message.trim().isEmpty) {
      return const ChatGuardCheckResult.allowed(skipped: true);
    }
    try {
      final res = await _fn
          .httpsCallable('checkChatMessage')
          .call(<String, dynamic>{
        'message': message,
        if (chatId != null)    'chatId':     chatId,
        if (receiverId != null) 'receiverId': receiverId,
      });
      final data = res.data;
      if (data is! Map) return const ChatGuardCheckResult.allowed(skipped: true);
      return ChatGuardCheckResult._fromMap(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatGuardClient] check failed: $e');
      return const ChatGuardCheckResult.allowed(skipped: true);
    }
  }
}

/// Allowed actions returned by the CF. Mirrors the JS `ACTIONS` enum.
enum ChatGuardAction {
  allowed,
  warned,
  rewritten,
  blocked,
  suspended,
}

extension ChatGuardActionExt on ChatGuardAction {
  static ChatGuardAction fromWire(String? s) {
    switch (s) {
      case 'allowed':   return ChatGuardAction.allowed;
      case 'warned':    return ChatGuardAction.warned;
      case 'rewritten': return ChatGuardAction.rewritten;
      case 'blocked':   return ChatGuardAction.blocked;
      case 'suspended': return ChatGuardAction.suspended;
      default:          return ChatGuardAction.allowed;
    }
  }
}

class ChatGuardCheckResult {
  const ChatGuardCheckResult({
    required this.action,
    required this.detected,
    required this.skipped,
    this.severity,
    this.score = 0,
    this.rewrite,
    this.reason,
    this.matchedWords = const <String>[],
  });

  const ChatGuardCheckResult.allowed({this.skipped = false})
      : action = ChatGuardAction.allowed,
        detected = false,
        severity = null,
        score = 0,
        rewrite = null,
        reason = null,
        matchedWords = const <String>[];

  /// `true` when the kill-switch is off (admin disabled the guard) — call
  /// site should fall through to legacy / default send behavior.
  final bool skipped;

  /// `true` when the engine matched at least one rule.
  final bool detected;

  final ChatGuardAction action;
  final String? severity;
  final int score;
  final String? rewrite;
  final String? reason;
  final List<String> matchedWords;

  factory ChatGuardCheckResult._fromMap(Map<String, dynamic> m) {
    return ChatGuardCheckResult(
      action: ChatGuardActionExt.fromWire(m['action'] as String?),
      detected: (m['detected'] as bool?) ?? false,
      skipped: (m['skipped'] as bool?) ?? false,
      severity: m['severity'] as String?,
      score: (m['score'] as num?)?.toInt() ?? 0,
      rewrite: m['rewrite'] as String?,
      reason: m['reason'] as String?,
      matchedWords: m['matches'] is List
          ? (m['matches'] as List)
              .whereType<Map>()
              .map((e) => (e['word'] as String?) ?? '')
              .where((s) => s.isNotEmpty)
              .toList()
          : const <String>[],
    );
  }
}
