import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Securely stores "Remember Me" credentials using each platform's
/// native encrypted storage:
///   • iOS     → Keychain  (AES-256 encrypted by the OS)
///   • Android → EncryptedSharedPreferences / Keystore
///   • Web     → localStorage (best-effort; no OS keychain on browsers)
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

  /// Persists [email] and [password] in encrypted storage.
  static Future<void> save({
    required String email,
    required String password,
  }) async {
    await Future.wait([
      _storage.write(key: _kEmail,    value: email),
      _storage.write(key: _kPassword, value: password),
      _storage.write(key: _kEnabled,  value: 'true'),
    ]);
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
  static Future<SavedCredentials> load() async {
    final results = await Future.wait([
      _storage.read(key: _kEmail),
      _storage.read(key: _kPassword),
      _storage.read(key: _kEnabled),
    ]);
    return SavedCredentials(
      email:    results[0] ?? '',
      password: results[1] ?? '',
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
