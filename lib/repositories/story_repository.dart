import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/story.dart';

/// Handles ALL Firebase operations for the Stories system.
///
/// No UI code, no BuildContext, no setState. Pure data layer.
/// Every method either returns data or throws — the provider handles errors.
class StoryRepository {
  StoryRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _db       = firestore ?? FirebaseFirestore.instance,
        _storage  = storage   ?? FirebaseStorage.instance,
        _auth     = auth      ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// Test-only: creates an instance without touching Firebase singletons.
  /// Any method that accesses the fields will throw LateInitializationError.
  StoryRepository.dummy();

  late final FirebaseFirestore  _db;
  late final FirebaseStorage    _storage;
  late final FirebaseAuth       _auth;
  late final FirebaseFunctions  _functions;

  // ── Auth helpers ──────────────────────────────────────────────────────

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User not authenticated');
    return user.uid;
  }

  Future<void> _refreshToken() async {
    try {
      await _auth.currentUser?.getIdToken(true);
    } catch (_) {}
  }

  // ── Read ──────────────────────────────────────────────────────────────

  /// Real-time stream of all active stories (limit 30).
  /// Client-side sorted by timestamp descending.
  Stream<List<Story>> watchActiveStories() {
    return _db
        .collection('stories')
        .where('hasActive', isEqualTo: true)
        .limit(30)
        .snapshots()
        .map((snap) {
      final stories = snap.docs.map(Story.fromFirestore).toList()
        ..sort((a, b) {
          final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
          final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
      // Client-side 24h expiry filter
      return stories.where((s) => !s.isExpired).toList();
    });
  }

  /// Fetch a single story by uid (server source for verification).
  Future<Story?> getStory(String uid) async {
    final doc = await _db
        .collection('stories')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!doc.exists) return null;
    return Story.fromFirestore(doc);
  }

  // ── Upload ────────────────────────────────────────────────────────────

  /// Full upload pipeline: Storage → Firestore → verify → user flags → XP.
  ///
  /// [videoBytes] must be pre-read (no Blob URL dependency).
  /// [onProgress] fires with 0.0–1.0 during the Storage upload.
  ///
  /// Returns the created [Story] on success.
  /// Throws on any failure (auth, storage, firestore).
  Future<Story> uploadStory({
    required Uint8List videoBytes,
    required String fileName,
    required String mimeType,
    void Function(double)? onProgress,
  }) async {
    final authUid = _uid;
    await _refreshToken();

    // 1. Read user profile
    final userDoc = await _db.collection('users').doc(authUid).get();
    final userData    = userDoc.data() ?? {};
    final name        = userData['name']         as String? ?? 'ספק';
    final avatar      = userData['profileImage'] as String? ?? '';
    final serviceType = userData['serviceType']  as String? ?? '';

    // 2. Upload to Storage
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'mp4';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'stories/${authUid}_$ts.$ext';

    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putData(
      videoBytes,
      SettableMetadata(contentType: mimeType),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      });
    }

    final snapshot = await uploadTask;
    final videoUrl = await snapshot.ref.getDownloadURL();

    // 3. Create story document
    final now       = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    final story = Story(
      uid:            authUid,
      expertName:     name,
      videoUrl:       videoUrl,
      thumbnailUrl:   avatar,
      providerName:   name,
      providerAvatar: avatar,
      serviceType:    serviceType,
      timestamp:      now,
      expiresAt:      expiresAt,
      hasActive:      true,
      views:          0,
      viewCount:      0,
      likeCount:      0,
      likedBy:        const [],
    );

    await _db.collection('stories').doc(authUid).set(story.toJson());

    // 4. Server verification
    final verified = await getStory(authUid);
    if (verified == null || verified.videoUrl != videoUrl) {
      throw Exception('הסטורי לא נשמר בשרת — ייתכן שאין הרשאה');
    }

    // 5. Update user ranking signals
    await _db.collection('users').doc(authUid).update({
      'hasActiveStory': true,
      'storyTimestamp': Timestamp.fromDate(now),
    });

    // 6. XP + activity log (fire-and-forget)
    _functions
        .httpsCallable('updateUserXP')
        .call({'userId': authUid, 'eventId': 'story_upload'})
        .ignore();

    _db.collection('activity_log').add({
      'type':        'story_upload',
      'userId':      authUid,
      'expertName':  name,
      'serviceType': serviceType,
      'createdAt':   FieldValue.serverTimestamp(),
      'priority':    'normal',
      'title':       '📱 סטורי חדש: $name',
      'detail':      'שירות: $serviceType',
      'expireAt':    Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30))),
    }).ignore();

    return verified;
  }

  // ── Delete ────────────────────────────────────────────────────────────

  Future<void> deleteStory(String storyUid, String? videoUrl) async {
    // 1. Delete from Storage (best-effort)
    if (videoUrl != null && videoUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(videoUrl).delete();
      } catch (e) {
        debugPrint('[StoryRepository] Storage delete failed (non-fatal): $e');
      }
    }

    // 2. Delete Firestore doc
    await _db.collection('stories').doc(storyUid).delete();

    // 3. Clear ranking signals on user doc
    await _db.collection('users').doc(storyUid).update({
      'hasActiveStory': false,
      'storyTimestamp': null,
    });
  }

  // ── Engagement ────────────────────────────────────────────────────────

  Future<void> incrementViewCount(String storyUid) async {
    await _db.collection('stories').doc(storyUid).update({
      'viewCount': FieldValue.increment(1),
    });
  }

  Future<void> likeStory(String storyUid) async {
    final userId = _uid;
    await _db.collection('stories').doc(storyUid).update({
      'likeCount': FieldValue.increment(1),
      'likedBy':   FieldValue.arrayUnion([userId]),
    });
  }
}
