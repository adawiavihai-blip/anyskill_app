import 'package:cloud_firestore/cloud_firestore.dart';

/// Word category — drives the icon + color theme in the admin UI.
enum WordCategory { payment, contact, external, custom }

extension WordCategoryExt on WordCategory {
  String get wire {
    switch (this) {
      case WordCategory.payment:  return 'payment';
      case WordCategory.contact:  return 'contact';
      case WordCategory.external: return 'external';
      case WordCategory.custom:   return 'custom';
    }
  }

  String get hebrew {
    switch (this) {
      case WordCategory.payment:  return 'תשלום';
      case WordCategory.contact:  return 'קשר';
      case WordCategory.external: return 'אפליקציה חיצונית';
      case WordCategory.custom:   return 'מותאם';
    }
  }

  static WordCategory fromWire(String? s) {
    switch (s) {
      case 'payment':  return WordCategory.payment;
      case 'contact':  return WordCategory.contact;
      case 'external': return WordCategory.external;
      default:         return WordCategory.custom;
    }
  }
}

/// Severity — drives the action taken when the word is matched.
enum WordSeverity { low, medium, high, critical }

extension WordSeverityExt on WordSeverity {
  String get wire {
    switch (this) {
      case WordSeverity.low:      return 'low';
      case WordSeverity.medium:   return 'medium';
      case WordSeverity.high:     return 'high';
      case WordSeverity.critical: return 'critical';
    }
  }

  String get hebrew {
    switch (this) {
      case WordSeverity.low:      return 'נמוכה';
      case WordSeverity.medium:   return 'בינונית';
      case WordSeverity.high:     return 'גבוהה';
      case WordSeverity.critical: return 'קריטית';
    }
  }

  int get score {
    switch (this) {
      case WordSeverity.low:      return 15;
      case WordSeverity.medium:   return 35;
      case WordSeverity.high:     return 60;
      case WordSeverity.critical: return 90;
    }
  }

  static WordSeverity fromWire(String? s) {
    switch (s) {
      case 'low':      return WordSeverity.low;
      case 'medium':   return WordSeverity.medium;
      case 'high':     return WordSeverity.high;
      case 'critical': return WordSeverity.critical;
      default:         return WordSeverity.medium;
    }
  }
}

/// Action taken by the detection engine. Stored on every incident doc.
enum IncidentAction { allowed, warned, rewritten, blocked, suspended }

extension IncidentActionExt on IncidentAction {
  String get wire {
    switch (this) {
      case IncidentAction.allowed:   return 'allowed';
      case IncidentAction.warned:    return 'warned';
      case IncidentAction.rewritten: return 'rewritten';
      case IncidentAction.blocked:   return 'blocked';
      case IncidentAction.suspended: return 'suspended';
    }
  }

  String get hebrew {
    switch (this) {
      case IncidentAction.allowed:   return 'אושר';
      case IncidentAction.warned:    return 'אזהרה';
      case IncidentAction.rewritten: return 'הוחלף';
      case IncidentAction.blocked:   return 'נחסם';
      case IncidentAction.suspended: return 'חשבון הושעה';
    }
  }

  static IncidentAction fromWire(String? s) {
    switch (s) {
      case 'allowed':   return IncidentAction.allowed;
      case 'warned':    return IncidentAction.warned;
      case 'rewritten': return IncidentAction.rewritten;
      case 'blocked':   return IncidentAction.blocked;
      case 'suspended': return IncidentAction.suspended;
      default:          return IncidentAction.blocked;
    }
  }
}

// ── Models ──────────────────────────────────────────────────────────────────

