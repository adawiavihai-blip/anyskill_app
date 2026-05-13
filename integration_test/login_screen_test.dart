// ⚠️ בדיקה זו רצה מול Firebase פרודקשן. אסור לכתוב בדיקות שיוצרות/משנות/מוחקות נתונים עד שנעבור ל-Emulator.
// ⚠️ This test runs against PRODUCTION Firebase. Read-only operations only — DO NOT add tests that create/modify/delete data here.
//
// תפקיד הקובץ: בדיקת רינדור של מסך הלוגין — מוודא שכל הרכיבים המרכזיים מופיעים.
// בודק 4 דברים בבת אחת: MaterialApp עלה, CTA "להתחברות" מופיע, כפתור Google מופיע,
// בורר השפה מציג "עברית", ויש לפחות שדה טקסט אחד (input הטלפון).
//
// Scope: Login screen render check — verifies all key UI elements are present.
// One testWidgets block (web flutter_drive limitation — see CLAUDE.md / project notes).

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anyskill_app/main.dart' as app;

// JS-interop: עוקף את ה-Watchdog של web/app_init.js (CLAUDE.md §9b Law 15).
// JS interop: bypasses the production Watchdog (CLAUDE.md §9b Law 15).
@JS('eval')
external JSAny? _jsEval(String script);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Login screen renders all core elements', (tester) async {
    // השתקת ה-Watchdog לפני boot.
    // Silence Watchdog before boot.
    _jsEval("window.sessionStorage.setItem('app_ready', '1');");

    // הפעלת האפליקציה האמיתית.
    // Boot the real app.
    app.main();

    // pump עם משך קצוב במקום pumpAndSettle (אנימציות אינסופיות במסך הלוגין).
    // Bounded pump instead of pumpAndSettle (login screen has infinite animations).
    await tester.pump(const Duration(seconds: 5));

    // 1. MaterialApp קיים — האפליקציה עלתה בכלל.
    // 1. MaterialApp exists — proves boot.
    expect(find.byType(MaterialApp), findsOneWidget);

    // 2. CTA הלוגין בעברית: "להתחברות" — מוכיח ששפת ברירת המחדל היא עברית.
    // 2. Hebrew CTA — proves localization defaulted to Hebrew.
    expect(find.text('להתחברות'), findsOneWidget);

    // 3. כפתור Google — חלק מליבת הלוגין.
    // 3. Google sign-in button (Hebrew label).
    expect(find.text('המשך עם Google'), findsOneWidget);

    // 4. בורר השפה מציג "עברית" — מוכיח ש-LocaleProvider עובד.
    // 4. Language switcher shows "עברית" — proves LocaleProvider works.
    expect(find.text('עברית'), findsAtLeastNWidgets(1));

    // 5. לפחות שדה קלט אחד (input הטלפון).
    // 5. At least one input field (phone input).
    expect(find.byType(TextField), findsAtLeastNWidgets(1));
  });
}
