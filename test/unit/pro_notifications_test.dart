// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: AnySkill Pro Phase 2 — notification fan-out shape.
//
// Mirrors functions/pro_service.js :: _notifyProviderTransition. We verify:
//   1. A grant transition writes:
//        notifications/{id}  with type='pro_granted' + Hebrew title/body
//        mail/{id}           with to=email + subject + html (grant template)
//   2. A revoke transition writes the above with type='pro_revoked' and the
//      revoke email template (subject starts with "עדכון לגבי").
//   3. Missing FCM token → we still write notifications + mail (durable
//      delivery doesn't depend on push).
//   4. Missing email → we skip the mail doc cleanly (no crash).
//   5. Revocation-reason logic writes the correct Hebrew reason + recovery
//      tip for each failure mode (cancellations, rating, orders, response).
//
// Run:  flutter test test/unit/pro_notifications_test.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── Logic under test — mirrors pro_service.js + pro_email_templates.js ─────

class _Metrics {
  final double rating;
  final int    completedDeals;
  final int    avgResponseTime;
  final int    cancellations;
  // Thresholds are hard-coded for tests — matches the production default
  // in system_settings/pro. Tests that need different thresholds would
  // extend this class; no current test needs that.
  static const double _minRating          = 4.8;
  static const int    _minOrders          = 20;
  static const int    _maxResponseMinutes = 15;
  double get minRating          => _minRating;
  int    get minOrders          => _minOrders;
  int    get maxResponseMinutes => _maxResponseMinutes;
  const _Metrics({
    required this.rating,
    required this.completedDeals,
    required this.avgResponseTime,
    required this.cancellations,
  });
}

/// Mirrors getRevocationCopy() in pro_email_templates.js.
({String reason, String tip}) _getRevocationCopy(_Metrics m) {
  if (m.cancellations > 0) {
    return (
      reason: 'רשמנו ${m.cancellations} ביטול/ים מצדך ב-30 הימים האחרונים.',
      tip:    'הימנע מקבלת עסקאות שאתה לא בטוח שתוכל לעמוד בהן. כשעוברים 30 יום ללא ביטולים — התג חוזר אוטומטית.',
    );
  }
  if (m.rating < m.minRating) {
    return (
      reason: 'הדירוג הממוצע שלך ירד ל-${m.rating.toStringAsFixed(1)}, מתחת לסף של ${m.minRating}.',
      tip:    'התמקד בתקשורת מעולה עם הלקוחות ובאיכות השירות. כל דירוג חיובי חדש יעלה את הממוצע שלך.',
    );
  }
  if (m.completedDeals < m.minOrders) {
    return (
      reason: 'השלמת ${m.completedDeals} עסקאות מתוך ${m.minOrders} הנדרשות.',
      tip:    'המשך לקבל ולסיים עסקאות בהצלחה. ברגע שתגיע ל-${m.minOrders} עסקאות מושלמות — תוכל לזכות בתג.',
    );
  }
  if (m.avgResponseTime > m.maxResponseMinutes) {
    return (
      reason: 'זמן התגובה הממוצע שלך עלה ל-${m.avgResponseTime} דקות, מעל הסף של ${m.maxResponseMinutes} דקות.',
      tip:    'הפעל התראות מיידיות באפליקציה וענה לפניות חדשות בהקדם האפשרי. גם תגובה קצרה של \'אחזור אליך בקרוב\' נספרת.',
    );
  }
  return (
    reason: 'לא עמדת באחד מהקריטריונים של AnySkill Pro.',
    tip:    'בדוק את הדשבורד שלך לפרטים המדויקים.',
  );
}

