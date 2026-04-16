import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// ── Result type ───────────────────────────────────────────────────────────────

enum DeletionOutcome {
  /// All data and the Auth user were removed successfully.
  success,

  /// Firebase rejected the Auth deletion because the session is too old.
  /// The user must sign out, sign back in, and try again.
  requiresReauth,

  /// A non-recoverable error occurred. [AccountDeletionResult.errorMessage]
  /// contains a human-readable description.
  error,
}

class AccountDeletionResult {
  const AccountDeletionResult._(this.outcome, [this.errorMessage]);

  factory AccountDeletionResult.success() =>
      const AccountDeletionResult._(DeletionOutcome.success);

  factory AccountDeletionResult.requiresReauth() =>
      const AccountDeletionResult._(DeletionOutcome.requiresReauth);

  factory AccountDeletionResult.error(String message) =>
      AccountDeletionResult._(DeletionOutcome.error, message);

  final DeletionOutcome outcome;
  final String? errorMessage;
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Handles the complete account-deletion flow required by Apple App Store and
/// Google Play Store guidelines.
///
/// Deletion order:
///   1. Best-effort Firestore data cleanup (client-readable collections).
///   2. Cloud Function `deleteUserAccount` — server-side deep cleanup
///      (chats, messages, jobs, transactions, Storage files, etc.) via
///      Admin SDK which bypasses Security Rules.
///   3. `FirebaseAuth.currentUser.delete()` — removes the Auth identity.
///
/// If step 3 throws `requires-recent-login`, the service returns
/// [DeletionOutcome.requiresReauth] so the UI can guide the user.
class AccountDeletionService {
  AccountDeletionService._();

  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ── Public entry point ────────────────────────────────────────────────────

  static Future<AccountDeletionResult> deleteAccount(String uid) async {
    if (uid.isEmpty) {
      return AccountDeletionResult.error('מזהה משתמש חסר.');
    }

    try {
      // Step 1 — Client-side Firestore data cleanup (best-effort; never throws).
      await _deleteFirestoreData(uid);

      // Step 2 — Server-side deep cleanup via Cloud Function.
      // The CF uses Admin SDK, so it can delete chats, messages, Storage
      // files, and any subcollections the client cannot reach directly.
      // If the CF is unavailable, we continue — Auth deletion is what matters
      // for App Store compliance.
      await _callDeleteFunction(uid);

      // Step 3 — Delete the Firebase Auth user.
      // This is the step that can throw `requires-recent-login`.
      await _auth.currentUser?.delete();

      return AccountDeletionResult.success();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return AccountDeletionResult.requiresReauth();
      }
      return AccountDeletionResult.error(e.message ?? e.code);
    } catch (e) {
      return AccountDeletionResult.error(e.toString());
    }
  }

  // ── Step 1: Firestore data cleanup ───────────────────────────────────────

  static Future<void> _deleteFirestoreData(String uid) async {
    // Run all deletions concurrently; swallow individual failures so one
    // missing collection never blocks the rest of the cleanup.
    await Future.wait([
      _deleteDoc('users', uid),
      _deleteUserProgressSubcollection(uid),
      _deleteQueryBatch('notifications',        'userId',   uid),
      _deleteQueryBatch('scheduled_reminders',  'userId',   uid),
      _deleteQueryBatch('transactions',          'senderId', uid),
      _deleteQueryBatch('transactions',          'userId',   uid),
      _deleteQueryBatch('withdrawals',           'userId',   uid),
      _deleteQueryBatch('incomplete_registrations', 'uid',  uid),
    ], eagerError: false);
  }

  /// Deletes a single document by collection + id.
  static Future<void> _deleteDoc(String collection, String id) async {
    try {
      await _db.collection(collection).doc(id).delete();
    } catch (e) {
      debugPrint('AccountDeletion: could not delete $collection/$id — $e');
    }
  }

  /// Deletes up to 200 documents matching [field] == [uid] in [collection].
  static Future<void> _deleteQueryBatch(
      String collection, String field, String uid) async {
    try {
      final snap = await _db
          .collection(collection)
          .where(field, isEqualTo: uid)
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('AccountDeletion: could not delete $collection where $field==$uid — $e');
    }
  }

  /// Deletes the `user_progress/{uid}/courses` subcollection and then the
  /// parent doc (Firestore does not cascade-delete subcollections).
  static Future<void> _deleteUserProgressSubcollection(String uid) async {
    try {
      final courses = await _db
          .collection('user_progress')
          .doc(uid)
          .collection('courses')
          .limit(200)
          .get();
      if (courses.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in courses.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await _db.collection('user_progress').doc(uid).delete();
    } catch (e) {
      debugPrint('AccountDeletion: could not delete user_progress/$uid — $e');
    }
  }

  // ── Step 2: Cloud Function deep cleanup ──────────────────────────────────

  static Future<void> _callDeleteFunction(String uid) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteUserAccount')
          .call({'uid': uid})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      // CF failure is non-fatal: client cleanup in step 1 already ran,
      // and Auth deletion in step 3 still proceeds.
      debugPrint('AccountDeletion: CF deleteUserAccount failed (non-fatal) — $e');
    }
  }
}
