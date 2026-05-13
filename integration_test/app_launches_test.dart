// ⚠️ בדיקה זו רצה מול Firebase פרודקשן. אסור לכתוב בדיקות שיוצרות/משנות/מוחקות נתונים עד שנעבור ל-Emulator.
// ⚠️ This test runs against PRODUCTION Firebase. Do NOT write tests that create/modify/delete data until we migrate to the Firebase Emulator Suite.
//
// תפקיד הקובץ: Smoke test ראשון לאפליקציה — מוודא שהאפליקציה מצליחה לעלות בלי לקרוס.
// Scope: Boot-up smoke test — verifies the app launches without throwing.

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// יבוא של נקודת הכניסה האמיתית של האפליקציה.
// Imports the real app entry point so we can call app.main() inside the test.
import 'package:anyskill_app/main.dart' as app;

// JS-interop: גישה ל-eval כדי לעקוף את ה-Watchdog של web/app_init.js
// (CLAUDE.md §9b Law 15) שעושה location.reload() אם sessionStorage['app_ready']
// לא נכתב תוך 10 שניות. ב-test mode הדגל הזה לא נכתב באופן טבעי, אז ה-reload
// הורג את החיבור של flutter drive והבדיקה תוקעת.
// JS interop helper to bypass the production Watchdog timer in web/app_init.js
// (CLAUDE.md §9b Law 15) — without it, the page reloads mid-test and the
// flutter drive WebSocket disconnects, leaving the test runner hanging.
@JS('eval')
external JSAny? _jsEval(String script);

void _suppressProductionWatchdog() {
  _jsEval("window.sessionStorage.setItem('app_ready', '1');");
}

void main() {
  // אתחול ה-binding של integration_test — חובה לפני כל testWidgets בבדיקות E2E.
  // Required initializer for integration_test bindings.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches without crashing', (tester) async {
    // ראשון לכל דבר: לעצור את ה-Watchdog. הוא התחיל countdown של 10 שניות
    // ברגע שהדף נטען — אנחנו חייבים לכתוב את הדגל לפני שהוא יורה.
    // FIRST thing: silence the Watchdog. Its 10s countdown started at page
    // load — we must set the flag before it fires.
    _suppressProductionWatchdog();

    // הפעלת האפליקציה האמיתית (Firebase init + Sentry + Stripe + ...).
    // Boot the real app — same entry as production.
    app.main();

    // ⚠️ חשוב: לא משתמשים ב-pumpAndSettle כי מסך הלוגין (CLAUDE.md §30) מכיל
    // אנימציות אינסופיות (orbs, pulses, shimmer) שלעולם לא נרגעות —
    // pumpAndSettle היה תקוע לנצח. במקום זה — pump עם משך קצוב שמספיק
    // לאתחול Firebase/Sentry/Stripe ולרינדור הראשון של ה-MaterialApp.
    // ⚠️ NOT pumpAndSettle: the login screen (CLAUDE.md §30) has continuous
    // animations (orbs, pulses, shimmer) that never settle. Use a fixed-duration
    // pump that's long enough for Firebase/Sentry/Stripe init + first frame.
    await tester.pump(const Duration(seconds: 5));

    // ההוכחה היחידה שהאפליקציה לא קרסה — קיים MaterialApp במסך.
    // Sole assertion: a MaterialApp survived the boot. Anything else (login screen,
    // home screen, splash) is acceptable — we only care that something rendered.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
