import 'package:cloud_firestore/cloud_firestore.dart';

/// The type of log entry — determines which Firestore collection receives it.
enum LogType {
  /// App crashes, Firebase failures, unhandled exceptions.
  error,

  /// Key business actions: provider verified, story uploaded, category deleted.
  activity,

  /// Login, logout, failed auth attempts, token refresh failures.
  auth,
}

/// Severity level for error logs.
enum LogSeverity { fatal, warning, info }

/// Immutable log entry. Created in-memory, flushed to Firestore in batches.
class AppLog {
  final LogType type;
  final LogSeverity severity;
  final String title;
  final String message;
  final String? errorCode;
  final String? stackTrace;
  final String? screen;
  final String userId;
  final String platform;
  final String appVersion;
  final DateTime timestamp;
  final Map<String, dynamic> extra;

  const AppLog({
    required this.type,
    this.severity = LogSeverity.info,
    required this.title,
    this.message = '',
    this.errorCode,
    this.stackTrace,
    this.screen,
    this.userId = '',
    this.platform = '',
    this.appVersion = '',
    required this.timestamp,
    this.extra = const {},
  });

  // ── Convenience factories ─────────────────────────────────────────────

  /// Create an error log from an exception.
  factory AppLog.error({
    required Object error,
    StackTrace? stack,
    LogSeverity severity = LogSeverity.fatal,
    String? screen,
    String userId = '',
    String platform = '',
    String appVersion = '',
  }) {
    final errStr = error.toString();
    return AppLog(
      type:       LogType.error,
      severity:   severity,
      title:      error.runtimeType.toString(),
      message:    errStr.substring(0, errStr.length.clamp(0, 500)),
      errorCode:  error.runtimeType.toString(),
      stackTrace: stack?.toString().substring(
          0, (stack.toString().length).clamp(0, 500)),
      screen:     screen,
      userId:     userId,
      platform:   platform,
      appVersion: appVersion,
      timestamp:  DateTime.now(),
    );
  }

  /// Create an activity log for a business event.
  factory AppLog.activity({
    required String title,
    String detail = '',
    String userId = '',
    String platform = '',
    String appVersion = '',
    String? screen,
    Map<String, dynamic> extra = const {},
  }) {
    return AppLog(
      type:       LogType.activity,
      severity:   LogSeverity.info,
      title:      title,
      message:    detail,
      userId:     userId,
      platform:   platform,
      appVersion: appVersion,
      screen:     screen,
      timestamp:  DateTime.now(),
      extra:      extra,
    );
  }

  /// Create an auth log.
  factory AppLog.auth({
    required String title,
    String detail = '',
    LogSeverity severity = LogSeverity.info,
    String userId = '',
    String platform = '',
    String appVersion = '',
  }) {
    return AppLog(
      type:       LogType.auth,
      severity:   severity,
      title:      title,
      message:    detail,
      userId:     userId,
      platform:   platform,
      appVersion: appVersion,
      timestamp:  DateTime.now(),
    );
  }

  // ── Firestore serialisation ───────────────────────────────────────────

  factory AppLog.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AppLog(
      type:       LogType.values.firstWhere(
          (t) => t.name == (d['type'] as String? ?? 'error'),
          orElse: () => LogType.error),
      severity:   LogSeverity.values.firstWhere(
          (s) => s.name == (d['severity'] as String? ?? 'info'),
          orElse: () => LogSeverity.info),
      title:      d['title']      as String? ?? '',
      message:    d['message']    as String? ?? '',
      errorCode:  d['errorCode']  as String?,
      stackTrace: d['stackTrace'] as String?,
      screen:     d['screen']     as String?,
      userId:     d['userId']     as String? ?? '',
      platform:   d['platform']   as String? ?? '',
      appVersion: d['appVersion'] as String? ?? '',
      timestamp:  (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      extra:      (d['extra']     as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'type':       type.name,
    'severity':   severity.name,
    'title':      title,
    'message':    message,
    if (errorCode != null)  'errorCode':  errorCode,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (screen != null)     'screen':     screen,
    'userId':     userId,
    'platform':   platform,
    'appVersion': appVersion,
    'timestamp':  Timestamp.fromDate(timestamp),
    if (extra.isNotEmpty) 'extra': extra,
  };

  /// The Firestore collection this log should be written to.
  String get collection {
    switch (type) {
      case LogType.error:    return 'error_logs';
      case LogType.activity: return 'activity_log';
      case LogType.auth:     return 'auth_logs';
    }
  }
}
