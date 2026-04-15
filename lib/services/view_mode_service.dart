import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v12.7.0: tri-state view-mode toggle.
///
/// - `normal`      — default. User sees everything they're entitled to
///                   (admin + provider + customer).
/// - `customer`    — force customer UI. Admin tabs AND provider tabs hidden.
/// - `providerOnly`— admin-only. Hides admin tabs but keeps provider tabs,
///                   so an admin-provider can experience the provider UX.
///
/// Persisted per-uid to SharedPreferences (`view_mode.mode.{uid}`).
enum ViewMode {
  normal,
  customer,
  providerOnly,
}

class ViewModeService extends ChangeNotifier {
  static const _prefKeyPrefix = 'view_mode.mode.';
  // Legacy v12.6 key — still read on init for smooth upgrade.
  static const _legacyBoolKey = 'view_mode.customer.';

  ViewModeService._();
  static ViewModeService? _instance;
  static ViewModeService get instance {
    _instance ??= ViewModeService._();
    return _instance!;
  }

  ViewMode _mode = ViewMode.normal;
  String _loadedForUid = '';

  ViewMode get mode => _mode;

  /// Back-compat shim for v12.6 callers that still read `customerMode` as a bool.
  bool get customerMode => _mode == ViewMode.customer;

  /// Called once per uid on auth login.
  static Future<void> initForUid(String uid) async {
    if (instance._loadedForUid == uid) return;
    instance._loadedForUid = uid;
    if (uid.isEmpty) {
      instance._mode = ViewMode.normal;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // New enum key first.
      final raw = prefs.getString('$_prefKeyPrefix$uid');
      if (raw != null) {
        instance._mode = ViewMode.values.firstWhere(
          (m) => m.name == raw,
          orElse: () => ViewMode.normal,
        );
      } else {
        // Fall back to v12.6 bool key so returning users' state persists.
        final legacy = prefs.getBool('$_legacyBoolKey$uid') ?? false;
        instance._mode = legacy ? ViewMode.customer : ViewMode.normal;
      }
      instance.notifyListeners();
    } catch (_) {
      instance._mode = ViewMode.normal;
    }
  }

  Future<void> setMode({required String uid, required ViewMode mode}) async {
    _mode = mode;
    notifyListeners();
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefKeyPrefix$uid', mode.name);
      // Keep the legacy bool key in sync so any stragglers see the right value.
      await prefs.setBool(
          '$_legacyBoolKey$uid', mode == ViewMode.customer);
    } catch (_) {
      // best-effort
    }
  }

  /// Back-compat shim for v12.6 callers.
  Future<void> setCustomerMode({required String uid, required bool enabled}) {
    return setMode(
      uid: uid,
      mode: enabled ? ViewMode.customer : ViewMode.normal,
    );
  }

  Future<void> reset() async {
    _mode = ViewMode.normal;
    _loadedForUid = '';
    notifyListeners();
  }
}
