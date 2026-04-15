/// AnySkill — Pet Update Service (Pet Stay Tracker v13.0.0)
///
/// Owns the `jobs/{jobId}/petStay/data/updates/{updateId}` feed.
/// Step 6: walk-related events (pee/poop/walk_completed/walk_started).
/// Step 7+: media (photo/video/note), daily reports, reactions, replies.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/pet_update.dart';

class PetUpdateService {
  PetUpdateService._();
  static final instance = PetUpdateService._();

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _col(String jobId) => _db
      .collection('jobs')
      .doc(jobId)
      .collection('petStay')
      .doc('data')
      .collection('updates');

  /// Reverse-chronological stream for the feed UI. Capped so a multi-week
  /// stay doesn't load hundreds of entries at once — Step 8 can paginate.
  Stream<List<PetUpdate>> stream(String jobId) => _col(jobId)
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => PetUpdate.fromMap(d.id, d.data()))
          .toList());

  /// Generic creator — used by the specialised writers below and by
  /// Step 7's media upload flow.
  Future<String> write({
    required String jobId,
    required PetUpdate update,
  }) async {
    final ref = await _col(jobId).add(update.toMap());
    return ref.id;
  }

  Future<String> writeMarker({
    required String jobId,
    required String customerId,
    required String expertId,
    required String type, // 'pee' | 'poop'
    required String walkId,
    double? lat,
    double? lng,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? expertId;
    return write(
      jobId: jobId,
      update: PetUpdate(
        type: type,
        providerId: uid,
        timestamp: DateTime.now(),
        customerId: customerId,
        expertId: expertId,
        walkId: walkId,
        lat: lat,
        lng: lng,
      ),
    );
  }

  Future<String> writeWalkCompleted({
    required String jobId,
    required String customerId,
    required String expertId,
    required String walkId,
    required double distanceKm,
    required int durationSeconds,
    required int steps,
    required String pacePerKm,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? expertId;
    return write(
      jobId: jobId,
      update: PetUpdate(
        type: 'walk_completed',
        providerId: uid,
        timestamp: DateTime.now(),
        customerId: customerId,
        expertId: expertId,
        walkId: walkId,
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
        steps: steps,
        pacePerKm: pacePerKm,
      ),
    );
  }

  /// Writes a free-text note to the feed.
  Future<String> writeNote({
    required String jobId,
    required String customerId,
    required String expertId,
    required String text,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? expertId;
    return write(
      jobId: jobId,
      update: PetUpdate(
        type: 'note',
        providerId: uid,
        timestamp: DateTime.now(),
        customerId: customerId,
        expertId: expertId,
        text: text.trim(),
      ),
    );
  }

  /// Uploads a photo (compressed bytes) to Storage and writes the feed
  /// entry. Returns the new update id.
  Future<String> uploadPhoto({
    required String jobId,
    required String customerId,
    required String expertId,
    required Uint8List bytes,
    required String ext,
    String? caption,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? expertId;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'boarding_proofs/$jobId/feed/photo_$ts.$ext';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
    final url = await ref.getDownloadURL();
    return write(
      jobId: jobId,
      update: PetUpdate(
        type: 'photo',
        providerId: uid,
        timestamp: DateTime.now(),
        customerId: customerId,
        expertId: expertId,
        mediaUrl: url,
        mediaType: 'image',
        text: (caption == null || caption.trim().isEmpty)
            ? null
            : caption.trim(),
      ),
    );
  }

  /// Step 10 — writes a daily_report feed entry. `reportData` shape is
  /// validated loosely; see [PetUpdate.reportData] for the expected keys.
  Future<String> writeDailyReport({
    required String jobId,
    required String customerId,
    required String expertId,
    required Map<String, dynamic> reportData,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? expertId;
    return write(
      jobId: jobId,
      update: PetUpdate(
        type: 'daily_report',
        providerId: uid,
        timestamp: DateTime.now(),
        customerId: customerId,
        expertId: expertId,
        reportData: reportData,
      ),
    );
  }

  // ── Step 9 — Reactions + Replies ─────────────────────────────────

  /// Toggles the current user's reaction on an update. If they already
  /// picked [emoji], it's removed; if they picked a different one, it's
  /// switched; if they had no reaction, it's added.
  ///
  /// We overwrite the whole `reactions` Map rather than using dotted-path
  /// writes — simpler, and the map is tiny in practice.
  Future<void> toggleReaction({
    required String jobId,
    required String updateId,
    required String emoji,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = _col(jobId).doc(updateId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final current = Map<String, String>.from(
      (snap.data()?['reactions'] as Map?) ?? const {},
    );
    if (current[uid] == emoji) {
      current.remove(uid);
    } else {
      current[uid] = emoji;
    }
    await ref.update({'reactions': current});
  }

  /// Appends a reply from the current user. `timestamp` uses client time
  /// because Firestore disallows `serverTimestamp()` inside `arrayUnion`.
  Future<void> addReply({
    required String jobId,
    required String updateId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final reply = {
      'userId': user.uid,
      'userName': user.displayName ?? 'משתמש',
      'text': trimmed,
      'timestamp': Timestamp.now(),
    };
    await _col(jobId).doc(updateId).update({
      'replies': FieldValue.arrayUnion([reply]),
    });
  }

  /// Uploads a video (raw bytes, no re-encode) and writes the feed entry.
  Future<String> uploadVideo({
    required String jobId,
    required String customerId,
    required String expertId,
    required Uint8List bytes,
    required String ext,
    String? caption,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? expertId;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'boarding_proofs/$jobId/feed/video_$ts.$ext';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'video/$ext'));
    final url = await ref.getDownloadURL();
    return write(
      jobId: jobId,
      update: PetUpdate(
        type: 'video',
        providerId: uid,
        timestamp: DateTime.now(),
        customerId: customerId,
        expertId: expertId,
        mediaUrl: url,
        mediaType: 'video',
        text: (caption == null || caption.trim().isEmpty)
            ? null
            : caption.trim(),
      ),
    );
  }
}
