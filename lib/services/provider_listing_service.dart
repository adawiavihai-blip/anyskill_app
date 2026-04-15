import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// v10.1.0: Dual-Identity Provider Listing Service
///
/// Manages the `provider_listings` collection — each doc represents one
/// professional identity for a provider. A provider can have up to 2 listings
/// (identityIndex 0 = primary, 1 = secondary).
///
/// The `users/{uid}` doc remains the auth/account record. Identity-specific
/// fields (serviceType, price, gallery, rating) live on the listing doc.
/// Shared fields (name, profileImage, isOnline, location) are denormalized
/// from the user doc onto every listing for efficient search queries.
class ProviderListingService {
  ProviderListingService._();

  static final _db = FirebaseFirestore.instance;
  static const _col = 'provider_listings';
  static const int maxIdentities = 2;

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Get all listings for a user (1 or 2 docs).
  static Future<List<Map<String, dynamic>>> getListings(String uid) async {
    final snap = await _db
        .collection(_col)
        .where('uid', isEqualTo: uid)
        .orderBy('identityIndex')
        .limit(maxIdentities)
        .get();
    return snap.docs.map((d) {
      final m = d.data();
      m['listingId'] = d.id;
      return m;
    }).toList();
  }

  /// Stream all listings for a user (real-time).
  static Stream<List<Map<String, dynamic>>> streamListings(String uid) {
    return _db
        .collection(_col)
        .where('uid', isEqualTo: uid)
        .orderBy('identityIndex')
        .limit(maxIdentities)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              m['listingId'] = d.id;
              return m;
            }).toList());
  }

  /// Get a single listing by ID.
  static Future<Map<String, dynamic>?> getListing(String listingId) async {
    final snap = await _db.collection(_col).doc(listingId).get();
    if (!snap.exists) return null;
    final m = snap.data() ?? {};
    m['listingId'] = snap.id;
    return m;
  }

  // ── Create ──────────────────────────────────────────────────────────────

  /// Create a new listing for the current user.
  /// Returns the new listing doc ID.
  static Future<String> createListing({
    required String uid,
    required int identityIndex,
    required String serviceType,
    String? parentCategory,
    String? subCategory,
    required String aboutMe,
    double pricePerHour = 0,
    List<dynamic> gallery = const [],
    Map<String, dynamic> categoryDetails = const {},
    Map<String, dynamic> priceList = const {},
    List<String> quickTags = const [],
    Map<String, dynamic> workingHours = const {},
    String cancellationPolicy = 'flexible',
  }) async {
    // Enforce max 2 identities
    final existing = await getListings(uid);
    if (existing.length >= maxIdentities) {
      throw Exception('ניתן ליצור עד $maxIdentities זהויות מקצועיות');
    }
    if (existing.any((l) => l['identityIndex'] == identityIndex)) {
      throw Exception('זהות מקצועית $identityIndex כבר קיימת');
    }

    // Read shared fields from user doc for denormalization
    final userSnap = await _db.collection('users').doc(uid).get();
    final u = userSnap.data() ?? {};

    final ref = await _db.collection(_col).add({
      'uid': uid,
      'identityIndex': identityIndex,
      // Denormalized shared fields
      'name': u['name'] ?? '',
      'profileImage': u['profileImage'] ?? '',
      'isVerified': u['isVerified'] ?? false,
      'isHidden': u['isHidden'] ?? false,
      'isDemo': u['isDemo'] ?? false,
      'isVolunteer': u['isVolunteer'] ?? false,
      'isOnline': u['isOnline'] ?? false,
      'isAnySkillPro': u['isAnySkillPro'] ?? false,
      'isPromoted': u['isPromoted'] ?? false,
      'profileBoostUntil': u['profileBoostUntil'],
      'latitude': u['latitude'],
      'longitude': u['longitude'],
      'geohash': u['geohash'],
      // Identity-specific fields
      'serviceType': serviceType,
      'parentCategory': parentCategory ?? '',
      'subCategory': subCategory ?? '',
      'aboutMe': aboutMe,
      'pricePerHour': pricePerHour,
      'gallery': gallery,
      'categoryDetails': categoryDetails,
      'priceList': priceList,
      'quickTags': quickTags,
      'workingHours': workingHours,
      'cancellationPolicy': cancellationPolicy,
      // Per-identity ratings (start fresh for new identities)
      'rating': identityIndex == 0 ? (u['rating'] ?? 5.0) : 5.0,
      'reviewsCount': identityIndex == 0 ? (u['reviewsCount'] ?? 0) : 0,
      // Metadata
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update user doc with listing reference
    final listingIds = List<String>.from(u['listingIds'] ?? []);
    listingIds.add(ref.id);
    await _db.collection('users').doc(uid).update({
      'listingIds': listingIds,
      'activeIdentityCount': listingIds.length,
    });

    return ref.id;
  }

  // ── Update ──────────────────────────────────────────────────────────────

  /// Update identity-specific fields on a listing.
  static Future<void> updateListing(
    String listingId,
    Map<String, dynamic> updates,
  ) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection(_col).doc(listingId).update(updates);
  }

  /// Sync shared fields (name, profileImage, isOnline, location) from user
  /// doc to all their listings. Call this whenever these fields change on
  /// the user doc (e.g., online toggle, name edit, profile image upload).
  static Future<void> syncSharedFields(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final u = userSnap.data() ?? {};
    final listings = await getListings(uid);
    if (listings.isEmpty) return;

    final batch = _db.batch();
    final shared = {
      'name': u['name'] ?? '',
      'profileImage': u['profileImage'] ?? '',
      'isOnline': u['isOnline'] ?? false,
      'isVerified': u['isVerified'] ?? false,
      'isHidden': u['isHidden'] ?? false,
      'isVolunteer': u['isVolunteer'] ?? false,
      'isAnySkillPro': u['isAnySkillPro'] ?? false,
      'isPromoted': u['isPromoted'] ?? false,
      'profileBoostUntil': u['profileBoostUntil'],
      'latitude': u['latitude'],
      'longitude': u['longitude'],
      'geohash': u['geohash'],
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final l in listings) {
      batch.update(_db.collection(_col).doc(l['listingId'] as String), shared);
    }
    await batch.commit();
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  /// Delete a listing (e.g., removing a second identity).
  static Future<void> deleteListing(String listingId, String uid) async {
    await _db.collection(_col).doc(listingId).delete();
    // Update user doc
    final userSnap = await _db.collection('users').doc(uid).get();
    final listingIds = List<String>.from(
        (userSnap.data() ?? {})['listingIds'] ?? []);
    listingIds.remove(listingId);
    await _db.collection('users').doc(uid).update({
      'listingIds': listingIds,
      'activeIdentityCount': listingIds.length,
    });
  }

  // ── Migration ───────────────────────────────────────────────────────────

  /// Migrate an existing provider to the dual-identity system.
  /// Creates a primary listing (identityIndex: 0) from their current user doc.
  /// Idempotent — skips if listing already exists.
  static Future<String?> migrateIfNeeded(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final u = userSnap.data() ?? {};
    if (u['isProvider'] != true) return null;

    // Already migrated?
    final existingIds = List<String>.from(u['listingIds'] ?? []);
    if (existingIds.isNotEmpty) return existingIds.first;

    // No serviceType → nothing to migrate
    final serviceType = u['serviceType'] as String? ?? '';
    if (serviceType.isEmpty) return null;

    debugPrint('[ListingMigration] Migrating uid=$uid serviceType=$serviceType');

    final listingId = await createListing(
      uid: uid,
      identityIndex: 0,
      serviceType: serviceType,
      parentCategory: u['parentCategory'] as String?,
      subCategory: u['subCategory'] as String?,
      aboutMe: u['aboutMe'] as String? ?? '',
      pricePerHour: (u['pricePerHour'] as num?)?.toDouble() ?? 0,
      gallery: List<dynamic>.from(u['gallery'] ?? []),
      categoryDetails: Map<String, dynamic>.from(u['categoryDetails'] ?? {}),
      priceList: Map<String, dynamic>.from(u['priceList'] ?? {}),
      quickTags: List<String>.from(u['quickTags'] ?? []),
      workingHours: Map<String, dynamic>.from(u['workingHours'] ?? {}),
      cancellationPolicy: u['cancellationPolicy'] as String? ?? 'flexible',
    );

    // Backfill existing reviews with listingId
    try {
      final reviewSnap = await _db
          .collection('reviews')
          .where('revieweeId', isEqualTo: uid)
          .limit(200)
          .get();
      if (reviewSnap.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in reviewSnap.docs) {
          if (doc.data()['listingId'] == null) {
            batch.update(doc.reference, {'listingId': listingId});
          }
        }
        await batch.commit();
        debugPrint('[ListingMigration] Backfilled ${reviewSnap.docs.length} reviews');
      }
    } catch (e) {
      debugPrint('[ListingMigration] Review backfill error: $e');
    }

    return listingId;
  }
}
