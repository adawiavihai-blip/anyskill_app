import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart' as ff;

import '../models/activity_log_entry.dart';

/// Read / write / undo for `admin_activity_log/{logId}`. Server-side writes
/// happen via the `logAdminAction` Cloud Function (audit trail integrity);
/// reads stream directly from Firestore (admin-only by security rule).
class ActivityLogService {
  ActivityLogService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ff.FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _fn = functions ?? ff.FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ff.FirebaseFunctions _fn;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('admin_activity_log');

  /// Live feed for the Activity Log panel — newest first.
  Stream<List<ActivityLogEntry>> watch({int limit = 50}) {
    return _col
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ActivityLogEntry.fromDoc).toList());
  }

  /// Filtered feed — used by the dropdown filter inside the panel.
  Stream<List<ActivityLogEntry>> watchByTarget(
    ActivityTargetType target, {
    int limit = 50,
  }) {
    return _col
        .where('target_type', isEqualTo: target.wire)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ActivityLogEntry.fromDoc).toList());
  }

  /// Writes one log entry through the `logAdminAction` Cloud Function. The
  /// CF stamps `admin_uid`, `admin_name`, `created_at` server-side so the
  /// audit trail can't be forged.
  Future<void> log({
    required ActivityActionType actionType,
    required ActivityTargetType targetType,
    required String targetId,
    required String targetName,
    required Map<String, dynamic> payloadBefore,
    required Map<String, dynamic> payloadAfter,
    bool isReversible = true,
  }) async {
    if (_auth.currentUser == null) return; // silent no-op for unauth contexts
    final callable = _fn.httpsCallable('logAdminAction');
    await callable.call(<String, dynamic>{
      'action_type': actionType.wire,
      'target_type': targetType.wire,
      'target_id': targetId,
      'target_name': targetName,
      'payload_before': payloadBefore,
      'payload_after': payloadAfter,
      'is_reversible': isReversible,
    });
  }

  /// Undoes [entry] by re-applying `payload_before` server-side. Returns the
  /// new "undo" log entry id so the UI can highlight it.
  Future<String> undo(ActivityLogEntry entry) async {
    final callable = _fn.httpsCallable('undoAdminAction');
    final res = await callable.call(<String, dynamic>{'log_id': entry.id});
    final data = res.data;
    if (data is Map && data['undo_log_id'] is String) {
      return data['undo_log_id'] as String;
    }
    return '';
  }

  /// Convenience used by Cmd+Z — undo the latest reversible entry that this
  /// admin authored and that hasn't already been reversed.
  Future<ActivityLogEntry?> undoLast() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final snap = await _col
        .where('admin_uid', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(20) // small window — most undo intents are very recent
        .get();
    for (final doc in snap.docs) {
      final entry = ActivityLogEntry.fromDoc(doc);
      if (entry.isReversible && !entry.isReversed) {
        await undo(entry);
        return entry;
      }
    }
    return null;
  }
}
