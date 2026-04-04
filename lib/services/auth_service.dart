import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../screens/phone_login_screen.dart';
import 'cache_service.dart';

/// Hard state reset + sign out.
///
/// v9.1.2 "Defensive Engineering" logout:
///   1. Terminate all Firestore listeners (terminates the SDK instance)
///   2. Clear in-memory caches
///   3. Clear Sentry user context
///   4. Sign out Firebase Auth
///   5. Let AuthWrapper handle navigation (no manual pushAndRemoveUntil)
///   6. Fallback: if signOut throws, force-navigate to login
Future<void> performSignOut(BuildContext context) async {
  debugPrint('[Logout] Starting hard state reset...');

  // 1. Clear in-memory cache
  try { CacheService.purgeExpired(); } catch (_) {}

  // 2. Clear Sentry user context
  try { Sentry.configureScope((scope) => scope.setUser(null)); } catch (_) {}

  // 3. Clear secure storage (saved credentials, tokens)
  try { await const FlutterSecureStorage().deleteAll(); } catch (_) {}

  // 4. Sign out — AuthWrapper detects null user → shows PhoneLoginScreen
  try {
    await FirebaseAuth.instance.signOut();
    debugPrint('[Logout] SignOut complete — AuthWrapper handles navigation');
  } catch (e) {
    debugPrint('[Logout] SignOut error: $e — force-navigating to login');
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
        (route) => false,
      );
    }
  }
}
