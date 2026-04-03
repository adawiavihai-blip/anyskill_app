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
  ///
  /// Forces a **server read** (`GetOptions(source: Source.server)`) to avoid
  /// stale IndexedDB cache that may be missing fields like `profileImage`.
  /// Falls back to cache if the device is offline.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchUsersPage({
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> q = _users.limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);

    // Three-tier fetch (same pattern as OnboardingGate — never hangs):
    //   1. Server with 5s timeout
    //   2. Cache fallback
    //   3. Default get with 5s timeout
    try {
      return await q.get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      return await q.get(const GetOptions(source: Source.cache));
    } catch (_) {}
    return q.get().timeout(
      const Duration(seconds: 5),
      onTimeout: () => q.get(const GetOptions(source: Source.cache)),
    );
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
