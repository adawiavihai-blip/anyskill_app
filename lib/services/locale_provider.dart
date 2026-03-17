import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton ChangeNotifier that owns the active locale and persists
/// the user's choice to SharedPreferences.
///
/// Usage:
///   await LocaleProvider.init();   // call once in main()
///   LocaleProvider.instance.locale // read anywhere
///   LocaleProvider.instance.setLocale(const Locale('en')) // change
///
/// MaterialApp wires it via:
///   ListenableBuilder(listenable: LocaleProvider.instance, builder: ...)
class LocaleProvider extends ChangeNotifier {
  static const _prefKey = 'app_locale';

  // ── Singleton ─────────────────────────────────────────────────────────────
  static LocaleProvider? _instance;
  static LocaleProvider get instance {
    _instance ??= LocaleProvider._();
    return _instance!;
  }
  LocaleProvider._();

  Locale _locale = const Locale('he');
  Locale get locale => _locale;

  // ── Supported locales ─────────────────────────────────────────────────────
  static const List<Locale> supported = [
    Locale('he'),
    Locale('en'),
    Locale('es'),
  ];

  /// Reads the saved locale from SharedPreferences.
  /// Must be awaited before runApp().
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved  = prefs.getString(_prefKey);
    if (saved != null &&
        LocaleProvider.supported.any((l) => l.languageCode == saved)) {
      instance._locale = Locale(saved);
    }
  }

  /// Persists and applies a new locale, rebuilding any ListenableBuilder.
  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, locale.languageCode);
    notifyListeners();
  }
}
