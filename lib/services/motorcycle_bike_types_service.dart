// Motorcycle Bike-Types Service.
//
// Manages the admin-editable catalog of motorcycle types used by the
// motorcycle towing CSM. Live source of truth: Firestore collection
// `motorcycle_bike_types/{id}`. Falls back to the static seed list in
// `motorcycle_bike_types_catalog.dart` when offline / empty.
//
// Provider settings block + customer booking block + customer profile view
// all read through this service so an admin's image swap propagates to
// every surface immediately.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../constants/motorcycle_bike_types_catalog.dart';

class MotorcycleBikeTypesService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static const _collection = 'motorcycle_bike_types';
  static const _storagePath = 'motorcycle_bike_types';

  /// Live stream of bike types ordered by id. When the collection is
  /// empty (e.g. brand-new project), emits the offline seed list so the
  /// UI never renders blank.
  static Stream<List<MotorcycleBikeType>> streamBikeTypes() {
    return _db.collection(_collection).orderBy('order').snapshots().map((q) {
      if (q.docs.isEmpty) return kMotorcycleBikeTypesFallback;
      return q.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        // The Firestore doc id is the canonical id. Override the map id so
        // legacy seeds with mismatched 'id' fields still resolve.
        data['id'] = d.id;
        return MotorcycleBikeType.fromMap(data);
      }).toList();
    });
  }

  /// One-shot fetch (used by the booking block on first mount). Falls back
  /// to the seed list on any error.
  static Future<List<MotorcycleBikeType>> fetchBikeTypes() async {
    try {
      final snap = await _db.collection(_collection).orderBy('order').get();
      if (snap.docs.isEmpty) return kMotorcycleBikeTypesFallback;
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return MotorcycleBikeType.fromMap(data);
      }).toList();
    } catch (e) {
      debugPrint('[MotorcycleBikeTypes] fetch failed: $e');
      return kMotorcycleBikeTypesFallback;
    }
  }

  /// Idempotent seed — writes the offline catalog into Firestore the first
  /// time the admin opens the management tab. Skips entries that already
  /// exist. Run as admin via `set(merge: true)`.
  static Future<void> ensureSeeded() async {
    try {
      for (var i = 0; i < kMotorcycleBikeTypesFallback.length; i++) {
        final t = kMotorcycleBikeTypesFallback[i];
        final ref = _db.collection(_collection).doc(t.id);
        final snap = await ref.get();
        if (snap.exists) continue;
        await ref.set({
          ...t.toMap(),
          'order': i,
          'providerCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[MotorcycleBikeTypes] seed failed: $e');
    }
  }

  /// Upsert a bike type. Used by the admin tab on save. Caller supplies
  /// the doc id; for brand-new entries the admin tab passes a slug derived
  /// from the English name.
  static Future<void> upsert({
    required String id,
    required String name,
    required String nameEn,
    required String imageUrl,
    bool active = true,
    int order = 999,
  }) {
    return _db.collection(_collection).doc(id).set({
      'id': id,
      'name': name,
      'nameEn': nameEn,
      'imageUrl': imageUrl,
      'active': active,
      'order': order,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Delete a bike type. Admin-only.
  static Future<void> delete(String id) {
    return _db.collection(_collection).doc(id).delete();
  }

  /// Uploads a bike-type image to Storage and returns the download URL.
  /// Path: `motorcycle_bike_types/{id}.{ext}`.
  static Future<String> uploadImage({
    required String id,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final ext = _extFromMime(contentType);
    final ref = _storage.ref('$_storagePath/$id.$ext');
    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  static String _extFromMime(String mime) {
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    return 'jpg';
  }

  /// Returns the count of providers who have selected each bike type.
  /// Used for the admin metadata "X נותני שירות מסמנים את הסוג הזה".
  /// Single-field aggregation — no composite index needed.
  static Future<int> countProvidersForBikeType(String bikeTypeId) async {
    try {
      final agg = await _db
          .collection('users')
          .where('motorcycleTowProfile.bikeTypeIds', arrayContains: bikeTypeId)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (e) {
      debugPrint(
          '[MotorcycleBikeTypes] count for $bikeTypeId failed: $e');
      return 0;
    }
  }
}
