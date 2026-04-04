import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/phone_login_screen.dart';

/// Safe sign-out that avoids the Firestore INTERNAL_ASSERTION_FAILED crash.
///
/// Root cause: calling [FirebaseAuth.signOut] while Firestore StreamBuilders
/// are still active causes the Firestore SDK to fire snapshot events against
/// revoked credentials, triggering an internal assertion.
///
/// Fix: navigate away first — this disposes all StreamBuilder widgets and
/// cancels their Firestore subscriptions — THEN call signOut with no live
/// listeners remaining.
Future<void> performSignOut(BuildContext context) async {
  try {
    // Sign out ONLY — do NOT navigate manually.
    // AuthWrapper's StreamBuilder on authStateChanges() will detect the
    // null user and automatically rebuild to PhoneLoginScreen.
    // Manual pushAndRemoveUntil caused a double-navigation race that
    // crashed with a blank "death screen" (v9.1.0 bug).
    await FirebaseAuth.instance.signOut();
    debugPrint('SignOut: completed — AuthWrapper will handle navigation');
  } catch (e) {
    debugPrint('SignOut error (non-fatal): $e');
    // Even if signOut throws, force-navigate to prevent the user from
    // being stuck on a broken screen.
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
        (route) => false,
      );
    }
  }
}
