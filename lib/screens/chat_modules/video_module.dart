import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

/// Pick + upload a video from the user's gallery into
/// `chats/{chatRoomId}/vid_{ts}.mp4`. Returns the Firebase Storage
/// download URL on success, or `null` if the user cancelled / the
/// upload failed.
///
/// Capped at 60 seconds to avoid ballooning storage costs on a chat
/// thread. Quality is source-native (ImagePicker doesn't expose a
/// compression flag for videos on web).
class VideoModule {
  static final ImagePicker _picker = ImagePicker();

  static Future<String?> uploadVideo(String chatRoomId) async {
    try {
      final XFile? file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 1),
      );
      if (file == null) return null; // user cancelled

      final Uint8List bytes = await file.readAsBytes();
      final ext = _extForName(file.name);
      final fileName = 'vid_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('chats/$chatRoomId/$fileName');

      final metadata = SettableMetadata(contentType: _mimeForExt(ext));
      await ref.putData(bytes, metadata);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[VideoModule] uploadVideo failed: $e');
      return null;
    }
  }

  static String _extForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mov')) return 'mov';
    if (lower.endsWith('.webm')) return 'webm';
    if (lower.endsWith('.m4v')) return 'm4v';
    return 'mp4';
  }

  static String _mimeForExt(String ext) {
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return 'video/mp4';
    }
  }
}
