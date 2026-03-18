// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: Auth flow validation helpers
//
// Run:  flutter test test/unit/auth_flow_test.dart
//
// Pure Dart — no Firebase, no network.
// Tests the validation logic used by LoginScreen / SignupScreen.
// Real Firebase calls are integration-tested via emulator (out of scope here).
// ─────────────────────────────────────────────────────────────────────────────

// ── Replicated validation logic (mirrors LoginScreen / SignupScreen) ──────────
// These validators are pure functions — extracted here for testability.

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'נא להזין כתובת אימייל';
  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailRegex.hasMatch(value.trim())) return 'כתובת אימייל לא תקינה';
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'נא להזין סיסמה';
  if (value.length < 6) return 'הסיסמה חייבת להכיל לפחות 6 תווים';
  return null;
}

String? validateDisplayName(String? value) {
  if (value == null || value.trim().isEmpty) return 'נא להזין שם';
  if (value.trim().length < 2) return 'השם חייב להכיל לפחות 2 תווים';
  return null;
}

String? validatePhone(String? value) {
  if (value == null || value.trim().isEmpty) return null; // optional field
  final phoneRegex = RegExp(r'^0[0-9]{9}$'); // Israeli mobile: 0XX-XXXXXXX (10 digits)
  if (!phoneRegex.hasMatch(value.replaceAll(RegExp(r'[\s\-]'), ''))) {
    return 'מספר טלפון לא תקין';
  }
  return null;
}

/// Returns true when the user may proceed past the ToS gate.
bool tosGatePass({required bool agreed}) => agreed;

/// Computes initial balance for a new user (always 0).
double initialBalance() => 0.0;

/// Determines whether a newly created user document is a provider.
bool isProviderFromRole(String role) => role == 'provider';

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('Email validation', () {
    test('empty string is invalid', () {
      expect(validateEmail(''), isNotNull);
    });

    test('null is invalid', () {
      expect(validateEmail(null), isNotNull);
    });

    test('missing @ is invalid', () {
      expect(validateEmail('userexample.com'), isNotNull);
    });

    test('missing domain is invalid', () {
      expect(validateEmail('user@'), isNotNull);
    });

    test('valid email passes', () {
      expect(validateEmail('user@example.com'), isNull);
    });

    test('valid email with subdomain passes', () {
      expect(validateEmail('user@mail.example.co.il'), isNull);
    });

    test('email with leading/trailing spaces passes (trimmed)', () {
      expect(validateEmail('  user@example.com  '), isNull);
    });
  });

  group('Password validation', () {
    test('empty password is invalid', () {
      expect(validatePassword(''), isNotNull);
    });

    test('null password is invalid', () {
      expect(validatePassword(null), isNotNull);
    });

    test('5-char password is too short', () {
      expect(validatePassword('abc12'), isNotNull);
    });

    test('6-char password is valid', () {
      expect(validatePassword('abc123'), isNull);
    });

    test('long password is valid', () {
      expect(validatePassword('MyStr0ngP@ssword!'), isNull);
    });
  });

  group('Display name validation', () {
    test('empty name is invalid', () {
      expect(validateDisplayName(''), isNotNull);
    });

    test('single character is invalid', () {
      expect(validateDisplayName('א'), isNotNull);
    });

    test('two characters is valid', () {
      expect(validateDisplayName('יו'), isNull);
    });

    test('whitespace-only is invalid', () {
      expect(validateDisplayName('   '), isNotNull);
    });

    test('normal Hebrew name is valid', () {
      expect(validateDisplayName('אבי כהן'), isNull);
    });

    test('normal English name is valid', () {
      expect(validateDisplayName('John Doe'), isNull);
    });
  });

  group('Phone validation (optional field)', () {
    test('empty phone is valid (field is optional)', () {
      expect(validatePhone(''), isNull);
    });

    test('null phone is valid (field is optional)', () {
      expect(validatePhone(null), isNull);
    });

    test('valid Israeli mobile number passes', () {
      expect(validatePhone('0501234567'), isNull);
    });

    test('number with hyphens passes (stripped before check)', () {
      expect(validatePhone('050-123-4567'), isNull);
    });

    test('number with spaces passes (stripped before check)', () {
      expect(validatePhone('050 123 4567'), isNull);
    });

    test('9-digit number is invalid (too short)', () {
      expect(validatePhone('050123456'), isNotNull);
    });

    test('number not starting with 0 is invalid', () {
      expect(validatePhone('5501234567'), isNotNull);
    });
  });

  group('ToS gate', () {
    test('agreed=true passes the gate', () {
      expect(tosGatePass(agreed: true), isTrue);
    });

    test('agreed=false blocks the gate', () {
      expect(tosGatePass(agreed: false), isFalse);
    });
  });

  group('New user document defaults', () {
    test('initial balance is zero', () {
      expect(initialBalance(), 0.0);
    });

    test('role=provider → isProvider=true', () {
      expect(isProviderFromRole('provider'), isTrue);
    });

    test('role=customer → isProvider=false', () {
      expect(isProviderFromRole('customer'), isFalse);
    });

    test('unknown role → isProvider=false', () {
      expect(isProviderFromRole(''), isFalse);
    });
  });

  group('Full sign-up form validation (combined)', () {
    Map<String, String?> validateSignupForm({
      required String email,
      required String password,
      required String name,
      required String phone,
      required bool tosAgreed,
    }) {
      return {
        'email':    validateEmail(email),
        'password': validatePassword(password),
        'name':     validateDisplayName(name),
        'phone':    validatePhone(phone),
        'tos':      tosAgreed ? null : 'יש לאשר תנאי שימוש',
      };
    }

    test('valid form has no errors', () {
      final errors = validateSignupForm(
        email:     'test@example.com',
        password:  'secret123',
        name:      'משה כהן',
        phone:     '0521234567',
        tosAgreed: true,
      );
      expect(errors.values.every((e) => e == null), isTrue);
    });

    test('form with bad email has exactly one error', () {
      final errors = validateSignupForm(
        email:     'not-an-email',
        password:  'secret123',
        name:      'משה כהן',
        phone:     '0521234567',
        tosAgreed: true,
      );
      final errorCount = errors.values.where((e) => e != null).length;
      expect(errorCount, 1);
      expect(errors['email'], isNotNull);
    });

    test('unsigned ToS blocks submission', () {
      final errors = validateSignupForm(
        email:     'test@example.com',
        password:  'secret123',
        name:      'משה כהן',
        phone:     '0521234567',
        tosAgreed: false,
      );
      expect(errors['tos'], isNotNull);
    });

    test('multiple invalid fields returns multiple errors', () {
      final errors = validateSignupForm(
        email:     '',
        password:  '123',
        name:      '',
        phone:     '12345',
        tosAgreed: false,
      );
      final errorCount = errors.values.where((e) => e != null).length;
      expect(errorCount, greaterThanOrEqualTo(4));
    });
  });
}