/// Mirrors _notifyProviderTransition() in pro_service.js.
Future<void> _notifyProviderTransition(
  FakeFirebaseFirestore db, {
  required String uid,
  required String providerName,
  required String? fcmToken,
  required String? email,
  required bool   isPro,
  required _Metrics metrics,
}) async {
  final title = isPro
      ? '🏆 קיבלת את תג AnySkill Pro!'
      : '💙 עדכון לגבי תג AnySkill Pro שלך';
  final body = isPro
      ? 'מזל טוב, $providerName! הצטרפת למועדון Pro של AnySkill.'
      : '$providerName, התג הוסר זמנית. תוכל/י לחזור אליו — בדוק/י את הדשבורד לפרטים.';

  // 1. In-app notification
  await db.collection('notifications').add({
    'userId':    uid,
    'title':     title,
    'body':      body,
    'type':      isPro ? 'pro_granted' : 'pro_revoked',
    'isRead':    false,
    'createdAt': Timestamp.now(),
  });

  // 2. FCM push — in the JS code this is admin.messaging().send; in tests we
  // verify the GATING (has token → would send; no token → skipped) by
  // leaving a marker doc so the test can assert path coverage without a
  // real FCM mock.
  if (fcmToken != null && fcmToken.isNotEmpty) {
    await db.collection('_test_fcm_sends').add({
      'to': fcmToken,
      'uid': uid,
      'title': title,
      'body':  body,
    });
  }

  // 3. Mail via Trigger Email extension
  if (email != null && email.contains('@')) {
    final subject = isPro
        ? '🏆 מזל טוב! קיבלת את תג AnySkill Pro'
        : 'עדכון לגבי תג AnySkill Pro שלך';
    String html;
    if (isPro) {
      html = '<html dir="rtl" lang="he">'
             '<body>תבנית הענקה עבור $providerName</body></html>';
    } else {
      final copy = _getRevocationCopy(metrics);
      html = '<html dir="rtl" lang="he">'
             '<body>שלום $providerName — '
             '${copy.reason} '
             '${copy.tip}</body></html>';
    }
    await db.collection('mail').add({
      'to':      email,
      'message': {'subject': subject, 'html': html},
    });
  }
}

// ── Test fixtures ───────────────────────────────────────────────────────────

