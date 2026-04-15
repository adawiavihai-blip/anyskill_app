import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for reading/writing sensitive user data from the private subcollection.
///
/// Data model:
///   users/{uid}/private/financial → balance, pendingBalance, bankDetails
///   users/{uid}/private/identity  → phone, taxId, idNumber
///   users/{uid}/private/kyc       → idNumber, idDocUrl, selfieVerificationUrl,
///                                    businessDocUrl   (PR 1 — v11.9.x)
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
  ///
  /// v9.7.0 SECURITY: Caller MUST be the owner of [uid] or an admin.
  /// This prevents User A from reading User B's financial data.
  static Future<Map<String, dynamic>> getFinancialData(String uid) async {
    // ── Auth guard: only owner or admin may access ───────────────────────
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return {};
    if (currentUid != uid) {
      // Check if caller is admin before allowing cross-user access
      try {
        final callerDoc = await _db.collection('users').doc(currentUid).get();
        final isAdmin = (callerDoc.data() ?? {})['isAdmin'] == true;
        if (!isAdmin) {
          debugPrint('[PrivateData] BLOCKED: uid=$currentUid tried to read financial data of uid=$uid');
          return {};
        }
      } catch (_) {
        return {};
      }
    }

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
  ///
  /// v9.7.0 SECURITY: Same auth guard as getFinancialData.
  static Future<Map<String, dynamic>> getIdentityData(String uid) async {
    // ── Auth guard ──────────────────────────────────────────────────────
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return {};
    if (currentUid != uid) {
      try {
        final callerDoc = await _db.collection('users').doc(currentUid).get();
        final isAdmin = (callerDoc.data() ?? {})['isAdmin'] == true;
        if (!isAdmin) {
          debugPrint('[PrivateData] BLOCKED: uid=$currentUid tried to read identity data of uid=$uid');
          return {};
        }
      } catch (_) {
        return {};
      }
    }

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

  /// Read the current user's KYC data (idNumber + uploaded document URLs).
  /// Falls back to main user doc if `private/kyc` doesn't exist yet — this
  /// is what keeps pre-migration users visible in the admin verification queue.
  ///
  /// SECURITY: Owner or admin only, same pattern as [getFinancialData].
  static Future<Map<String, dynamic>> getKycData(String uid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return {};
    if (currentUid != uid) {
      try {
        final callerDoc = await _db.collection('users').doc(currentUid).get();
        final isAdmin = (callerDoc.data() ?? {})['isAdmin'] == true;
        if (!isAdmin) {
          debugPrint('[PrivateData] BLOCKED: uid=$currentUid tried to read KYC data of uid=$uid');
          return {};
        }
      } catch (_) {
        return {};
      }
    }

    try {
      final privateDoc = await _db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('kyc')
          .get();
      if (privateDoc.exists) return privateDoc.data() ?? {};
    } catch (_) {}
    // Legacy fallback — read KYC fields from the main user doc
    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};
    return {
      'idNumber':              data['idNumber'] ?? '',
      'idDocUrl':              data['idDocUrl'],
      'selfieVerificationUrl': data['selfieVerificationUrl'],
      'businessDocUrl':        data['businessDocUrl'],
    };
  }

  /// Write KYC fields into `private/kyc`. Called from onboarding + provider
  /// registration. During PR 1 rollout the same fields are ALSO written to
  /// the main user doc for backwards-compat with legacy readers. Future PR
  /// will stop the dual-write once all readers have migrated.
  ///
  /// Only non-null values are written (merge:true). Safe to call multiple
  /// times per user.
  static Future<void> writeKycData(
    String uid, {
    String? idNumber,
    String? idDocUrl,
    String? selfieVerificationUrl,
    String? businessDocUrl,
  }) async {
    final payload = <String, dynamic>{
      if (idNumber != null && idNumber.isNotEmpty) 'idNumber': idNumber,
      if (idDocUrl != null) 'idDocUrl': idDocUrl,
      if (selfieVerificationUrl != null) 'selfieVerificationUrl': selfieVerificationUrl,
      if (businessDocUrl != null) 'businessDocUrl': businessDocUrl,
    };
    if (payload.isEmpty) return;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('kyc')
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[PrivateData] writeKycData error: $e');
    }
  }

  /// Read the current user's contact data (phone + email).
  /// Falls back to main user doc if `private/identity` doesn't have these
  /// fields yet. Used by admin/support screens so the WhatsApp + tel:
  /// buttons keep working for pre-migration users.
  ///
  /// SECURITY: Owner or admin only. Support agents (role == 'support_agent')
  /// read contact data for customer 360 via Cloud Functions which bypass
  /// these rules — do NOT expand this helper to allow staff.
  static Future<Map<String, String?>> getContactData(String uid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return {'phone': null, 'email': null};
    if (currentUid != uid) {
      try {
        final callerDoc = await _db.collection('users').doc(currentUid).get();
        final isAdmin = (callerDoc.data() ?? {})['isAdmin'] == true;
        if (!isAdmin) {
          debugPrint('[PrivateData] BLOCKED: uid=$currentUid tried to read contact data of uid=$uid');
          return {'phone': null, 'email': null};
        }
      } catch (_) {
        return {'phone': null, 'email': null};
      }
    }

    String? phone;
    String? email;
    try {
      final privateDoc = await _db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('identity')
          .get();
      if (privateDoc.exists) {
        final d = privateDoc.data() ?? {};
        phone = (d['phone'] as String?)?.trim();
        email = (d['email'] as String?)?.trim();
      }
    } catch (_) {}

    // Legacy fallback — any missing field comes from the main user doc
    if ((phone == null || phone.isEmpty) || (email == null || email.isEmpty)) {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        final d = userDoc.data() ?? {};
        phone ??= (d['phone'] as String?)?.trim();
        email ??= (d['email'] as String?)?.trim();
      } catch (_) {}
    }

    return {'phone': phone, 'email': email};
  }

  /// Mirror contact fields into `private/identity`. Called from onboarding.
  /// Dual-write pattern (matches [writeKycData]) — main-doc writes are
  /// preserved until every reader migrates.
  static Future<void> writeContactData(
    String uid, {
    String? phone,
    String? email,
  }) async {
    final payload = <String, dynamic>{
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
    };
    if (payload.isEmpty) return;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('identity')
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[PrivateData] writeContactData error: $e');
    }
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

    // Identity data (includes email — PR 2a)
    batch.set(privateRef.doc('identity'), {
      'phone': data['phone'] ?? '',
      if (data['email']    != null) 'email':    data['email'],
      if (data['taxId']    != null) 'taxId':    data['taxId'],
      if (data['idNumber'] != null) 'idNumber': data['idNumber'],
      'migratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // KYC data (PR 1) — id number + uploaded document URLs
    batch.set(privateRef.doc('kyc'), {
      if (data['idNumber']              != null) 'idNumber':              data['idNumber'],
      if (data['idDocUrl']              != null) 'idDocUrl':              data['idDocUrl'],
      if (data['selfieVerificationUrl'] != null) 'selfieVerificationUrl': data['selfieVerificationUrl'],
      if (data['businessDocUrl']        != null) 'businessDocUrl':        data['businessDocUrl'],
      'migratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Check if the current user is the owner of the requested uid.
  static bool isOwner(String uid) {
    return FirebaseAuth.instance.currentUser?.uid == uid;
  }
}
