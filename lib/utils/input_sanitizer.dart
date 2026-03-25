/// Input sanitization and validation utilities for user-facing text fields.
///
/// Why this exists:
///   Firestore is not a SQL database, so SQL injection is not a risk.
///   However, user-supplied strings are displayed in the UI and potentially
///   rendered in web contexts, making XSS injection (via HTML/script tags)
///   and storage-bloat attacks (very long strings) the primary concerns.
///
/// Usage:
///   final result = InputSanitizer.sanitizeName(rawValue);
///   if (result.error != null) { showSnackBar(result.error!); return; }
///   final safe = result.value;   // clean, trimmed, ready for Firestore
library;

// ── Limits ───────────────────────────────────────────────────────────────────
const kMaxNameLength        = 50;
const kMaxAboutLength       = 500;
const kMaxTagLength         = 40;
const kMaxUrlLength         = 300;
const kMaxBankFieldLength   = 100;
const kMaxTaxIdLength       = 20;
const kMaxBranchLength      = 10;

// ── Result type ──────────────────────────────────────────────────────────────
class SanitizeResult {
  const SanitizeResult.ok(this.value) : error = null;
  const SanitizeResult.err(this.error) : value = '';

  /// The cleaned value; empty string when [error] is non-null.
  final String value;

  /// Non-null means validation failed; show this message to the user.
  final String? error;

  bool get isOk => error == null;
}

// ── Core sanitizer ───────────────────────────────────────────────────────────
class InputSanitizer {
  InputSanitizer._();

  // Matches any HTML/XML tag: <script>, </div>, <img src=...>, etc.
  static final _htmlTagRe = RegExp(r'<[^>]*>', multiLine: true);

  // Matches dangerous JS event handlers injected as plain text: onclick=, onload=
  static final _eventHandlerRe =
      RegExp(r'on\w+\s*=', caseSensitive: false);

  // Matches javascript: URI scheme used in href/src injection
  static final _jsSchemeRe =
      RegExp(r'javascript\s*:', caseSensitive: false);

  // Matches data: URI scheme (can embed scripts in some browsers)
  static final _dataUriRe =
      RegExp(r'data\s*:', caseSensitive: false);

  // Collapses multiple whitespace/newline runs into a single space
  static final _multiSpaceRe = RegExp(r'\s{2,}');

  /// Strips HTML tags and known injection patterns, then trims whitespace.
  /// Returns the cleaned string. Never throws.
  static String _strip(String raw) {
    var s = raw
        .replaceAll(_htmlTagRe, '')
        .replaceAll(_eventHandlerRe, '')
        .replaceAll(_jsSchemeRe, '')
        .replaceAll(_dataUriRe, '')
        .replaceAll(_multiSpaceRe, ' ')
        .trim();
    return s;
  }

  /// Returns true if [raw] contained HTML/script injection before stripping.
  static bool _hadInjection(String raw) =>
      _htmlTagRe.hasMatch(raw) ||
      _eventHandlerRe.hasMatch(raw) ||
      _jsSchemeRe.hasMatch(raw) ||
      _dataUriRe.hasMatch(raw);

  // ── Public validators ────────────────────────────────────────────────────

  /// Display name: max [kMaxNameLength] chars, no HTML.
  static SanitizeResult sanitizeName(String raw, {
    String errForbidden = 'השם מכיל תווים אסורים (HTML/סקריפט)',
    String errTooLong   = 'השם ארוך מדי (מקסימום $kMaxNameLength תווים)',
  }) {
    if (_hadInjection(raw)) return SanitizeResult.err(errForbidden);
    final v = _strip(raw);
    if (v.length > kMaxNameLength) return SanitizeResult.err(errTooLong);
    return SanitizeResult.ok(v);
  }

  /// About / bio description: max [kMaxAboutLength] chars, no HTML.
  static SanitizeResult sanitizeAbout(String raw, {
    String errForbidden = 'התיאור מכיל תווים אסורים (HTML/סקריפט)',
    String errTooLong   = 'התיאור ארוך מדי (מקסימום $kMaxAboutLength תווים)',
  }) {
    if (_hadInjection(raw)) return SanitizeResult.err(errForbidden);
    final v = _strip(raw);
    if (v.length > kMaxAboutLength) return SanitizeResult.err(errTooLong);
    return SanitizeResult.ok(v);
  }

  /// Generic short text (bank fields, tax ID, etc.).
  static SanitizeResult sanitizeShortText(String raw, int maxLen, {
    String errForbidden = 'השדה מכיל תווים אסורים',
    String? errTooLong,
  }) {
    if (_hadInjection(raw)) return SanitizeResult.err(errForbidden);
    final v = _strip(raw);
    if (v.length > maxLen) {
      return SanitizeResult.err(errTooLong ?? 'השדה ארוך מדי (מקסימום $maxLen תווים)');
    }
    return SanitizeResult.ok(v);
  }

  /// URL: must be empty or start with https://, max [kMaxUrlLength] chars.
  static SanitizeResult sanitizeUrl(String raw, {
    String errScheme  = 'הכתובת חייבת להתחיל ב-https://',
    String errTooLong = 'הכתובת ארוכה מדי (מקסימום $kMaxUrlLength תווים)',
    bool   required   = false,
  }) {
    final v = raw.trim();
    if (v.isEmpty) {
      return required
          ? SanitizeResult.err('נא להזין כתובת URL')
          : const SanitizeResult.ok('');
    }
    if (!v.startsWith('https://')) return SanitizeResult.err(errScheme);
    if (v.length > kMaxUrlLength)  return SanitizeResult.err(errTooLong);
    return SanitizeResult.ok(v);
  }
}
