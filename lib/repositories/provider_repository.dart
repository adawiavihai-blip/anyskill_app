import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/service_provider.dart';

/// Handles ALL Firebase operations for service providers (experts).
///
/// Covers: search, verification lifecycle, profile updates, admin actions.
class ProviderRepository {
  ProviderRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  ProviderRepository.dummy();

  late final FirebaseFirestore _db;

  // ── Read ──────────────────────────────────────────────────────────────

  /// Stream a single provider's profile in real-time.
  Stream<ServiceProvider?> watchProvider(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ServiceProvider.fromFirestore(doc);
    });
  }

  /// Fetch a single provider (one-shot).
  Future<ServiceProvider?> getProvider(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return ServiceProvider.fromFirestore(doc);
  }

  /// Fetch providers by category with cursor-based pagination.
  ///
  /// Returns search-visible providers only (client-side filtered).
  Future<List<ServiceProvider>> searchByCategory({
    required String categoryName,
    DocumentSnapshot? startAfter,
    int limit = 15,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('serviceType', isEqualTo: categoryName);

    if (startAfter != null) q = q.startAfterDocument(startAfter);
    q = q.limit(limit);

    final snap = await q.get();
    return snap.docs
        .map(ServiceProvider.fromFirestore)
        .where((p) => p.isSearchVisible)
        .toList();
  }

  /// Fetch all pending expert applications (admin).
  Future<List<ServiceProvider>> getPendingExperts() async {
    final snap = await _db
        .collection('users')
        .where('isPendingExpert', isEqualTo: true)
        .limit(100)
        .get();
    return snap.docs.map(ServiceProvider.fromFirestore).toList();
  }

  /// Fetch providers with unreviewed verification videos (admin).
  Future<List<ServiceProvider>> getUnreviewedVideos() async {
    final snap = await _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .limit(200)
        .get();
    return snap.docs
        .map(ServiceProvider.fromFirestore)
        .where((p) => p.hasUnreviewedVideo)
        .toList();
  }

  // ── Write: Profile ────────────────────────────────────────────────────

  /// Update provider's profile fields (name, about, price, etc.).
  Future<void> updateProfile(String uid, Map<String, dynamic> updates) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(uid).update(updates);
  }

  /// Update only the categoryDetails (dynamic schema values).
  Future<void> updateCategoryDetails(
      String uid, Map<String, dynamic> details) async {
    await _db.collection('users').doc(uid).update({
      'categoryDetails': details,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Write: Verification lifecycle (admin) ─────────────────────────────

  /// Approve a pending expert → makes them a live provider.
  Future<void> approveExpert(String uid) async {
    await _db.collection('users').doc(uid).update({
      'isPendingExpert': false,
      'isProvider':      true,
      'isVerified':      true,
      'categoryReviewedByAdmin': true,
    });
  }

  /// Reject a pending expert.
  Future<void> rejectExpert(String uid) async {
    await _db.collection('users').doc(uid).update({
      'isPendingExpert': false,
      'isProvider':      false,
      'categoryReviewedByAdmin': true,
    });
  }

  /// Toggle the blue checkmark (isVerified).
  Future<void> setVerified(String uid, bool verified) async {
    await _db.collection('users').doc(uid).update({
      'isVerified': verified,
    });
  }

  /// Toggle compliance status (isVerifiedProvider).
  Future<void> setComplianceVerified(String uid, bool verified) async {
    await _db.collection('users').doc(uid).update({
      'isVerifiedProvider': verified,
      'compliance': {'verified': verified},
    });
  }

  /// Approve a verification video.
  Future<void> approveVideo(String uid) async {
    await _db.collection('users').doc(uid).update({
      'videoVerifiedByAdmin': true,
    });
  }

  /// Reject a verification video.
  Future<void> rejectVideo(String uid) async {
    await _db.collection('users').doc(uid).update({
      'verificationVideoUrl': FieldValue.delete(),
      'videoVerifiedByAdmin': false,
    });
  }

  /// Ban or unban a provider.
  Future<void> setBanned(String uid, bool banned) async {
    await _db.collection('users').doc(uid).update({
      'isBanned': banned,
    });
  }

  /// Hide or unhide from search results.
  Future<void> setHidden(String uid, bool hidden) async {
    await _db.collection('users').doc(uid).update({
      'isHidden': hidden,
    });
  }

  /// Toggle the online status.
  Future<void> setOnline(String uid, bool online) async {
    await _db.collection('users').doc(uid).update({
      'isOnline': online,
    });
  }
}
