import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyskill_app/utils/price_formatter.dart';
import 'package:anyskill_app/screens/search_screen/widgets/expert_card.dart';

void main() {
  // ─── בדיקות יחידה לפונקציה הטהורה ──────────────────────────────────────────
  group('formatPriceDisplay — unit tests', () {
    test('int רגיל', () {
      expect(formatPriceDisplay(100), 'החל מ־100 ₪');
    });

    test('double שלם (100.0) — ללא .0 מיותר', () {
      expect(formatPriceDisplay(100.0), 'החל מ־100 ₪');
    });

    test('double עשרוני (99.5)', () {
      expect(formatPriceDisplay(99.5), 'החל מ־99.5 ₪');
    });

    test('String מחיר', () {
      expect(formatPriceDisplay('150'), 'החל מ־150 ₪');
    });

    test('null — חזרה ל-0', () {
      expect(formatPriceDisplay(null), 'החל מ־0 ₪');
    });

    test('int אפס', () {
      expect(formatPriceDisplay(0), 'החל מ־0 ₪');
    });

    test('double אפס (0.0)', () {
      expect(formatPriceDisplay(0.0), 'החל מ־0 ₪');
    });

    test('String ריק — חזרה ל-0', () {
      expect(formatPriceDisplay(''), 'החל מ־0 ₪');
    });

    test('מחיר גדול (1500)', () {
      expect(formatPriceDisplay(1500), 'החל מ־1500 ₪');
    });

    test('תמיד מכיל את הקידומת העברית', () {
      expect(formatPriceDisplay(200), startsWith('החל מ־'));
    });

    test('תמיד מכיל סמל שקל', () {
      expect(formatPriceDisplay(200), endsWith('₪'));
    });

    test('מחיר עם ספרה אחת', () {
      expect(formatPriceDisplay(5), 'החל מ־5 ₪');
    });

    test('double עשרוני עם שתי ספרות (49.99)', () {
      expect(formatPriceDisplay(49.99), 'החל מ־49.99 ₪');
    });
  });

  // ─── בדיקות Widget ל-ExpertCard ─────────────────────────────────────────────
  group('ExpertCard — price display widget tests', () {
    Widget buildCard({required dynamic price}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ExpertCard(
              name: 'מבחן מומחה',
              bio: 'תיאור לצורך בדיקה',
              rating: 4.5,
              price: price,
              imageUrl: '', // ריק — יפעיל errorBuilder (אין רשת בבדיקות)
            ),
          ),
        ),
      );
    }

    // עוזר: מוצא Text שמכיל את הטקסט הנדרש
    Finder findTextContaining(String s) => find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains(s),
        );

    testWidgets('מציג "החל מ־" בתצוגה', (tester) async {
      await tester.pumpWidget(buildCard(price: 200));
      expect(findTextContaining('החל מ־'), findsOneWidget);
    });

    testWidgets('מציג את הסכום הנכון — int', (tester) async {
      await tester.pumpWidget(buildCard(price: 200));
      expect(findTextContaining('200'), findsAtLeastNWidgets(1));
    });

    testWidgets('מציג סמל שקל ₪', (tester) async {
      await tester.pumpWidget(buildCard(price: 200));
      expect(findTextContaining('₪'), findsOneWidget);
    });

    testWidgets('מציג מחיר double שלם ללא .0', (tester) async {
      await tester.pumpWidget(buildCard(price: 150.0));
      expect(findTextContaining('150'), findsAtLeastNWidgets(1));
      expect(findTextContaining('150.0'), findsNothing);
    });

    testWidgets('מציג מחיר עשרוני', (tester) async {
      await tester.pumpWidget(buildCard(price: 79.9));
      expect(findTextContaining('79.9'), findsAtLeastNWidgets(1));
    });

    testWidgets('null מציג "החל מ־0 ₪"', (tester) async {
      await tester.pumpWidget(buildCard(price: null));
      expect(findTextContaining('החל מ־0 ₪'), findsOneWidget);
    });

    testWidgets('מחיר String מוצג נכון', (tester) async {
      await tester.pumpWidget(buildCard(price: '300'));
      expect(findTextContaining('300'), findsAtLeastNWidgets(1));
    });
  });
}
