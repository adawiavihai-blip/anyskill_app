import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart' as ff;

import '../models/activity_log_entry.dart';
import '../models/category_v3_model.dart';
import 'activity_log_service.dart';

/// CRUD + ordering + bulk operations against the `categories` collection.
///
/// Runs alongside the legacy [CategoryService] (per Q1 — additive only).
/// Every mutation logs to `admin_activity_log` via [ActivityLogService] so
/// the Activity Log panel + Undo flow stay in sync.
class CategoriesV3Service {
  CategoriesV3Service({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ActivityLogService? activityLog,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _activityLog = activityLog ?? ActivityLogService();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ActivityLogService _activityLog;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('categories');

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Streams ALL categories (root + sub) as v3 models. Capped at 200 to honor
  /// CLAUDE.md §17 Rule 1. Live updates feed the admin tab in real time.
  Stream<List<CategoryV3Model>> watchAll() {
    return _col.limit(200).snapshots().map(
          (snap) =>
              snap.docs.map((d) => CategoryV3Model.fromDoc(d)).toList(),
        );
  }

  /// One-shot read of a single category. Used when we need a fresh snapshot
  /// for `payload_before` audit.
  Future<CategoryV3Model?> getOnce(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return CategoryV3Model.fromDoc(doc);
  }

  // ── Writes (each goes through activity-log) ───────────────────────────────

  /// Creates a new category. Returns the new doc ID.
  Future<String> create({
    required String name,
    required String iconUrl,
    String parentId = '',
    int? order,
    String? imageUrl,
    String? color,
    String? csmModule,
    List<String> customTags = const [],
  }) async {
    final adminUid = _requireAdminUid();
    final now = Timestamp.now();
    final payload = <String, dynamic>{
      'name': name,
      'iconUrl': iconUrl,
      'parentId': parentId,
      if (order != null) 'order': order,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (color != null) 'color': color,
      'clickCount': 0,
      'admin_meta': <String, dynamic>{
        'is_pinned': false,
        'is_hidden': false,
        'last_edited_by': adminUid,
        'last_edited_at': now,
        'last_edited_action': 'created',
        'notes': '',
      },
      if (csmModule != null) 'csm_module': csmModule,
      'custom_tags': customTags,
      'createdAt': now,
    };

    final ref = await _col.add(payload);

    await _activityLog.log(
      actionType: ActivityActionType.create,
      targetType: ActivityTargetType.category,
      targetId: ref.id,
      targetName: name,
      payloadBefore: const <String, dynamic>{},
      payloadAfter: payload,
    );

    return ref.id;
  }

  /// Updates arbitrary fields. Caller is responsible for omitting protected
  /// fields (e.g. `analytics` is server-only — the CF owns it). This method
  /// does not enforce that, the security rules do.
  Future<void> update(
    String id,
    Map<String, dynamic> patch, {
    String? action,
  }) async {
    final adminUid = _requireAdminUid();
    final before = await getOnce(id);
    if (before == null) {
      throw StateError('category-not-found:$id');
    }

    final now = Timestamp.now();
    final fullPatch = <String, dynamic>{
      ...patch,
      'admin_meta.last_edited_by': adminUid,
      'admin_meta.last_edited_at': now,
      if (action != null) 'admin_meta.last_edited_action': action,
    };

    await _col.doc(id).update(fullPatch);

    await _activityLog.log(
      actionType: action == 'image_changed'
          ? ActivityActionType.imageUpdate
          : ActivityActionType.update,
      targetType: ActivityTargetType.category,
      targetId: id,
      targetName: before.name,
      payloadBefore: _snapshotForUndo(before),
      payloadAfter: patch,
    );
  }

  Future<void> delete(String id) async {
    final before = await getOnce(id);
    if (before == null) return;

    await _col.doc(id).delete();

    await _activityLog.log(
      actionType: ActivityActionType.delete,
      targetType: ActivityTargetType.category,
      targetId: id,
      targetName: before.name,
      payloadBefore: _snapshotForUndo(before),
      payloadAfter: const <String, dynamic>{},
    );
  }

  /// Persists drag-and-drop reorder. Caller passes the FULL ordered list of
  /// root category ids. We write a batch with sequential `order` values 0..n-1
  /// so subsequent sort-by-order queries are stable.
  ///
  /// Debouncing (500ms per spec §10) is the caller's responsibility — the
  /// service writes immediately when invoked.
  Future<void> reorderRootCategories(List<String> orderedIds) async {
    final adminUid = _requireAdminUid();
    final now = Timestamp.now();
    final batch = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_col.doc(orderedIds[i]), <String, dynamic>{
        'order': i,
        'admin_meta.last_edited_by': adminUid,
        'admin_meta.last_edited_at': now,
        'admin_meta.last_edited_action': 'reordered',
      });
    }
    await batch.commit();

    await _activityLog.log(
      actionType: ActivityActionType.reorder,
      targetType: ActivityTargetType.category,
      targetId: 'bulk',
      targetName: 'סדר קטגוריות שורש',
      payloadBefore: const <String, dynamic>{},
      payloadAfter: <String, dynamic>{'order': orderedIds},
    );
  }

  Future<void> togglePin(String id) async {
    final before = await getOnce(id);
    if (before == null) return;
    final newValue = !before.isPinned;
    await update(
      id,
      <String, dynamic>{'admin_meta.is_pinned': newValue},
      action: newValue ? 'pinned' : 'unpinned',
    );
    // Override action type in the log entry that update() just wrote — re-log
    // with the more precise pin/unpin action so the panel filter works.
    await _activityLog.log(
      actionType:
          newValue ? ActivityActionType.pin : ActivityActionType.unpin,
      targetType: ActivityTargetType.category,
      targetId: id,
      targetName: before.name,
      payloadBefore: <String, dynamic>{
        'admin_meta': <String, dynamic>{'is_pinned': before.isPinned},
      },
      payloadAfter: <String, dynamic>{
        'admin_meta': <String, dynamic>{'is_pinned': newValue},
      },
    );
  }

