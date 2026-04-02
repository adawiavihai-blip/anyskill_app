import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for reading/writing sensitive user data from the private subcollection.
///
/// Data model:
///   users/{uid}/private/financial → balance, pendingBalance, bankDetails
///   users/{uid}/private/identity  → phone, taxId, idNumber
///
/// Only the owner (isOwner) or admin can read these docs.
/// Cloud Functions (Admin SDK) bypass rules and can always access.
///
/// During the migration period, this service reads from the private subcollection
/// first, falling back to the main user doc for backwards compatibility.
class PrivateDataService {
  static final _db = FirebaseFirestore.instance;

  /// Read the current user's financial data (balance, pendingBalance, bankDetails).
  /// Falls back to main user doc if private subcollection doesn't exist yet.
  static Future<Map<String, dynamic>> getFinancialData(String uid) async {
    try {
      final privateDoc = await _db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('financial')
          .get();
      if (privateDoc.exists) return privateDoc.data() ?? {};
    } catch (_) {
      // Permission denied or doc doesn't exist — fall back to main doc
    }
    // Fallback: read from main user doc (legacy)
    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};
    return {
      'balance': data['balance'] ?? 0.0,
      'pendingBalance': data['pendingBalance'] ?? 0.0,
      'bankDetails': data['bankDetails'],
    };
  }

  /// Read the current user's identity data (phone, taxId, idNumber).
  /// Falls back to main user doc if private subcollection doesn't exist yet.
  static Future<Map<String, dynamic>> getIdentityData(String uid) async {
    try {
      final privateDoc = await _db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('identity')
          .get();
      if (privateDoc.exists) return privateDoc.data() ?? {};
    } catch (_) {}
    // Fallback: read from main user doc (legacy)
    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};
    return {
      'phone': data['phone'] ?? '',
      'taxId': data['taxId'] ?? '',
      'idNumber': data['idNumber'] ?? '',
    };
  }

  /// Stream the current user's financial data (real-time updates).
  static Stream<Map<String, dynamic>> streamFinancialData(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('financial')
        .snapshots()
        .map((snap) => snap.data() ?? {});
  }

  /// Migrate sensitive fields from main user doc to private subcollection.
  /// Call this once per user (e.g., on profile screen load).
  /// Idempotent — safe to call multiple times.
  static Future<void> migrateIfNeeded(String uid) async {
    final privateRef = _db.collection('users').doc(uid).collection('private');

    // Check if already migrated
    final financialDoc = await privateRef.doc('financial').get();
    if (financialDoc.exists) return; // Already migrated

    // Read from main doc
    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};

    final batch = _db.batch();

    // Financial data
    batch.set(privateRef.doc('financial'), {
      'balance': data['balance'] ?? 0.0,
      'pendingBalance': data['pendingBalance'] ?? 0.0,
      if (data['bankDetails'] != null) 'bankDetails': data['bankDetails'],
      'migratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Identity data
    batch.set(privateRef.doc('identity'), {
      'phone': data['phone'] ?? '',
      if (data['taxId'] != null) 'taxId': data['taxId'],
      if (data['idNumber'] != null) 'idNumber': data['idNumber'],
      'migratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Check if the current user is the owner of the requested uid.
  static bool isOwner(String uid) {
    return FirebaseAuth.instance.currentUser?.uid == uid;
  }
}
