import 'package:record/record.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class AudioModule {
  static final AudioRecorder _recorder = AudioRecorder();

  static Future<void> start() async {
    if (await _recorder.hasPermission()) {
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(const RecordConfig(), path: path);
    }
  }

  static Future<String?> stopAndUpload(String chatRoomId) async {
    final path = await _recorder.stop();
    if (path == null) return null;

    String fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    Reference ref = FirebaseStorage.instance.ref().child('chats/$chatRoomId/$fileName');
    
    if (kIsWeb) {
      // טיפול מיוחד ל-WEB (QA חשוב!)
      // במידה ואתה עובד ב-Web, הקוד צריך להעלות כ-Blob
      return null; // ניתן להרחיב בהמשך לפי הצורך ב-Web
    } else {
      await ref.putFile(File(path));
    }
    return await ref.getDownloadURL();
  }
}