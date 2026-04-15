import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../screens/phone_login_screen.dart';
import 'cache_service.dart';

/// Hard state reset + sign out.
///
/// v9.4.7 — LOCAL-FIRST logout: clears all local state synchronously BEFORE
/// touching the network. If the server is down (500), the user still gets to
/// the login screen instead of a white screen.
///
/// Order:
///   1. Clear in-memory caches (sync)
///   2. Clear Sentry user context (sync)
///   3. Clear SharedPreferences (local, fast)
///   4. Clear FlutterSecureStorage (local, fast)
///   5. Sign out Firebase Auth (may hit network)
///   6. Fallback: if signOut throws, force-navigate to login
Future<void> performSignOut(BuildContext context) async {
  debugPrint('[Logout] Starting hard state reset...');

  // 1. Clear in-memory cache (sync — no network)
  try { CacheService.purgeExpired(); } catch (_) {}

  // 2. Clear Sentry user context (sync)
  try { Sentry.configureScope((scope) => scope.setUser(null)); } catch (_) {}

  // 3. Clear SharedPreferences (local storage — no network)
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    debugPrint('[Logout] SharedPreferences cleared');
  } catch (_) {}

  // 4. Clear secure storage (local — no network)
  try { await const FlutterSecureStorage().deleteAll(); } catch (_) {}

  // 5. Sign out — with 5s timeout so a 500/network error can't hang forever
  try {
    await FirebaseAuth.instance.signOut().timeout(
      const Duration(seconds: 5),
      onTimeout: () => debugPrint('[Logout] signOut timed out — forcing nav'),
    );
    debugPrint('[Logout] SignOut complete — AuthWrapper handles navigation');
  } catch (e) {
    debugPrint('[Logout] SignOut error: $e — force-navigating to login');
  }

  // 6. ALWAYS force-navigate to login as a safety net.
  // AuthWrapper should handle it via stream, but if the stream is stuck
  // (500 errors, broken state), this ensures the user never sees a white screen.
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
      (route) => false,
    );
  }
}