const _defaultMetrics = _Metrics(
  rating: 4.9,
  completedDeals: 30,
  avgResponseTime: 5,
  cancellations: 0,
);

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('Pro notifications fan-out — invariants', () {
    test('GRANT: writes notifications/ + mail/ + fcm send with Hebrew grant subject',
        () async {
      final db = FakeFirebaseFirestore();
      await _notifyProviderTransition(
        db,
        uid:          'p_grant',
        providerName: 'אבישי',
        fcmToken:     'test_token_xyz',
        email:        'provider@example.com',
        isPro:        true,
        metrics:      _defaultMetrics,
      );

      final notifs = await db.collection('notifications').get();
      expect(notifs.docs, hasLength(1));
      final n = notifs.docs.first.data();
      expect(n['userId'],   equals('p_grant'));
      expect(n['type'],     equals('pro_granted'));
      expect(n['isRead'],   isFalse);
      expect(n['title'],    contains('תג AnySkill Pro'));
      expect(n['body'],     contains('אבישי'));

      final mail = await db.collection('mail').get();
      expect(mail.docs, hasLength(1));
      final m = mail.docs.first.data();
      expect(m['to'], equals('provider@example.com'));
      expect((m['message'] as Map)['subject'], startsWith('🏆'));
      expect((m['message'] as Map)['html'],    contains('dir="rtl"'));
      expect((m['message'] as Map)['html'],    contains('אבישי'));

      final fcm = await db.collection('_test_fcm_sends').get();
      expect(fcm.docs, hasLength(1));
      expect(fcm.docs.first.data()['to'], equals('test_token_xyz'));
    });

    test('REVOKE: email subject "עדכון לגבי..." + revocation copy embedded',
        () async {
      final db = FakeFirebaseFirestore();
      await _notifyProviderTransition(
        db,
        uid:          'p_revoke',
        providerName: 'דנה',
        fcmToken:     'token_123',
        email:        'dana@example.com',
        isPro:        false,
        metrics: const _Metrics(
          rating: 4.5, completedDeals: 30,
          avgResponseTime: 5, cancellations: 0,
        ),
      );

      final notifs = await db.collection('notifications').get();
      expect(notifs.docs.first.data()['type'], equals('pro_revoked'));

      final mail = await db.collection('mail').get();
      final m = mail.docs.first.data();
      expect((m['message'] as Map)['subject'],
          equals('עדכון לגבי תג AnySkill Pro שלך'));
      // Revocation reason (rating) + recovery tip must appear in HTML body.
      expect((m['message'] as Map)['html'],
          contains('הדירוג הממוצע שלך ירד ל-4.5'));
      expect((m['message'] as Map)['html'],
          contains('תקשורת מעולה'));
    });

    test('REVOKE with cancellation: copy cites the cancellation, not rating',
        () async {
      final db = FakeFirebaseFirestore();
      await _notifyProviderTransition(
        db,
        uid:          'p_rev_cancel',
        providerName: 'יוסי',
        fcmToken:     null,
        email:        'yossi@example.com',
        isPro:        false,
        metrics: const _Metrics(
          rating: 4.9,            // rating would pass
          completedDeals: 30,     // orders would pass
          avgResponseTime: 5,     // response would pass
          cancellations: 1,       // but 1 cancellation wins
        ),
      );

      final mail = await db.collection('mail').get();
      final html = (mail.docs.first.data()['message'] as Map)['html'] as String;
      expect(html, contains('רשמנו 1 ביטול'));
      expect(html, isNot(contains('הדירוג הממוצע שלך ירד')));
    });

    test('No FCM token: notifications + mail still written, zero FCM sends',
        () async {
      final db = FakeFirebaseFirestore();
      await _notifyProviderTransition(
        db,
        uid:          'p_no_token',
        providerName: 'מאיה',
        fcmToken:     null,       // <── missing
        email:        'maya@example.com',
        isPro:        true,
        metrics:      _defaultMetrics,
      );

      expect((await db.collection('notifications').get()).docs, hasLength(1));
      expect((await db.collection('mail').get()).docs,          hasLength(1));
      expect((await db.collection('_test_fcm_sends').get()).docs, isEmpty,
          reason: 'FCM path must be skipped when token is null');
    });

    test('No email: notifications + FCM still written, zero mail docs',
        () async {
      final db = FakeFirebaseFirestore();
      await _notifyProviderTransition(
        db,
        uid:          'p_no_email',
        providerName: 'רון',
        fcmToken:     'token_abc',
        email:        null,       // <── missing
        isPro:        true,
        metrics:      _defaultMetrics,
      );

      expect((await db.collection('notifications').get()).docs, hasLength(1));
      expect((await db.collection('mail').get()).docs,          isEmpty,
          reason: 'Mail must be skipped when email is null');
      expect((await db.collection('_test_fcm_sends').get()).docs, hasLength(1));
    });

    test('Invalid email ("not-an-email"): mail skipped', () async {
      final db = FakeFirebaseFirestore();
      await _notifyProviderTransition(
        db,
        uid: 'p_bad_email', providerName: 'X',
        fcmToken: null, email: 'not-an-email', isPro: true,
        metrics: _defaultMetrics,
      );
      expect((await db.collection('mail').get()).docs, isEmpty);
    });

    test('Revocation copy: insufficient_orders reason fires when only orders fail',
        () async {
      final copy = _getRevocationCopy(const _Metrics(
        rating: 4.9,
        completedDeals: 10,
        avgResponseTime: 5,
        cancellations: 0,
      ));
      expect(copy.reason, contains('השלמת 10 עסקאות מתוך 20'));
      expect(copy.tip,    contains('המשך לקבל ולסיים'));
    });

    test('Revocation copy: slow_response reason fires when only response fails',
        () async {
      final copy = _getRevocationCopy(const _Metrics(
        rating: 4.9,
        completedDeals: 30,
        avgResponseTime: 25,   // > 15
        cancellations: 0,
      ));
      expect(copy.reason, contains('זמן התגובה'));
      expect(copy.tip,    contains('התראות מיידיות'));
    });
  });
}
