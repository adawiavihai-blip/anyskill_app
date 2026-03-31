// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:anyskill_app/models/app_log.dart';
import 'package:anyskill_app/repositories/logger_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: Watchtower logging system (AppLog model + batch flush)
//
// Run:  flutter test test/unit/watchtower_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. AppLog MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('AppLog model', () {
    test('error factory captures exception type and message', () {
      final log = AppLog.error(
        error:    FormatException('bad input'),
        severity: LogSeverity.fatal,
        screen:   'home_screen',
        userId:   'u1',
      );

      expect(log.type,      LogType.error);
      expect(log.severity,  LogSeverity.fatal);
      expect(log.title,     'FormatException');
      expect(log.errorCode, 'FormatException');
      expect(log.message,   contains('bad input'));
      expect(log.screen,    'home_screen');
      expect(log.userId,    'u1');
      expect(log.collection, 'error_logs');
    });

    test('error factory truncates long messages to 500 chars', () {
      final longMsg = 'x' * 1000;
      final log = AppLog.error(error: Exception(longMsg));
      expect(log.message.length, lessThanOrEqualTo(500));
    });

    test('error factory captures stack trace (truncated)', () {
      final log = AppLog.error(
        error: Exception('test'),
        stack: StackTrace.current,
      );
      expect(log.stackTrace, isNotNull);
      expect(log.stackTrace!.length, lessThanOrEqualTo(500));
    });

    test('activity factory sets correct type and collection', () {
      final log = AppLog.activity(
        title:  '📱 סטורי חדש: דנה',
        detail: 'שירות: ניקיון',
        extra:  {'serviceType': 'ניקיון'},
      );

      expect(log.type,       LogType.activity);
      expect(log.severity,   LogSeverity.info);
      expect(log.title,      '📱 סטורי חדש: דנה');
      expect(log.message,    'שירות: ניקיון');
      expect(log.extra,      {'serviceType': 'ניקיון'});
      expect(log.collection, 'activity_log');
    });

    test('auth factory sets correct type and collection', () {
      final log = AppLog.auth(
        title:    'login_failed',
        detail:   'wrong password',
        severity: LogSeverity.warning,
        userId:   'u2',
      );

      expect(log.type,       LogType.auth);
      expect(log.severity,   LogSeverity.warning);
      expect(log.title,      'login_failed');
      expect(log.userId,     'u2');
      expect(log.collection, 'auth_logs');
    });

    test('collection routing is correct for each type', () {
      expect(
        AppLog.error(error: Exception('x')).collection,
        'error_logs',
      );
      expect(
        AppLog.activity(title: 'x').collection,
        'activity_log',
      );
      expect(
        AppLog.auth(title: 'x').collection,
        'auth_logs',
      );
    });

    test('toJson includes all fields and omits nulls', () {
      final log = AppLog.activity(title: 'test', detail: 'detail');
      final json = log.toJson();

      expect(json['type'],     'activity');
      expect(json['severity'], 'info');
      expect(json['title'],    'test');
      expect(json['message'],  'detail');
      expect(json.containsKey('errorCode'),  false); // null omitted
      expect(json.containsKey('stackTrace'), false); // null omitted
    });

    test('toJson includes errorCode and stackTrace for errors', () {
      final log = AppLog.error(
        error: StateError('bad state'),
        stack: StackTrace.current,
      );
      final json = log.toJson();

      expect(json['errorCode'],  'StateError');
      expect(json['stackTrace'], isNotNull);
    });

    test('fromFirestore round-trips correctly', () async {
      final db = FakeFirebaseFirestore();
      final original = AppLog.activity(
        title:  'test_event',
        detail: 'some detail',
        userId: 'u1',
        extra:  {'key': 'value'},
      );

      final json = original.toJson();
      await db.collection('activity_log').doc('t1').set(json);

      final doc = await db.collection('activity_log').doc('t1').get();
      final loaded = AppLog.fromFirestore(doc);

      expect(loaded.type,    LogType.activity);
      expect(loaded.title,   'test_event');
      expect(loaded.message, 'some detail');
      expect(loaded.userId,  'u1');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Watchtower BUFFER
  // ═══════════════════════════════════════════════════════════════════════════

  group('Watchtower buffer', () {
    late Watchtower wt;

    setUp(() {
      wt = Watchtower.test();
      Watchtower.initForTest(wt);
    });

    test('starts with empty buffer', () {
      expect(wt.buffer, isEmpty);
    });

    test('log() adds entry to buffer', () {
      wt.log(AppLog.activity(title: 'test'));
      expect(wt.buffer.length, 1);
      expect(wt.buffer.first.title, 'test');
    });

    test('activity() convenience adds activity log', () {
      wt.activity('Provider Verified', detail: 'uid=abc');
      expect(wt.buffer.length, 1);
      expect(wt.buffer.first.type, LogType.activity);
      expect(wt.buffer.first.title, 'Provider Verified');
    });

    test('authEvent() convenience adds auth log', () {
      wt.authEvent('login_success');
      expect(wt.buffer.length, 1);
      expect(wt.buffer.first.type, LogType.auth);
    });

    test('error() convenience adds error log', () {
      wt.error(FormatException('bad'), screen: 'test_screen');
      expect(wt.buffer.length, 1);
      expect(wt.buffer.first.type, LogType.error);
      expect(wt.buffer.first.screen, 'test_screen');
    });

    test('buffer caps at 100 entries (drops oldest)', () {
      for (int i = 0; i < 110; i++) {
        wt.log(AppLog.activity(title: 'log_$i'));
      }
      expect(wt.buffer.length, lessThanOrEqualTo(100));
      // Oldest entries should be dropped
      expect(wt.buffer.first.title, isNot('log_0'));
    });

    test('flush is no-op on test instance (no Firestore)', () async {
      wt.activity('a');
      wt.activity('b');
      expect(wt.buffer.length, 2);

      await wt.flush(); // db is null → early return, buffer untouched
      expect(wt.buffer.length, 2); // entries stay since there's no db to flush to
    });

    test('multiple log types coexist in buffer', () {
      wt.error(Exception('crash'));
      wt.activity('uploaded');
      wt.authEvent('login');

      expect(wt.buffer.length, 3);
      expect(wt.buffer[0].type, LogType.error);
      expect(wt.buffer[1].type, LogType.activity);
      expect(wt.buffer[2].type, LogType.auth);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Watchtower FIRESTORE FLUSH
  // ═══════════════════════════════════════════════════════════════════════════

  group('Watchtower Firestore flush', () {
    test('flush writes logs to correct collections', () async {
      final db = FakeFirebaseFirestore();
      Watchtower.initForTest(Watchtower.test());
      // Create a real-ish instance with fake Firestore
      final wt = Watchtower.withFirestore(firestore: db);

      wt.log(AppLog.error(error: Exception('crash1')));
      wt.log(AppLog.activity(title: 'upload1'));
      wt.log(AppLog.auth(title: 'login1'));

      await wt.flush();

      final errors = await db.collection('error_logs').get();
      final activities = await db.collection('activity_log').get();
      final auths = await db.collection('auth_logs').get();

      expect(errors.docs.length,     1);
      expect(activities.docs.length, 1);
      expect(auths.docs.length,      1);

      expect(errors.docs.first.data()['title'],     contains('Exception'));
      expect(activities.docs.first.data()['title'],  'upload1');
      expect(auths.docs.first.data()['title'],       'login1');

      // Buffer should be empty after flush
      expect(wt.buffer, isEmpty);

      await wt.dispose();
    });

    test('flush handles empty buffer gracefully', () async {
      final db = FakeFirebaseFirestore();
      final wt = Watchtower.withFirestore(firestore: db);

      await wt.flush(); // no-op, no error
      expect(wt.buffer, isEmpty);

      await wt.dispose();
    });

    test('multiple flushes write independently', () async {
      final db = FakeFirebaseFirestore();
      final wt = Watchtower.withFirestore(firestore: db);

      wt.activity('batch1');
      await wt.flush();

      wt.activity('batch2');
      wt.activity('batch3');
      await wt.flush();

      final all = await db.collection('activity_log').get();
      expect(all.docs.length, 3);

      await wt.dispose();
    });
  });
}

