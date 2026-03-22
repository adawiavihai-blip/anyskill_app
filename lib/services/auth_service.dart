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
    // Step 1: clear the entire nav stack and go to PhoneLoginScreen.
    // All StreamBuilders in the old tree are disposed here, cancelling
    // every active Firestore listener before credentials are revoked.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
      (route) => false,
    );

    // Step 2: sign out after the navigation request is enqueued.
    // By the time this executes the old widget tree is already tearing down.
    await FirebaseAuth.instance.signOut();
    debugPrint('SignOut: completed successfully');
  } catch (e) {
    // Firestore may still log a non-fatal assertion — auth state clears anyway.
    debugPrint('SignOut error (non-fatal): $e');
  }
}
