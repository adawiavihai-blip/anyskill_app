import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'cached_readers.dart';

/// Media-picking + Firebase Storage upload helpers used by Edit Profile.
///
/// Extracted from `_pickProfileImage`, `_pickAndCompressGalleryImage`,
/// `_pickCertificationImage`, `_pickAndUploadVerificationVideo` in §85
/// (2026-05-14). The screen still owns:
///   • setState + loading flags
///   • Error UI feedback (ErrorMapper.show + SnackBar)
///   • Mount checks before applying results
///
/// The service does only the I/O — picker, byte read, base64 encode, or
/// Storage upload. Returns the result; throws on picker/network errors
/// for the caller to handle (matches legacy try/catch placement).
class ProfileMediaService {
  ProfileMediaService._();

  static const int _profileImageMaxEncodedBytes = 800 * 1024; // 800 KB

  /// Picks a profile image and returns it as a `data:image/jpeg;base64,...`
  /// URI ready to write directly to `users/{uid}.profileImage`.
  ///
  /// Returns null when the user cancelled the picker.
  /// Returns the special string [profileImageTooLargeSentinel] when the
  /// encoded blob exceeds the 800 KB safety cap (caller shows the
  /// "image too large" Hebrew snackbar).
  ///
  /// Throws on picker errors — caller wraps in try/catch + ErrorMapper.
  static Future<String?> pickAndEncodeProfileImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 50,
    );
    if (image == null) return null; // user cancelled
    final Uint8List bytes = await image.readAsBytes();
    final encoded = base64Encode(bytes);
    if (encoded.length > _profileImageMaxEncodedBytes) {
      return profileImageTooLargeSentinel;
    }
    return 'data:image/jpeg;base64,$encoded';
  }

  /// Sentinel returned by [pickAndEncodeProfileImage] when the picked
  /// image is too large after base64 encoding. Caller maps this to the
  /// Hebrew "תמונה גדולה מדי" snackbar.
  static const String profileImageTooLargeSentinel = '__TOO_LARGE__';

  /// Picks a gallery image, compresses to JPEG, uploads to Firebase
  /// Storage at `gallery/{uid}/g_{timestamp}.jpg`, and returns the
  /// HTTPS download URL ready to write to `gallery: [String]`.
  ///
  /// **Migrated from base64 → Storage 2026-05-14** to fix two issues
  /// reported by רועי צברי:
  ///   1. INTERNAL ASSERTION FAILED on save (the watch-stream race
  ///      that fires when a large doc update fans out to multiple
  ///      listeners — 10 base64 images at ~100KB each would push
  ///      the user doc past Firestore's 1MB document cap, causing
  ///      a write rejection that manifested as a watch-stream race).
  ///   2. The user wants 10 gallery images. With Storage, doc size
  ///      stays trivial (10 URLs × ~120 chars = 1.2 KB) and the
  ///      individual files can be up to 10 MB each.
  ///
  /// Returns null when the user cancelled the picker.
  /// Throws on picker/upload errors (caller wraps in ErrorMapper).
  ///
  /// _Legacy mode (no uid):_ when no uid is provided, falls back to
  /// the old base64-encoded behavior so call sites that haven't
  /// migrated yet keep working. Gallery rendering already handles
  /// both base64 and HTTPS via `_buildGalleryImage`.
  static Future<String?> pickAndCompressGalleryImage({String? uid}) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 75,
    );
    if (image == null) return null;
    final Uint8List bytes = await image.readAsBytes();

    // Storage path: gallery/{uid}/g_{timestamp}.jpg
    //
    // 2026-05-15 (live bug, רועי צברי): previously this method silently
    // fell back to base64 when Storage upload failed. Base64 in the
    // user doc pushed the doc near 1 MB and triggered INTERNAL
    // ASSERTION FAILED (watch-stream race) on the next save. That's
    // why "the save shows 'connection error', refresh fixes it" —
    // the silent base64 fallback was masking the real upload failure.
    //
    // New behaviour: retry Storage upload up to 3 times (0.5s + 2s
    // backoff). If ALL retries fail, throw a clear exception so the
    // caller's catch block can show a real error to the user. Base64
    // fallback only fires if no uid is provided (legacy callers).
    if (uid != null && uid.isNotEmpty) {
      // 2026-05-15 — Roi's "sometimes uploads, sometimes shows error":
      // Storage is genuinely flaky on cold-startup paths. The previous
      // 3 attempts × 0/500ms/2s backoff with 20s timeout each gave a
      // total of ~63s patience, but the 20s timeout was cutting off
      // legitimate slow uploads (first-time TLS handshake on Storage's
      // CDN can take 10-15s on iOS Safari + slow networks).
      //
      // New config: 5 attempts × 30s timeout + 0/1s/3s/6s/12s backoff.
      // Total worst case: ~172s — long, but the user sees the loading
      // spinner the whole time and the upload eventually succeeds.
      // Much better than "error → user retries → maybe works".
      const backoffs = [
        Duration.zero,
        Duration(seconds: 1),
        Duration(seconds: 3),
        Duration(seconds: 6),
        Duration(seconds: 12),
      ];
      Object? lastError;
      for (int attempt = 0; attempt < backoffs.length; attempt++) {
        if (attempt > 0) await Future.delayed(backoffs[attempt]);
        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          // Unique filename per attempt — defensive in case a partial
          // upload from a previous attempt is in a weird state on the
          // CDN. The cost is negligible (Storage doesn't bill for
          // small objects).
          final ref = FirebaseStorage.instance
              .ref()
              .child('gallery')
              .child(uid)
              .child('g_${ts}_$attempt.jpg');
          await ref
              .putData(
                bytes,
                SettableMetadata(contentType: 'image/jpeg'),
              )
              .timeout(const Duration(seconds: 30));
          final url = await ref.getDownloadURL();
          debugPrint(
              '[ProfileMediaService] Gallery upload OK (attempt ${attempt + 1}/${backoffs.length}): ${bytes.length ~/ 1024} KB → $url');
          return url;
        } catch (e) {
          lastError = e;
          debugPrint(
              '[ProfileMediaService] Storage upload attempt ${attempt + 1}/${backoffs.length} failed: $e');
        }
      }
      // All retries failed — throw so the caller can show a real error
      // and the user knows to try again. DO NOT fall back to base64 —
      // that creates the doc-size-pressure bug we're trying to avoid.
      throw Exception(
          'העלאת התמונה לשרת נכשלה — בדוק/י את החיבור ונסה/י שוב. (${lastError ?? "unknown"})');
    }

    // Legacy / fallback: base64-encode and return as raw string. Only
    // hit when uid is null (extremely rare — pre-§10.8.0 callers).
    final encoded = base64Encode(bytes);
    if (encoded.length > 150000) {
      debugPrint(
        '[ProfileMediaService] Gallery image is ${encoded.length ~/ 1024} KB '
        'after compression — consider a lower-res source.',
      );
    }
    return encoded;
  }

  /// Picks a certification image (slightly larger budget — 800px, q65).
  /// Returns raw base64 (no data URI prefix) or null on cancel.
  static Future<String?> pickAndEncodeCertificationImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 65,
    );
    if (image == null) return null;
    final Uint8List bytes = await image.readAsBytes();
    return base64Encode(bytes);
  }

  /// Picks a verification video (max 60 sec), uploads it to
  /// `users/{uid}/verification_video.mp4` in Firebase Storage, then writes
  /// the downloadURL + resets the admin-verified flag.
  ///
  /// Returns null when the user cancelled the picker. Returns the
  /// downloadURL on success.
  ///
  /// [onProgress] receives 0.0 → 1.0 updates as bytes upload — caller
  /// uses this to drive a progress indicator in the UI.
  ///
  /// Throws on picker / upload / Firestore errors. Caller wraps in
  /// try/catch + Hebrew error snackbar.
  static Future<String?> uploadVerificationVideo({
    required String uid,
    required void Function(double progress) onProgress,
  }) async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (video == null) return null;

    final ref = FirebaseStorage.instance.ref(
      'users/$uid/verification_video.mp4',
    );
    final bytes = await video.readAsBytes();
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: 'video/mp4'),
    );

    task.snapshotEvents.listen((snap) {
      final progress = snap.bytesTransferred /
          (snap.totalBytes == 0 ? 1 : snap.totalBytes);
      onProgress(progress);
    });

    await task;
    final downloadUrl = await ref.getDownloadURL();

    // Save URL + reset admin-verified flag so admin re-approves.
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'verificationVideoUrl': downloadUrl,
      'videoVerifiedByAdmin': false,
    });
    // CLAUDE.md §61 invalidation contract.
    CachedReaders.invalidateProvider(uid);

    return downloadUrl;
  }
}
