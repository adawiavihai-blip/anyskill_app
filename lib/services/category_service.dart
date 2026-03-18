import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class CategoryService {
  static const Map<String, IconData> iconMap = {
    'build':                 Icons.build,
    'cleaning_services':     Icons.cleaning_services,
    'camera_alt':            Icons.camera_alt,
    'fitness_center':        Icons.fitness_center,
    'school':                Icons.school,
    'palette':               Icons.palette,
    'pets':                  Icons.pets,
    'restaurant':            Icons.restaurant,
    'local_hospital':        Icons.local_hospital,
    'music_note':            Icons.music_note,
    'computer':              Icons.computer,
    'car_repair':            Icons.car_repair,
    'landscape':             Icons.landscape,
    'home':                  Icons.home,
    'child_care':            Icons.child_care,
    'translate':             Icons.translate,
    'design_services':       Icons.design_services,
    'plumbing':              Icons.plumbing,
    'electrical_services':   Icons.electrical_services,
    'content_cut':           Icons.content_cut,
  };

  static IconData getIcon(String? iconName) =>
      iconMap[iconName] ?? Icons.work_outline;

  static Stream<List<Map<String, dynamic>>> stream() =>
      // NO orderBy on the Firestore query — Firestore silently excludes docs
      // that don't have the sorted field, causing Console-added categories to
      // disappear.  We fetch all docs and sort client-side.
      FirebaseFirestore.instance
          .collection('categories')
          .snapshots()
          .map((snap) {
            final cats = snap.docs
                .map((d) => {'id': d.id, ...d.data()})
                .toList();
            // Sort order (all client-side, all fields optional):
            //   1. clickCount DESC — most popular first
            //   2. order    ASC  — admin-defined order as tiebreaker
            //   3. name     ASC  — alphabetical as final tiebreaker
            cats.sort((a, b) {
              final cA = (a['clickCount'] as num? ?? 0).toInt();
              final cB = (b['clickCount'] as num? ?? 0).toInt();
              if (cA != cB) return cB.compareTo(cA); // DESC
              final oA = (a['order'] as num? ?? 999).toInt();
              final oB = (b['order'] as num? ?? 999).toInt();
              if (oA != oB) return oA.compareTo(oB);
              return (a['name'] as String? ?? '')
                  .compareTo(b['name'] as String? ?? '');
            });
            return cats;
          });

  /// Atomically increments the click counter for a category document.
  /// Uses FieldValue.increment so concurrent taps from multiple users
  /// never overwrite each other.
  static Future<void> incrementClickCount(String docId) =>
      FirebaseFirestore.instance
          .collection('categories')
          .doc(docId)
          .update({'clickCount': FieldValue.increment(1)})
          .catchError((_) {}); // best-effort — never crash the UI on tap

  /// Only top-level categories (parentId absent or empty string)
  static Stream<List<Map<String, dynamic>>> streamMainCategories() =>
      stream().map((cats) => cats
          .where((c) => (c['parentId'] as String? ?? '').isEmpty)
          .toList());

  /// Sub-categories belonging to a specific main category doc ID
  static Stream<List<Map<String, dynamic>>> streamSubCategories(String parentId) =>
      stream().map((cats) => cats
          .where((c) => c['parentId'] == parentId)
          .toList());

  /// Admin-only: update any fields on a category document.
  /// Strips null values so the Web SDK never receives undefined.
  static Future<void> updateCategory(
      String docId, Map<String, dynamic> updates) {
    // Remove nulls — Firestore Web SDK throws INTERNAL ASSERTION on null values
    updates.removeWhere((_, v) => v == null);
    return FirebaseFirestore.instance
        .collection('categories')
        .doc(docId)
        .update(updates);
  }

  /// Returns the number of active providers whose serviceType matches
  /// [categoryName].  Used to warn admins before deleting a category.
  static Future<int> activeProviderCount(String categoryName) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('serviceType', isEqualTo: categoryName)
        .limit(50)
        .get();
    return snap.docs.length;
  }

  /// Admin-only: permanently delete a category and all its sub-categories.
  /// Also removes the Storage image (best-effort — won't throw if absent).
  /// Call [activeProviderCount] first and warn the user if count > 0.
  static Future<void> deleteCategory(String docId, String imageUrl) async {
    final db = FirebaseFirestore.instance;

    // 1. Delete child sub-categories
    final subs = await db
        .collection('categories')
        .where('parentId', isEqualTo: docId)
        .get();
    for (final sub in subs.docs) {
      await sub.reference.delete();
    }

    // 2. Delete the category document itself
    await db.collection('categories').doc(docId).delete();

    // 3. Delete the Storage image (best-effort)
    if (imageUrl.isNotEmpty) {
      try {
        // Try resolving directly from the download URL first
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      } catch (_) {
        // Fall back to the known storage path used by CategoryEditSheet
        try {
          await FirebaseStorage.instance
              .ref('category_images/$docId.jpg')
              .delete();
        } catch (_) {}
      }
    }
  }
}
