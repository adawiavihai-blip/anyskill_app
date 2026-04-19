import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/saved_view.dart';

/// Per-admin saved filter / sort presets. Stored at
/// `admin_saved_views/{viewId}` keyed implicitly by `admin_uid`.
class SavedViewsService {
  SavedViewsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('admin_saved_views');

  /// Streams the current admin's saved views, default-first then by
  /// creation time. Capped at 50 (admins won't realistically save more).
  Stream<List<SavedView>> watchMine() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Stream<List<SavedView>>.empty();
    }
    return _col
        .where('admin_uid', isEqualTo: uid)
        .orderBy('is_default', descending: true)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(SavedView.fromDoc).toList());
  }

  Future<String> save({
    required String name,
    required SavedViewFilters filters,
    required CategorySort sortBy,
    required ViewMode viewMode,
    bool isDefault = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('not-authenticated');

    // If marking this as default, unset the previous default in a single
    // batch so we never end up with two defaults at the same time.
    final batch = _db.batch();
    if (isDefault) {
      final prevDefault = await _col
          .where('admin_uid', isEqualTo: uid)
          .where('is_default', isEqualTo: true)
          .limit(5)
          .get();
      for (final doc in prevDefault.docs) {
        batch.update(doc.reference, <String, dynamic>{'is_default': false});
      }
    }

    final ref = _col.doc();
    batch.set(
      ref,
      SavedView(
        id: ref.id,
        adminUid: uid,
        name: name,
        filters: filters,
        sortBy: sortBy,
        viewMode: viewMode,
        isDefault: isDefault,
      ).toMap(),
    );
    await batch.commit();
    return ref.id;
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  Future<void> setAsDefault(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('not-authenticated');

    final batch = _db.batch();
    final prev = await _col
        .where('admin_uid', isEqualTo: uid)
        .where('is_default', isEqualTo: true)
        .limit(5)
        .get();
    for (final doc in prev.docs) {
      batch.update(doc.reference, <String, dynamic>{'is_default': false});
    }
    batch.update(_col.doc(id), <String, dynamic>{'is_default': true});
    await batch.commit();
  }
}
