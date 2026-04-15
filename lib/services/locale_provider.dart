import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'content_management_service.dart';

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

  // ── CMS overrides stream subscription ──────────────────────────────────────
  StreamSubscription<Map<String, String>>? _overridesSub;

  // ── Supported locales ─────────────────────────────────────────────────────
  static const List<Locale> supported = [
    Locale('he'),
    Locale('en'),
    Locale('es'),
    Locale('ar'),
  ];

  /// Reads the saved locale from SharedPreferences.
  /// Must be awaited before runApp(). CMS override subscription is deferred
  /// to [subscribeOverrides] (called AFTER Firebase.initializeApp) because
  /// [ContentManagementService] uses Firestore which isn't ready at init time.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved  = prefs.getString(_prefKey);
    if (saved != null &&
        LocaleProvider.supported.any((l) => l.languageCode == saved)) {
      instance._locale = Locale(saved);
    }
  }

  /// Subscribes to CMS overrides for the current locale. MUST be called
  /// AFTER Firebase.initializeApp() — uses Firestore internally.
  /// Safe to call multiple times; previous subscription is cancelled.
  static void subscribeOverrides() => instance._subscribeToOverrides();

  /// Subscribes to CMS overrides for the current locale.
  /// Wrapped in try/catch so a transient Firestore issue never breaks init.
  void _subscribeToOverrides() {
    _overridesSub?.cancel();
    try {
      _overridesSub = ContentManagementService.streamOverrides(_locale.languageCode)
          .listen(
            (overrides) {
              // AppLocalizations.overrides = overrides; // setter not available on generated class
              notifyListeners();
            },
            onError: (e) {
              // Don't crash — overrides are a nice-to-have, not load-bearing.
            },
          );
    } catch (_) {
      // Firestore not ready / transient error — CMS overrides stay disabled.
    }
  }

  /// Persists and applies a new locale, rebuilding any ListenableBuilder.
  /// Also resubscribes to CMS overrides for the new locale.
  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, locale.languageCode);
    _subscribeToOverrides();
    notifyListeners();
  }
}
