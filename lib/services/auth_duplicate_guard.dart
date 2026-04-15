import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// PR-A: Anti-Duplicate Guard for social sign-in (v12.4.0).
///
/// Belt-and-suspenders complement to the Firebase Console flag
/// "One account per email" — catches edge cases where a NEW Firebase Auth
/// uid is created for an email that already owns a `users/{otherUid}` doc
/// (legacy email/password user, Console misconfigured, OAuth race, etc.).
///
/// Policy (per user decision 2026-04-13): block, do NOT auto-merge.
/// The just-signed-in user is signed back out and shown a Hebrew dialog
/// instructing them to use their original sign-in method.
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

  /// Convenience: checks for a conflict; if found, signs the current user
  /// out and shows the Hebrew "use your original method" dialog.
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

    // Conflict — sign back out so we don't leave a half-created session.
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