  Future<void> toggleHide(String id) async {
    final before = await getOnce(id);
    if (before == null) return;
    final newValue = !before.isHidden;
    await update(
      id,
      <String, dynamic>{'admin_meta.is_hidden': newValue},
      action: newValue ? 'hidden' : 'unhidden',
    );
    await _activityLog.log(
      actionType:
          newValue ? ActivityActionType.hide : ActivityActionType.unhide,
      targetType: ActivityTargetType.category,
      targetId: id,
      targetName: before.name,
      payloadBefore: <String, dynamic>{
        'admin_meta': <String, dynamic>{'is_hidden': before.isHidden},
      },
      payloadAfter: <String, dynamic>{
        'admin_meta': <String, dynamic>{'is_hidden': newValue},
      },
    );
  }

  // ── Bulk ops ──────────────────────────────────────────────────────────────

  Future<void> bulkHide(Iterable<String> ids, {required bool hide}) async {
    final adminUid = _requireAdminUid();
    final now = Timestamp.now();
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col.doc(id), <String, dynamic>{
        'admin_meta.is_hidden': hide,
        'admin_meta.last_edited_by': adminUid,
        'admin_meta.last_edited_at': now,
        'admin_meta.last_edited_action': hide ? 'bulk_hide' : 'bulk_unhide',
      });
    }
    await batch.commit();

    await _activityLog.log(
      actionType: ActivityActionType.bulkAction,
      targetType: ActivityTargetType.category,
      targetId: 'bulk',
      targetName: hide
          ? '${ids.length} קטגוריות הוסתרו'
          : '${ids.length} קטגוריות נחשפו',
      payloadBefore: <String, dynamic>{'ids': ids.toList()},
      payloadAfter: <String, dynamic>{'is_hidden': hide},
    );
  }

  Future<void> bulkPin(Iterable<String> ids, {required bool pin}) async {
    final adminUid = _requireAdminUid();
    final now = Timestamp.now();
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col.doc(id), <String, dynamic>{
        'admin_meta.is_pinned': pin,
        'admin_meta.last_edited_by': adminUid,
        'admin_meta.last_edited_at': now,
        'admin_meta.last_edited_action': pin ? 'bulk_pin' : 'bulk_unpin',
      });
    }
    await batch.commit();

    await _activityLog.log(
      actionType: ActivityActionType.bulkAction,
      targetType: ActivityTargetType.category,
      targetId: 'bulk',
      targetName: pin
          ? '${ids.length} קטגוריות קודמו'
          : '${ids.length} קטגוריות הורדו מקידום',
      payloadBefore: <String, dynamic>{'ids': ids.toList()},
      payloadAfter: <String, dynamic>{'is_pinned': pin},
    );
  }

  Future<void> bulkDelete(Iterable<String> ids) async {
    final batch = _db.batch();
    final names = <String>[];
    for (final id in ids) {
      final snap = await _col.doc(id).get();
      if (snap.exists) {
        names.add((snap.data()?['name'] as String?) ?? id);
        batch.delete(_col.doc(id));
      }
    }
    await batch.commit();

    await _activityLog.log(
      actionType: ActivityActionType.bulkAction,
      targetType: ActivityTargetType.category,
      targetId: 'bulk',
      targetName: '${names.length} קטגוריות נמחקו',
      payloadBefore: <String, dynamic>{'ids': ids.toList(), 'names': names},
      payloadAfter: const <String, dynamic>{},
    );
  }

  // ── Power-tools ───────────────────────────────────────────────────────────

  /// Triggers a manual analytics refresh. The scheduled
  /// `updateCategoryAnalytics` CF runs every 15 min on its own; this calls
  /// the callable sibling `refreshCategoryAnalyticsNow` for the admin tab's
  /// "refresh" button.
  Future<Map<String, dynamic>> triggerAnalyticsRefresh() async {
    final callable = ff.FirebaseFunctions.instance
        .httpsCallable('refreshCategoryAnalyticsNow');
    final res = await callable.call(<String, dynamic>{});
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'ok': true};
  }

  /// One-shot backfill — calls the admin-only CF that initializes
  /// `admin_meta` + `custom_tags` on legacy category docs. Idempotent.
  /// Run this once after Phase A deploy.
  Future<Map<String, dynamic>> runBackfill() async {
    final callable = ff.FirebaseFunctions.instance
        .httpsCallable('backfillCategoriesV3');
    final res = await callable.call(<String, dynamic>{});
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'ok': true};
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _requireAdminUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('not-authenticated');
    }
    return uid;
  }

  /// Snapshots only the fields we know how to restore via Undo. We DO NOT
  /// persist `analytics` (CF-owned) or `clickCount` (live counter) to keep
  /// the audit log compact.
  Map<String, dynamic> _snapshotForUndo(CategoryV3Model c) =>
      <String, dynamic>{
        'name': c.name,
        'iconUrl': c.iconUrl,
        'parentId': c.parentId,
        'order': c.order,
        if (c.imageUrl != null) 'imageUrl': c.imageUrl,
        if (c.color != null) 'color': c.color,
        if (c.csmModule != null) 'csm_module': c.csmModule,
        'custom_tags': c.customTags,
        'admin_meta': c.adminMeta != null
            ? <String, dynamic>{
                'is_pinned': c.adminMeta!.isPinned,
                'is_hidden': c.adminMeta!.isHidden,
                'notes': c.adminMeta!.notes,
              }
            : <String, dynamic>{},
      };
}
