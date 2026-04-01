import 'package:flutter_test/flutter_test.dart';

import 'package:anyskill_app/utils/input_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tests for the ACTUAL InputSanitizer class (not a mirror implementation)
//
// Run:  flutter test test/unit/input_sanitizer_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. sanitizeName
  // ═══════════════════════════════════════════════════════════════════════════

  group('sanitizeName', () {
    test('clean Hebrew name passes', () {
      final r = InputSanitizer.sanitizeName('דנה כהן');
      expect(r.isOk, true);
      expect(r.value, 'דנה כהן');
    });

    test('trims whitespace', () {
      final r = InputSanitizer.sanitizeName('  דנה  ');
      expect(r.value, 'דנה');
    });

    test('rejects HTML tags', () {
      final r = InputSanitizer.sanitizeName('<script>alert("xss")</script>');
      expect(r.isOk, false);
      expect(r.error, contains('תווים אסורים'));
    });

    test('rejects event handlers', () {
      final r = InputSanitizer.sanitizeName('onclick=steal()');
      expect(r.isOk, false);
    });

    test('rejects javascript: scheme', () {
      final r = InputSanitizer.sanitizeName('javascript:void(0)');
      expect(r.isOk, false);
    });

    test('rejects names longer than max', () {
      final r = InputSanitizer.sanitizeName('א' * 51);
      expect(r.isOk, false);
      expect(r.error, contains('ארוך מדי'));
    });

    test('accepts name at exact max length', () {
      final r = InputSanitizer.sanitizeName('א' * 50);
      expect(r.isOk, true);
    });

    test('empty name passes (empty is not forbidden)', () {
      final r = InputSanitizer.sanitizeName('');
      expect(r.isOk, true);
      expect(r.value, '');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. sanitizeAbout
  // ═══════════════════════════════════════════════════════════════════════════

  group('sanitizeAbout', () {
    test('clean bio passes', () {
      final r = InputSanitizer.sanitizeAbout('אני מומחה לניקיון מקצועי עם 10 שנות ניסיון');
      expect(r.isOk, true);
    });

    test('rejects bio with HTML', () {
      final r = InputSanitizer.sanitizeAbout('<img src=x onerror=alert(1)>');
      expect(r.isOk, false);
    });

    test('rejects bio longer than 500 chars', () {
      final r = InputSanitizer.sanitizeAbout('א' * 501);
      expect(r.isOk, false);
      expect(r.error, contains('ארוך מדי'));
    });

    test('accepts bio at exact max', () {
      final r = InputSanitizer.sanitizeAbout('א' * 500);
      expect(r.isOk, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. sanitizeShortText
  // ═══════════════════════════════════════════════════════════════════════════

  group('sanitizeShortText', () {
    test('clean text within limit passes', () {
      final r = InputSanitizer.sanitizeShortText('123456789', 20);
      expect(r.isOk, true);
    });

    test('rejects text over limit', () {
      final r = InputSanitizer.sanitizeShortText('x' * 25, 20);
      expect(r.isOk, false);
    });

    test('rejects data: URI', () {
      final r = InputSanitizer.sanitizeShortText('data:text/html,<h1>x</h1>', 100);
      expect(r.isOk, false);
    });

    test('custom error message used', () {
      final r = InputSanitizer.sanitizeShortText('x' * 25, 20,
          errTooLong: 'custom error');
      expect(r.error, 'custom error');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. sanitizeUrl
  // ═══════════════════════════════════════════════════════════════════════════

  group('sanitizeUrl', () {
    test('valid https URL passes', () {
      final r = InputSanitizer.sanitizeUrl('https://example.com');
      expect(r.isOk, true);
      expect(r.value, 'https://example.com');
    });

    test('rejects http (non-secure)', () {
      final r = InputSanitizer.sanitizeUrl('http://example.com');
      expect(r.isOk, false);
      expect(r.error, contains('https://'));
    });

    test('rejects javascript: scheme', () {
      final r = InputSanitizer.sanitizeUrl('javascript:alert(1)');
      expect(r.isOk, false);
    });

    test('empty URL passes when not required', () {
      final r = InputSanitizer.sanitizeUrl('', required: false);
      expect(r.isOk, true);
      expect(r.value, '');
    });

    test('empty URL fails when required', () {
      final r = InputSanitizer.sanitizeUrl('', required: true);
      expect(r.isOk, false);
      expect(r.error, contains('URL'));
    });

    test('rejects URL longer than max', () {
      final r = InputSanitizer.sanitizeUrl('https://${'x' * 300}');
      expect(r.isOk, false);
      expect(r.error, contains('ארוכה מדי'));
    });

    test('trims whitespace', () {
      final r = InputSanitizer.sanitizeUrl('  https://example.com  ');
      expect(r.value, 'https://example.com');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. SanitizeResult
  // ═══════════════════════════════════════════════════════════════════════════

  group('SanitizeResult', () {
    test('ok result has value and no error', () {
      const r = SanitizeResult.ok('clean');
      expect(r.isOk, true);
      expect(r.value, 'clean');
      expect(r.error, isNull);
    });

    test('err result has error and empty value', () {
      const r = SanitizeResult.err('bad input');
      expect(r.isOk, false);
      expect(r.value, '');
      expect(r.error, 'bad input');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. Constants
  // ═══════════════════════════════════════════════════════════════════════════

  group('Constants', () {
    test('limits are reasonable', () {
      expect(kMaxNameLength, 50);
      expect(kMaxAboutLength, 500);
      expect(kMaxUrlLength, 300);
      expect(kMaxTagLength, 40);
      expect(kMaxTaxIdLength, 20);
    });
  });
}
