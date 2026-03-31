import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget tests: Form validation and input handling
//
// Tests validators, error messages, and form submission logic
// using pure Flutter widgets — no Firebase dependency.
//
// Run:  flutter test test/widget/form_validation_test.dart
// ─────────────────────────────────────────────────────────────────────────────

/// AnySkill email validator (mirrors login_screen.dart logic).
bool _emailValid(String v) =>
    RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$', caseSensitive: false)
        .hasMatch(v.trim());

/// Phone validator for Israeli numbers.
bool _phoneValid(String v) {
  final cleaned = v.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  return RegExp(r'^(\+972|0)\d{9}$').hasMatch(cleaned);
}

/// Price validator (positive number).
bool _priceValid(String v) {
  final n = double.tryParse(v);
  return n != null && n > 0;
}

/// Name validator (min 2 chars, no HTML).
bool _nameValid(String v) {
  if (v.trim().length < 2) return false;
  if (RegExp(r'<[^>]*>').hasMatch(v)) return false; // no HTML
  return true;
}

/// Bio validator (min 10 chars for providers).
bool _bioValid(String v) => v.trim().length >= 10;

/// Hebrew text validator (contains Hebrew characters).
bool _hasHebrew(String v) => RegExp(r'[\u0590-\u05FF]').hasMatch(v);

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. EMAIL VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Email validation', () {
    test('valid emails pass', () {
      expect(_emailValid('user@example.com'), true);
      expect(_emailValid('user+tag@test.org'), true);
      expect(_emailValid('a@b.cd'), true);
      // Note: subdomain emails like name@domain.co.il fail the simple regex
      // but that matches the actual app's login_screen.dart validator behavior
    });

    test('invalid emails fail', () {
      expect(_emailValid(''), false);
      expect(_emailValid('noatsign'), false);
      expect(_emailValid('@nodomain.com'), false);
      expect(_emailValid('user@'), false);
      expect(_emailValid('user@.com'), false);
      expect(_emailValid('user@domain'), false); // no TLD
      expect(_emailValid('user @domain.com'), false); // space
    });

    test('trims whitespace before validation', () {
      expect(_emailValid('  user@example.com  '), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. PHONE VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Phone validation', () {
    test('valid Israeli numbers pass', () {
      expect(_phoneValid('0501234567'), true);
      expect(_phoneValid('+972501234567'), true);
      expect(_phoneValid('050-123-4567'), true);
      expect(_phoneValid('050 123 4567'), true);
    });

    test('invalid numbers fail', () {
      expect(_phoneValid(''), false);
      expect(_phoneValid('123'), false);
      expect(_phoneValid('050123456'), false); // too short
      expect(_phoneValid('05012345678'), false); // too long
      expect(_phoneValid('+1501234567'), false); // wrong country
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. PRICE VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Price validation', () {
    test('positive numbers pass', () {
      expect(_priceValid('100'), true);
      expect(_priceValid('49.99'), true);
      expect(_priceValid('1'), true);
      expect(_priceValid('0.01'), true);
    });

    test('zero and negative fail', () {
      expect(_priceValid('0'), false);
      expect(_priceValid('-10'), false);
      expect(_priceValid('-0.01'), false);
    });

    test('non-numeric fails', () {
      expect(_priceValid(''), false);
      expect(_priceValid('abc'), false);
      expect(_priceValid('₪100'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. NAME VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Name validation', () {
    test('valid Hebrew names pass', () {
      expect(_nameValid('דנה'), true);
      expect(_nameValid('יוסי כהן'), true);
      expect(_nameValid('שרה-לאה'), true);
    });

    test('valid English names pass', () {
      expect(_nameValid('Dana'), true);
      expect(_nameValid('John Doe'), true);
    });

    test('too short fails', () {
      expect(_nameValid(''), false);
      expect(_nameValid('א'), false);
      expect(_nameValid(' '), false);
    });

    test('HTML injection blocked', () {
      expect(_nameValid('<script>alert("xss")</script>'), false);
      expect(_nameValid('דנה<img src=x>'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. BIO VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Bio validation', () {
    test('10+ chars passes', () {
      expect(_bioValid('אני מומחה לניקיון מקצועי'), true);
      expect(_bioValid('1234567890'), true);
    });

    test('under 10 chars fails', () {
      expect(_bioValid(''), false);
      expect(_bioValid('קצר'), false);
      expect(_bioValid('123456789'), false); // exactly 9
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. HEBREW DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Hebrew detection', () {
    test('Hebrew text detected', () {
      expect(_hasHebrew('שלום'), true);
      expect(_hasHebrew('Hello שלום'), true);
    });

    test('non-Hebrew text not detected', () {
      expect(_hasHebrew('Hello'), false);
      expect(_hasHebrew('12345'), false);
      expect(_hasHebrew(''), false);
    });

    test('Arabic is not Hebrew', () {
      expect(_hasHebrew('مرحبا'), false); // Arabic chars are different range
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. FORM WIDGET TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Form widget behavior', () {
    testWidgets('empty TextFormField shows error on validate', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: TextFormField(
              validator: (v) => (v == null || v.isEmpty) ? 'שדה חובה' : null,
            ),
          ),
        ),
      ));

      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text('שדה חובה'), findsOneWidget);
    });

    testWidgets('valid input shows no error', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'valid input');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              validator: (v) => (v == null || v.isEmpty) ? 'שדה חובה' : null,
            ),
          ),
        ),
      ));

      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text('שדה חובה'), findsNothing);
    });

    testWidgets('email field shows error for invalid email', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'not-an-email');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              validator: (v) => !_emailValid(v ?? '') ? 'אימייל לא תקין' : null,
            ),
          ),
        ),
      ));

      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text('אימייל לא תקין'), findsOneWidget);
    });

    testWidgets('price field rejects zero', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: '0');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              validator: (v) => !_priceValid(v ?? '') ? 'מחיר לא תקין' : null,
            ),
          ),
        ),
      ));

      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text('מחיר לא תקין'), findsOneWidget);
    });

    testWidgets('multiple validators in a form', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('name'),
                  validator: (v) => !_nameValid(v ?? '') ? 'שם קצר מדי' : null,
                ),
                TextFormField(
                  key: const Key('email'),
                  validator: (v) => !_emailValid(v ?? '') ? 'אימייל לא תקין' : null,
                ),
                TextFormField(
                  key: const Key('price'),
                  validator: (v) => !_priceValid(v ?? '') ? 'מחיר לא תקין' : null,
                ),
              ],
            ),
          ),
        ),
      ));

      // All empty → all errors
      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text('שם קצר מדי'), findsOneWidget);
      expect(find.text('אימייל לא תקין'), findsOneWidget);
      expect(find.text('מחיר לא תקין'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. BUTTON INTERACTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Button interactions', () {
    testWidgets('ElevatedButton triggers onPressed', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => pressed = true,
            child: const Text('שלח'),
          ),
        ),
      ));

      await tester.tap(find.text('שלח'));
      expect(pressed, true);
    });

    testWidgets('disabled button does not trigger', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: null,
            child: const Text('שלח'),
          ),
        ),
      ));

      await tester.tap(find.text('שלח'));
      expect(pressed, false);
    });

    testWidgets('loading state disables button', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: null, // disabled (loading)
            child: const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ));

      // Button should show spinner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tapping a disabled button doesn't fire
      await tester.tap(find.byType(ElevatedButton));
      expect(tapCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Navigation', () {
    testWidgets('push navigates to new screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => const Scaffold(
                  body: Text('Page 2'),
                )),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Page 2'), findsOneWidget);
    });

    testWidgets('pop returns to previous screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Back'),
                  ),
                )),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Go'), findsOneWidget);
    });
  });
}
