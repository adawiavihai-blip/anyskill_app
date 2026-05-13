/// Sound Studio §53 — `sound_system_log` writes + reads.
///
/// Append-only audit trail of every settings change, upload, warning, and
/// AudioService lifecycle event surfaced in the admin SystemLogsTab.
///
/// Categories (mirrors the mockup logs.html):
///   change   — admin updated event_sounds or sounds map
///   upload   — admin uploaded a new sound file
///   warning  — system detected anomaly (high mute %, etc.)
///   system   — informational (Firestore sync, iOS unlock, init)
///   error    — pre-buffering failed, Firestore write failed, etc.
///
/// All writes carry `expireAt` = now + 90d so a future GCP TTL policy can
/// auto-delete (same convention as error_logs/activity_log §19).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum SoundsLogType { change, upload, warning, system, error }

extension SoundsLogTypeName on SoundsLogType {
  String get wireName => name; // 'change' | 'upload' | ...
}

class SoundsLogService {
  SoundsLogService._();
  static final SoundsLogService instance = SoundsLogService._();

  static const _collection = 'sound_system_log';
  static const _ttlDays = 90;

  CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection(_collection);

  /// Best-effort write. Never throws — sound logging is observational.
  Future<void> write({
    required SoundsLogType type,
    required String title,
    required String description,
    String? actor,
    String? platform,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final now = DateTime.now();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await _ref.add({
        'type': type.wireName,
        'title': title,
        'description': description,
        'actor': actor ?? (uid ?? 'מערכת'),
        'platform': platform ?? _platformLabel(),
        'timestamp': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(
          now.add(const Duration(days: _ttlDays)),
        ),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      });
    } catch (e) {
      debugPrint('SoundsLogService.write error: $e');
    }
  }

  /// Newest-first stream limited to [limit] entries. Optional filter by
  /// [type] — pass null for all categories.
  Stream<List<SoundsLogEntry>> stream({
    SoundsLogType? type,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q =
        _ref.orderBy('timestamp', descending: true).limit(limit);
    if (type != null) q = q.where('type', isEqualTo: type.wireName);
    return q.snapshots().map(
          (snap) => snap.docs.map(SoundsLogEntry.fromDoc).toList(),
        );
  }

  /// One-shot fetch for the "טען עוד 20" pagination button. Returns the next
  /// page after [startAfter] (a doc previously emitted by stream/fetch).
  Future<List<SoundsLogEntry>> fetchMore({
    SoundsLogType? type,
    required DocumentSnapshot startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> q = _ref
        .orderBy('timestamp', descending: true)
        .startAfterDocument(startAfter)
        .limit(limit);
    if (type != null) q = q.where('type', isEqualTo: type.wireName);
    final snap = await q.get();
    return snap.docs.map(SoundsLogEntry.fromDoc).toList();
  }

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'system';
    }
  }
}

class SoundsLogEntry {
  final String id;
  final SoundsLogType type;
  final String title;
  final String description;
  final String actor;
  final String platform;
  final DateTime? timestamp;
  final Map<String, dynamic> metadata;
  final DocumentSnapshot rawDoc;

  const SoundsLogEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.actor,
    required this.platform,
    required this.timestamp,
    required this.metadata,
    required this.rawDoc,
  });

  factory SoundsLogEntry.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    final typeStr = data['type'] as String? ?? 'system';
    final type = SoundsLogType.values.firstWhere(
      (t) => t.wireName == typeStr,
      orElse: () => SoundsLogType.system,
    );
    final ts = data['timestamp'];
    return SoundsLogEntry(
      id: doc.id,
      type: type,
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      actor: (data['actor'] as String?) ?? 'מערכת',
      platform: (data['platform'] as String?) ?? 'system',
      timestamp: ts is Timestamp ? ts.toDate() : null,
      metadata: (data['metadata'] is Map<String, dynamic>)
          ? data['metadata'] as Map<String, dynamic>
          : const {},
      rawDoc: doc,
    );
  }
}
