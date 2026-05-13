import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Anti-Duplicate Guard for social sign-in.
///
/// Belt-and-suspenders complement to the Firebase Console flag
/// "One account per email" — catches edge cases where a NEW Firebase Auth
/// uid is created for an email that already owns a `users/{otherUid}` doc
/// (legacy email/password user, Console misconfigured, OAuth race, etc.).
///
/// Behavior (v15.x, post-Sigalit fix): when a duplicate is detected, the
/// CF `selfHealAccountByEmail` automatically deletes the caller's new Auth
/// account and returns a custom token for the legacy uid. The client then
/// signs in seamlessly as the legacy user — preserving role, history, and
/// verifications. The user sees a "Welcome back!" toast.
///
/// Falls back to the v12.4 "use original method" dialog if the heal fails
/// (e.g. Cloud Functions unreachable, email_verified missing).
class AuthDuplicateGuard {
  /// Returns the conflicting uid if [email] is already used by a doc with a
  /// DIFFERENT uid than [currentUid]. Returns null if no conflict, empty
  /// email, or the only match IS [currentUid].
  static Future<String?> findConflict({
    required String currentUid,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    // 4s cap — must NEVER hang the sign-in flow. If the query stalls
    // (network, missing index, Firestore slow), fail-open: allow the
    // signup to proceed. Worst case is a rare duplicate doc that the
    // server-side Auth "one account per email" flag + manual admin
    // review will catch. Hanging the Google sign-in is much worse UX.
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: normalized)
          .limit(2)
          .get()
          .timeout(const Duration(seconds: 4));

      for (final doc in snap.docs) {
        if (doc.id != currentUid) return doc.id;
      }
    } catch (e) {
      debugPrint('[AuthDuplicateGuard] findConflict failed/timed out: $e');
    }
    return null;
  }

  /// Checks for an email conflict, then attempts auto-heal via the
  /// `selfHealAccountByEmail` CF. If the heal succeeds, the caller is
  /// already signed in seamlessly as the legacy user (custom token) and
  /// sees a Hebrew "Welcome back!" toast. If the heal fails, falls back
  /// to the original sign-out + "use original method" dialog.
  ///
  /// Returns `true` if it is safe to proceed creating/updating the profile.
  /// Returns `false` if a conflict was found and handled (caller MUST stop).
  static Future<bool> enforceOrSignOut({
    required BuildContext context,
    required UserCredential cred,
  }) async {
    final user = cred.user;
    if (user == null) return true;

    final conflictUid = await findConflict(
      currentUid: user.uid,
      email: user.email ?? '',
    );
    if (conflictUid == null) return true;

    // ── Self-heal path ──
    // CF deletes the caller's brand-new Auth account, returns a custom
    // token for the legacy uid. We sign out + signInWithCustomToken so
    // the user lands directly in their existing account.
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('selfHealAccountByEmail')
          .call({})
          .timeout(const Duration(seconds: 30));
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['healed'] == true && data['customToken'] is String) {
        final token = data['customToken'] as String;
        try { await FirebaseAuth.instance.signOut(); } catch (_) {}
        try {
          await FirebaseAuth.instance.signInWithCustomToken(token);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('ברוכים השבים! 👋 זיהינו את החשבון שלך'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ));
          }
          return false; // caller stops; AuthWrapper will route via legacy uid
        } catch (signInErr) {
          debugPrint('[AuthDuplicateGuard] custom-token signin failed: $signInErr');
          // Fall through to dialog fallback below.
        }
      }
    } catch (e) {
      debugPrint('[AuthDuplicateGuard] self-heal CF failed: $e');
    }

    // ── Fallback ──
    // Sign back out so we don't leave a half-created session, then show
    // the legacy "use original method" dialog.
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}

    if (context.mounted) {
      await showConflictDialog(context, email: user.email ?? '');
    }
    return false;
  }

  static Future<void> showConflictDialog(
    BuildContext context, {
    required String email,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('כבר יש חשבון עם המייל הזה'),
        content: Text(
          'מצאנו חשבון קיים במערכת עם המייל $email.\n\n'
          'כדי לא ליצור חשבון כפול, אנא התחבר/י דרך השיטה שבה נרשמת '
          'במקור (טלפון או שיטת הרשמה אחרת). אם איבדת גישה — פנה/י '
          'לתמיכה ונחבר את החשבונות ידנית.',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }
}
