import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyskill_app/utils/expert_filter.dart';
import 'package:anyskill_app/screens/category_results_screen.dart';

// ── נתוני בדיקה ──────────────────────────────────────────────────────────────
final List<Map<String, dynamic>> _fakeExperts = [
  {'name': 'משה לוי',   'pricePerHour': 80,  'isOnline': true,  'isVerified': false, 'uid': '1'},
  {'name': 'שרה כהן',   'pricePerHour': 120, 'isOnline': false, 'isVerified': true,  'uid': '2'},
  {'name': 'דוד ישראלי','pricePerHour': 90,  'isOnline': true,  'isVerified': false, 'uid': '3'},
  {'name': 'רחל מזרחי', 'pricePerHour': 200, 'isOnline': false, 'isVerified': true,  'uid': '4'},
  {'name': 'יוסי אברהם','pricePerHour': 50,  'isOnline': true,  'isVerified': false, 'uid': '5'},
];

// ── עוזר: בונה widget עם זרם מוזרק ──────────────────────────────────────────
Widget _buildScreen({List<Map<String, dynamic>>? experts}) {
  final stream = Stream.value(experts ?? _fakeExperts);
  return MaterialApp(
    home: CategoryResultsScreen(
      categoryName: 'אימון כושר',
      testStream: stream,
    ),
  );
}

void main() {

  // ══════════════════════════════════════════════════════════════════════════
  // חלק א׳: בדיקות יחידה לפונקציית הסינון הטהורה
  // ══════════════════════════════════════════════════════════════════════════
  group('filterExperts — unit tests', () {

    test('ללא פילטרים — מחזיר את כולם', () {
      final result = filterExperts(_fakeExperts);
      expect(result.length, 5);
    });

    test('חיפוש שם "משה" — תוצאה אחת', () {
      final result = filterExperts(_fakeExperts, query: 'משה');
      expect(result.length, 1);
      expect(result.first['name'], 'משה לוי');
    });

    test('חיפוש שם — לא רגיש לרישיות', () {
      final result = filterExperts(_fakeExperts, query: 'כהן');
      expect(result.length, 1);
      expect(result.first['name'], 'שרה כהן');
    });

    test('חיפוש שם חלקי — מוצא מספר תוצאות', () {
      // 'י' נמצא ב-"דוד ישראלי", "רחל מזרחי", "יוסי אברהם"
      final result = filterExperts(_fakeExperts, query: 'י');
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('חיפוש שם שלא קיים — רשימה ריקה', () {
      final result = filterExperts(_fakeExperts, query: 'שם_לא_קיים_XYZ');
      expect(result, isEmpty);
    });

    test('פילטר עד 100 ₪ — מסנן נכון (80, 90, 50 עוברים; 120, 200 לא)', () {
      final result = filterExperts(_fakeExperts, underHundred: true);
      expect(result.length, 3);
      for (final e in result) {
        expect((e['pricePerHour'] as num).toDouble(), lessThan(100));
      }
    });

    test('פילטר עד 100 ₪ — לא כולל בדיוק 100', () {
      final data = [
        {'name': 'בדיוק 100', 'pricePerHour': 100},
        {'name': 'מתחת 100',  'pricePerHour': 99},
      ];
      final result = filterExperts(data, underHundred: true);
      expect(result.length, 1);
      expect(result.first['name'], 'מתחת 100');
    });

    test('שילוב — שם + עד 100 ₪', () {
      // "משה לוי" — 80 ₪ → עובר שניהם
      // "דוד ישראלי" — 90 ₪ → עובר שניהם
      final result = filterExperts(
        _fakeExperts,
        query: 'י',        // דוד ישראלי, רחל מזרחי, יוסי אברהם
        underHundred: true, // מסנן רחל (200 ₪)
      );
      for (final e in result) {
        expect((e['pricePerHour'] as num).toDouble(), lessThan(100));
        expect(
          (e['name'] as String).toLowerCase(),
          contains('י'),
        );
      }
    });

    test('פילטר עם מחיר כ-String', () {
      final data = [
        {'name': 'מומחה A', 'pricePerHour': '80'},
        {'name': 'מומחה B', 'pricePerHour': '150'},
      ];
      final result = filterExperts(data, underHundred: true);
      expect(result.length, 1);
      expect(result.first['name'], 'מומחה A');
    });

    test('רשימה ריקה — מחזיר ריק', () {
      expect(filterExperts([], query: 'משה', underHundred: true), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // חלק ב׳: בדיקות Widget — זרימת חיפוש מלאה
  // ══════════════════════════════════════════════════════════════════════════
  group('CategoryResultsScreen — search flow widget tests', () {

    testWidgets('מציג את כל המומחים בטעינה ראשונית', (tester) async {
      // הגדרת מסך גבוה כדי ש-ListView יבנה את כל הפריטים
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      expect(find.text('משה לוי'),    findsOneWidget);
      expect(find.text('שרה כהן'),    findsOneWidget);
      expect(find.text('דוד ישראלי'), findsOneWidget);
      expect(find.text('רחל מזרחי'), findsOneWidget);
      expect(find.text('יוסי אברהם'), findsOneWidget);
    });

    testWidgets('הקלדה בשורת חיפוש מסננת לפי שם', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'משה');
      await tester.pump();

      expect(find.text('משה לוי'),    findsOneWidget);
      expect(find.text('שרה כהן'),    findsNothing);
      expect(find.text('דוד ישראלי'), findsNothing);
    });

    testWidgets('לחיצה על "עד 100 ₪" מסנן מומחים יקרים', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      await tester.tap(find.text('עד 100 ₪'));
      await tester.pump();

      // מחיר < 100: משה (80), דוד (90), יוסי (50)
      expect(find.text('משה לוי'),    findsOneWidget);
      expect(find.text('דוד ישראלי'), findsOneWidget);
      expect(find.text('יוסי אברהם'), findsOneWidget);

      // מחיר >= 100: שרה (120), רחל (200) — לא אמורים להופיע
      expect(find.text('שרה כהן'),    findsNothing);
      expect(find.text('רחל מזרחי'), findsNothing);
    });

    testWidgets('שילוב חיפוש שם + עד 100 ₪', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      // הפעל פילטר מחיר
      await tester.tap(find.text('עד 100 ₪'));
      await tester.pump();

      // הקלד שם
      await tester.enterText(find.byType(TextField), 'משה');
      await tester.pump();

      expect(find.text('משה לוי'), findsOneWidget);
      // שאר המומחים שנשארו בפילטר מחיר (דוד, יוסי) לא תואמים "משה"
      expect(find.text('דוד ישראלי'), findsNothing);
      expect(find.text('יוסי אברהם'), findsNothing);
    });

    testWidgets('חיפוש שלא מניב תוצאות מציג מסך ריק', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'שם_לא_קיים');
      await tester.pump();

      expect(find.text('לא נמצאו תוצאות'), findsOneWidget);
    });

    testWidgets('ביטול פילטר "עד 100 ₪" מחזיר את כל המומחים', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();

      // הפעל
      await tester.tap(find.text('עד 100 ₪'));
      await tester.pump();
      expect(find.text('שרה כהן'), findsNothing);

      // בטל
      await tester.tap(find.text('עד 100 ₪'));
      await tester.pump();
      expect(find.text('שרה כהן'), findsOneWidget);
    });
  });
}
