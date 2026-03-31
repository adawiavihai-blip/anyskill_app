import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, visibleForTesting,
    defaultTargetPlatform;

import '../models/app_log.dart';

/// Centralized logging system with batched Firestore writes.
///
/// Collects logs in a memory buffer and flushes every [_flushInterval]
/// or when the buffer reaches [_maxBatchSize]. This prevents:
///   - One Firestore write per log (cost explosion)
///   - Blocking the UI thread on error handlers
///
/// Usage:
/// ```dart
/// Watchtower.instance.log(AppLog.error(error: e, stack: stack));
/// Watchtower.instance.activity('Story uploaded', detail: 'user=abc');
/// Watchtower.instance.authEvent('login_success', userId: uid);
/// ```
class Watchtower {
  Watchtower._({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db   = firestore ?? FirebaseFirestore.instance,
        _auth = auth      ?? FirebaseAuth.instance {
    _timer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Test-only constructor — no Firebase, no timer, no buffer flush.
  @visibleForTesting
  Watchtower.test()
      : _db   = null,
        _auth = null,
        _timer = null;

  /// Test-only constructor with a real (fake) Firestore for flush tests.
  @visibleForTesting
  Watchtower.withFirestore({required FirebaseFirestore firestore})
      : _db   = firestore,
        _auth = null,
        _timer = null;

  static Watchtower? _instance;

  /// Global singleton. Call [init] before first use.
  static Watchtower get instance {
    assert(_instance != null, 'Call Watchtower.init() in main() first');
    return _instance!;
  }

  /// Initialize the singleton. Safe to call multiple times.
  static void init({FirebaseFirestore? firestore, FirebaseAuth? auth}) {
    _instance ??= Watchtower._(firestore: firestore, auth: auth);
  }

  /// Replace the singleton with a test instance.
  @visibleForTesting
  static void initForTest(Watchtower testInstance) {
    _instance = testInstance;
  }

  final FirebaseFirestore? _db;
  final FirebaseAuth?      _auth;
  Timer?                   _timer;

  // ── Configuration ─────────────────────────────────────────────────────

  static const _flushInterval = Duration(seconds: 10);
  static const _maxBatchSize  = 20;
  static const _maxBufferSize = 100; // drop oldest if buffer overflows

  // ── Buffer ────────────────────────────────────────────────────────────

  final List<AppLog> _buffer = [];

  @visibleForTesting
  List<AppLog> get buffer => List.unmodifiable(_buffer);

  /// Platform string for log entries.
  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Current user ID (empty string if not logged in).
  String get _userId => _auth?.currentUser?.uid ?? '';

  // ── Public API ────────────────────────────────────────────────────────

  /// Add any [AppLog] to the buffer. Flushed automatically.
  void log(AppLog entry) {
    // Enrich with runtime context if not already set
    final enriched = AppLog(
      type:       entry.type,
      severity:   entry.severity,
      title:      entry.title,
      message:    entry.message,
      errorCode:  entry.errorCode,
      stackTrace: entry.stackTrace,
      screen:     entry.screen,
      userId:     entry.userId.isNotEmpty ? entry.userId : _userId,
      platform:   entry.platform.isNotEmpty ? entry.platform : _platform,
      appVersion: entry.appVersion,
      timestamp:  entry.timestamp,
      extra:      entry.extra,
    );

    _buffer.add(enriched);

    // Prevent memory leak on log storms
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeRange(0, _buffer.length - _maxBufferSize);
    }

    // Flush immediately if batch is full
    if (_buffer.length >= _maxBatchSize) {
      flush();
    }
  }

  /// Convenience: log a business activity.
  void activity(String title, {String detail = '', Map<String, dynamic> extra = const {}}) {
    log(AppLog.activity(title: title, detail: detail, extra: extra));
  }

  /// Convenience: log an auth event.
  void authEvent(String title, {String detail = '', LogSeverity severity = LogSeverity.info}) {
    log(AppLog.auth(title: title, detail: detail, severity: severity));
  }

  /// Convenience: log an error with stack trace.
  void error(Object error, {StackTrace? stack, String? screen, LogSeverity severity = LogSeverity.fatal}) {
    log(AppLog.error(error: error, stack: stack, screen: screen, severity: severity));
  }

  // ── Flush ─────────────────────────────────────────────────────────────

  /// Write all buffered logs to Firestore in a single batch.
  /// Called automatically by the timer, or manually for immediate writes.
  Future<void> flush() async {
    if (_buffer.isEmpty || _db == null) return;

    // Snapshot and clear — so new logs during write go to next batch
    final batch = List<AppLog>.from(_buffer);
    _buffer.clear();

    try {
      final writeBatch = _db.batch();
      for (final entry in batch) {
        final ref = _db.collection(entry.collection).doc();
        writeBatch.set(ref, entry.toJson());
      }
      await writeBatch.commit();
    } catch (e) {
      // Log flush failed — put entries back for next attempt (once only)
      debugPrint('[Watchtower] flush failed ($e), ${batch.length} entries re-queued');
      _buffer.insertAll(0, batch);
    }
  }

  /// Flush and stop the timer. Call in app lifecycle dispose.
  Future<void> dispose() async {
    _timer?.cancel();
    await flush();
  }
}