class BlockedWord {
  BlockedWord({
    required this.id,
    required this.text,
    required this.category,
    required this.severity,
    this.notes = '',
    this.hits = 0,
    this.isActive = true,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String text;
  final WordCategory category;
  final WordSeverity severity;
  final String notes;
  final int hits;
  final bool isActive;
  final DateTime? createdAt;
  final String? createdBy;

  factory BlockedWord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final ts = d['createdAt'];
    return BlockedWord(
      id: doc.id,
      text: (d['text'] as String?) ?? '',
      category: WordCategoryExt.fromWire(d['category'] as String?),
      severity: WordSeverityExt.fromWire(d['severity'] as String?),
      notes: (d['notes'] as String?) ?? '',
      hits: (d['hits'] as num?)?.toInt() ?? 0,
      isActive: (d['isActive'] as bool?) ?? true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
      createdBy: d['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'text': text,
        'category': category.wire,
        'severity': severity.wire,
        'notes': notes,
        'hits': hits,
        'isActive': isActive,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (createdBy != null) 'createdBy': createdBy,
      };
}

class ChatGuardIncident {
  ChatGuardIncident({
    required this.id,
    required this.userId,
    required this.userName,
    required this.message,
    required this.matchedWords,
    required this.severity,
    required this.action,
    this.chatId,
    this.chatPartnerId,
    this.chatPartnerName,
    this.riskScore = 0,
    this.reviewed = false,
    this.timestamp,
  });

  final String id;
  final String userId;
  final String userName;
  final String? chatId;
  final String? chatPartnerId;
  final String? chatPartnerName;
  final String message;
  final List<String> matchedWords;
  final WordSeverity severity;
  final IncidentAction action;
  final int riskScore;
  final bool reviewed;
  final DateTime? timestamp;

  factory ChatGuardIncident.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final ts = d['timestamp'];
    final matched = d['matchedWords'];
    return ChatGuardIncident(
      id: doc.id,
      userId: (d['userId'] as String?) ?? '',
      userName: (d['userName'] as String?) ?? '—',
      chatId: d['chatId'] as String?,
      chatPartnerId: d['chatPartnerId'] as String?,
      chatPartnerName: d['chatPartnerName'] as String?,
      message: (d['message'] as String?) ?? '',
      matchedWords: matched is List
          ? matched.whereType<String>().toList()
          : const <String>[],
      severity: WordSeverityExt.fromWire(d['severity'] as String?),
      action: IncidentActionExt.fromWire(d['action'] as String?),
      riskScore: (d['riskScore'] as num?)?.toInt() ?? 0,
      reviewed: (d['reviewed'] as bool?) ?? false,
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class ChatGuardSettings {
  const ChatGuardSettings({
    this.sensitivity = 65,
    this.detectSpaces = true,
    this.detectLeetspeak = true,
    this.detectEmoji = true,
    this.detectPhoneNumbers = true,
    this.detectLinks = true,
    this.enabled = false,
  });

  /// Master kill-switch. Phase 3 (chat integration) reads this — while
  /// `false`, ChatGuard.check() returns `allowed` immediately. Starts false
  /// so Phase 1 can ship without any chat-side behavior change.
  final bool enabled;

  /// 0-100 — higher = more aggressive.
  final int sensitivity;
  final bool detectSpaces;
  final bool detectLeetspeak;
  final bool detectEmoji;
  final bool detectPhoneNumbers;
  final bool detectLinks;

  static const defaults = ChatGuardSettings();

  factory ChatGuardSettings.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return ChatGuardSettings(
      enabled: (d['enabled'] as bool?) ?? false,
      sensitivity: (d['sensitivity'] as num?)?.toInt() ?? 65,
      detectSpaces: (d['detectSpaces'] as bool?) ?? true,
      detectLeetspeak: (d['detectLeetspeak'] as bool?) ?? true,
      detectEmoji: (d['detectEmoji'] as bool?) ?? true,
      detectPhoneNumbers: (d['detectPhoneNumbers'] as bool?) ?? true,
      detectLinks: (d['detectLinks'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'enabled': enabled,
        'sensitivity': sensitivity,
        'detectSpaces': detectSpaces,
        'detectLeetspeak': detectLeetspeak,
        'detectEmoji': detectEmoji,
        'detectPhoneNumbers': detectPhoneNumbers,
        'detectLinks': detectLinks,
      };

  ChatGuardSettings copyWith({
    bool? enabled,
    int? sensitivity,
    bool? detectSpaces,
    bool? detectLeetspeak,
    bool? detectEmoji,
    bool? detectPhoneNumbers,
    bool? detectLinks,
  }) =>
      ChatGuardSettings(
        enabled: enabled ?? this.enabled,
        sensitivity: sensitivity ?? this.sensitivity,
        detectSpaces: detectSpaces ?? this.detectSpaces,
        detectLeetspeak: detectLeetspeak ?? this.detectLeetspeak,
        detectEmoji: detectEmoji ?? this.detectEmoji,
        detectPhoneNumbers: detectPhoneNumbers ?? this.detectPhoneNumbers,
        detectLinks: detectLinks ?? this.detectLinks,
      );

  // Value equality — crucial for the admin Settings tab so the
  // "Save changes" button correctly disables when there are no diffs
  // between `_draft` and the current Firestore snapshot. Without this,
  // identity equality treats every stream emission as a "different"
  // ChatGuardSettings even when the values are identical.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatGuardSettings
        && other.enabled == enabled
        && other.sensitivity == sensitivity
        && other.detectSpaces == detectSpaces
        && other.detectLeetspeak == detectLeetspeak
        && other.detectEmoji == detectEmoji
        && other.detectPhoneNumbers == detectPhoneNumbers
        && other.detectLinks == detectLinks;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        sensitivity,
        detectSpaces,
        detectLeetspeak,
        detectEmoji,
        detectPhoneNumbers,
        detectLinks,
      );
}
