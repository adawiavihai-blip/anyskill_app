import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Securely stores "Remember Me" credentials using each platform's
/// native encrypted storage:
///   • iOS     → Keychain  (AES-256 encrypted by the OS)
///   • Android → EncryptedSharedPreferences / Keystore
///   • Web     → 🔒 PASSWORD IS NOT STORED — flutter_secure_storage falls
///               back to plain localStorage on web which is accessible to
///               any JS on the page (XSS risk). Only the email is saved.
///
/// Usage:
///   await CredentialsService.save(email: e, password: p);
///   final creds = await CredentialsService.load();
///   if (creds.enabled) { pre-fill fields }
///   await CredentialsService.clear(); // on logout or uncheck
class CredentialsService {
  CredentialsService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kEmail    = 'anyskill_rm_email';
  static const _kPassword = 'anyskill_rm_password';
  static const _kEnabled  = 'anyskill_rm_enabled';

  /// Persists [email] and, on native platforms only, [password] in
  /// encrypted storage. On web only the email is saved to avoid
  /// storing passwords in plain localStorage.
  static Future<void> save({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) {
      // Web: store only the email so the field is pre-filled.
      // Never store the password — localStorage is readable by any JS.
      await Future.wait([
        _storage.write(key: _kEmail,   value: email),
        _storage.write(key: _kEnabled, value: 'true'),
        _storage.delete(key: _kPassword), // ensure no stale value
      ]);
    } else {
      await Future.wait([
        _storage.write(key: _kEmail,    value: email),
        _storage.write(key: _kPassword, value: password),
        _storage.write(key: _kEnabled,  value: 'true'),
      ]);
    }
  }

  /// Wipes all stored credentials. Call on explicit logout or when the
  /// user un-ticks "Remember Me" after a successful login.
  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kEmail),
      _storage.delete(key: _kPassword),
      _storage.delete(key: _kEnabled),
    ]);
  }

  /// Reads stored credentials. [enabled] is false if the user never
  /// ticked "Remember Me" or previously cleared the data.
  /// On web, [password] is always empty.
  static Future<SavedCredentials> load() async {
    final results = await Future.wait([
      _storage.read(key: _kEmail),
      kIsWeb ? Future.value(null) : _storage.read(key: _kPassword),
      _storage.read(key: _kEnabled),
    ]);
    return SavedCredentials(
      email:    results[0] ?? '',
      password: results[1] ?? '',  // empty string on web
      enabled:  results[2] == 'true',
    );
  }
}

class SavedCredentials {
  const SavedCredentials({
    required this.email,
    required this.password,
    required this.enabled,
  });
  final String email;
  final String password;
  final bool   enabled;
}
