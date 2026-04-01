import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../models/category.dart';

/// Handles ALL Firebase operations for the Categories system.
///
/// No UI code, no BuildContext. Pure data layer.
class CategoryRepository {
  CategoryRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db      = firestore ?? FirebaseFirestore.instance,
        _storage = storage;

  @visibleForTesting
  CategoryRepository.dummy() : _storage = null;

  late final FirebaseFirestore _db;
  final FirebaseStorage?      _storage;

  // ── Read ──────────────────────────────────────────────────────────────

  /// Real-time stream of ALL categories.
  /// Client-side sorted: clickCount DESC → order ASC → name ASC.
  Stream<List<Category>> watchAll() {
    return _db.collection('categories').snapshots().map((snap) {
      final cats = snap.docs.map(Category.fromFirestore).toList()
        ..sort((a, b) {
          if (a.clickCount != b.clickCount) {
            return b.clickCount.compareTo(a.clickCount);
          }
          if (a.order != b.order) return a.order.compareTo(b.order);
          return a.name.compareTo(b.name);
        });
      return cats;
    });
  }

  /// Only top-level categories (parentId is empty), excluding hidden.
  Stream<List<Category>> watchMainCategories() {
    return watchAll().map(
      (all) => all.where((c) => c.isTopLevel && !c.isHidden).toList(),
    );
  }

  /// Sub-categories for a given parent ID.
  Stream<List<Category>> watchSubCategories(String parentId) {
    return watchAll().map(
      (all) => all.where((c) => c.parentId == parentId).toList(),
    );
  }

  /// Load schema for a category by name (used by DynamicSchemaForm).
  Future<List<SchemaField>> loadSchema(String categoryName) async {
    final snap = await _db
        .collection('categories')
        .where('name', isEqualTo: categoryName)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return const [];
    final cat = Category.fromFirestore(snap.docs.first);
    return cat.serviceSchema;
  }

  // ── Write ─────────────────────────────────────────────────────────────

  /// Atomically increment the click counter for analytics.
  Future<void> incrementClick(String docId) async {
    try {
      await _db.collection('categories').doc(docId).update({
        'clickCount': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('[CategoryRepository] incrementClick failed: $e');
    }
  }

  /// Update category fields. Image is uploaded separately via [uploadImage].
  Future<void> update(String docId, Map<String, dynamic> updates) async {
    updates.removeWhere((_, v) => v == null);
    await _db.collection('categories').doc(docId).update(updates);
  }

  /// Server-side read to verify a write actually persisted.
  Future<Category?> verifyOnServer(String docId) async {
    final doc = await _db
        .collection('categories')
        .doc(docId)
        .get(const GetOptions(source: Source.server));
    if (!doc.exists) return null;
    return Category.fromFirestore(doc);
  }

  /// Upload a category image to Storage, returns the download URL.
  Future<String> uploadImage(String docId, Uint8List bytes) async {
    final storage = _storage ?? FirebaseStorage.instance;
    final ref = storage.ref().child('category_images/$docId.jpg');
    final snap = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return snap.ref.getDownloadURL();
  }

  /// Create a new category document.
  Future<void> create(Category category) async {
    await _db.collection('categories').doc(category.id).set(category.toJson());
  }

  /// Delete a category and its sub-categories + Storage image.
  Future<void> delete(String docId, String imageUrl) async {
    // 1. Delete sub-categories
    final subs = await _db
        .collection('categories')
        .where('parentId', isEqualTo: docId)
        .get();
    for (final sub in subs.docs) {
      await sub.reference.delete();
    }

    // 2. Delete the category itself
    await _db.collection('categories').doc(docId).delete();

    // 3. Delete Storage image (best-effort)
    if (imageUrl.isNotEmpty) {
      try {
        await (_storage ?? FirebaseStorage.instance).refFromURL(imageUrl).delete();
      } catch (e) {
        debugPrint('[CategoryRepository] Image delete failed (non-fatal): $e');
      }
    }
  }

  /// Count active providers in a category (admin check before delete).
  Future<int> activeProviderCount(String categoryName) async {
    final snap = await _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('serviceType', isEqualTo: categoryName)
        .limit(50)
        .get();
    return snap.docs.length;
  }
}
