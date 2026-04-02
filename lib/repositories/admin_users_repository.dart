import 'package:cloud_firestore/cloud_firestore.dart';

/// Data-layer for admin user management.
///
/// UI must NEVER import `cloud_firestore` directly — all reads/writes go
/// through this repository.  This makes the admin panel testable (inject a
/// `FakeFirebaseFirestore`) and keeps Firestore details out of widgets.
class AdminUsersRepository {
  AdminUsersRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ── Paginated fetch ────────────────────────────────────────────────────

  /// Fetch one page of users (cursor-based pagination).
  /// Returns the raw [QuerySnapshot] so the provider can extract both the
  /// docs AND the cursor for the next page.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchUsersPage({
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q = _users.limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q.get();
  }

  // ── Single-user stream ─────────────────────────────────────────────────

  /// Real-time stream of a single user document.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String uid) {
    return _users.doc(uid).snapshots();
  }

  // ── Admin write operations ─────────────────────────────────────────────

  Future<void> updateUser(String uid, Map<String, dynamic> fields) {
    return _users.doc(uid).update(fields);
  }

  Future<void> toggleVerified(String uid, bool current) {
    return _users.doc(uid).update({'isVerified': !current});
  }

  Future<void> togglePromoted(String uid, bool current) {
    return _users.doc(uid).update({'isPromoted': !current});
  }

  Future<void> toggleBanned(String uid, bool current) {
    return _users.doc(uid).update({'isBanned': !current});
  }

  Future<void> approveProvider(String uid) {
    return _users.doc(uid).update({
      'isVerifiedProvider': true,
      'compliance.verified': true,
    });
  }

  Future<void> revokeProvider(String uid) {
    return _users.doc(uid).update({'isVerifiedProvider': false});
  }

  Future<void> setCustomCommission(String uid, double? rate) {
    if (rate == null) {
      return _users.doc(uid).update({
        'customCommission': FieldValue.delete(),
      });
    }
    return _users.doc(uid).update({'customCommission': rate});
  }

  Future<void> setAdminNote(String uid, String note) {
    return _users.doc(uid).update({'adminNote': note});
  }

  Future<void> deleteUser(String uid) {
    return _users.doc(uid).delete();
  }
}
