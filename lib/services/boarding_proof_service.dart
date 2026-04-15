/// AnySkill — Boarding Proof Service (Pet Services Module)
///
/// Daily proof-of-care for overnight pet boarding (פנסיון לכלבים).
/// The provider is prompted ONCE PER DAY (computed in IL local time) to
/// upload one photo and one short video; both are uploaded to Storage and
/// recorded under `boarding_proofs/{jobId}/{YYYYMMDD}` in Firestore.
///
/// On every successful upload the customer receives:
///   1. A chat system message of `type: 'boarding_proof'`
///   2. A push notification ("עדכון יומי מהפנסיון 🐕")
///
/// **Schema gate**: this service is invoked only when the expert's
/// sub-category schema has `dailyProof: true` (see [ServiceSchema]).
///
/// **Privacy**: only the customer + provider can read proof docs.
/// Storage path: `boarding_proofs/{jobId}/{YYYYMMDD}_{kind}.{ext}`
/// Firestore: `boarding_proofs/{jobId}/days/{YYYYMMDD}` —
///            `{photoUrl, videoUrl, postedAt, providerId}`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class BoardingProofService {
  static final _db = FirebaseFirestore.instance;

  /// Returns the YYYYMMDD key for a given DateTime (defaults to now).
  static String dayKey([DateTime? dt]) {
    final d = dt ?? DateTime.now();
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  /// Has today's proof been posted yet for this job? Returns the doc when
  /// present (caller can render the existing photo/video or hide the button).
  static Future<Map<String, dynamic>?> todayProof({required String jobId}) async {
    final snap = await _db
        .collection('boarding_proofs')
        .doc(jobId)
        .collection('days')
        .doc(dayKey())
        .get();
    return snap.exists ? snap.data() : null;
  }

  /// Stream of all daily proofs for a job — used by the customer's
  /// "Order Updates" view.
  static Stream<List<Map<String, dynamic>>> streamProofsForJob(String jobId) {
    return _db
        .collection('boarding_proofs')
        .doc(jobId)
        .collection('days')
        .orderBy('postedAt', descending: true)
        .limit(60)
        .snapshots()
        .map((q) => q.docs.map((d) => {...d.data(), '_dayKey': d.id}).toList());
  }

  // ──────────────────────────────────────────────────────────────────────
  // UPLOAD
  // ──────────────────────────────────────────────────────────────────────

  /// Picks an image from the camera, uploads it, and merges the URL onto
  /// today's proof doc. Returns the download URL on success.
  static Future<String?> uploadDailyPhoto({
    required String jobId,
  }) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    final key = dayKey();
    final ref = FirebaseStorage.instance
        .ref('boarding_proofs/$jobId/${key}_photo.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _mergeDayDoc(jobId: jobId, key: key, fields: {'photoUrl': url});
    debugPrint('[BoardingProof] photo uploaded for $jobId/$key');
    return url;
  }

  /// Picks a short video from the camera (max 30 s recommended), uploads,
  /// and merges the URL onto today's proof doc.
  static Future<String?> uploadDailyVideo({
    required String jobId,
  }) async {
    final picker = ImagePicker();
    final xfile = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 30),
    );
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    final key = dayKey();
    final ref = FirebaseStorage.instance
        .ref('boarding_proofs/$jobId/${key}_video.mp4');
    await ref.putData(bytes, SettableMetadata(contentType: 'video/mp4'));
    final url = await ref.getDownloadURL();
    await _mergeDayDoc(jobId: jobId, key: key, fields: {'videoUrl': url});
    debugPrint('[BoardingProof] video uploaded for $jobId/$key');
    return url;
  }

  /// Internal — upserts a day doc and posts the customer-facing notice
  /// when the day becomes "complete" (both photo + video present).
  static Future<void> _mergeDayDoc({
    required String jobId,
    required String key,
    required Map<String, dynamic> fields,
  }) async {
    final auth = FirebaseAuth.instance.currentUser;
    final docRef = _db
        .collection('boarding_proofs')
        .doc(jobId)
        .collection('days')
        .doc(key);

    // Read job context for the notification
    final jobSnap = await _db.collection('jobs').doc(jobId).get();
    final job = jobSnap.data() ?? const {};
    final customerId = job['customerId'] as String? ?? '';
    final chatRoomId = job['chatRoomId'] as String? ?? '';
    final providerName = job['expertName'] as String? ?? '';

    await docRef.set({
      ...fields,
      'jobId': jobId,
      'providerId': auth?.uid ?? '',
      'postedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Read merged doc to decide whether the day is "complete"
    final after = await docRef.get();
    final data = after.data() ?? {};
    final isComplete =
        (data['photoUrl'] as String?)?.isNotEmpty == true &&
            (data['videoUrl'] as String?)?.isNotEmpty == true;

    // Post chat message + notification on EACH upload (don't wait for both —
    // customers are happy to see incremental updates).
    try {
      if (chatRoomId.isNotEmpty) {
        await _db
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': auth?.uid ?? '',
          'senderName': providerName,
          'message': isComplete
              ? '🐕 עדכון יומי מהפנסיון — תמונה + וידאו זמינים'
              : (fields.containsKey('photoUrl')
                  ? '🐕 עדכון יומי מהפנסיון — תמונה חדשה'
                  : '🐕 עדכון יומי מהפנסיון — וידאו חדש'),
          'type': 'boarding_proof',
          'jobId': jobId,
          'dayKey': key,
          if (data['photoUrl'] != null) 'photoUrl': data['photoUrl'],
          if (data['videoUrl'] != null) 'videoUrl': data['videoUrl'],
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
    } catch (e) {
      debugPrint('[BoardingProof] chat post failed: $e');
    }

    try {
      if (customerId.isNotEmpty) {
        await _db.collection('notifications').add({
          'userId': customerId,
          'title': 'עדכון יומי מהפנסיון 🐕',
          'body': 'יש לך עדכון חדש על הכלב שלך',
          'type': 'boarding_proof',
          'jobId': jobId,
          'dayKey': key,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[BoardingProof] notification failed: $e');
    }
  }
}
