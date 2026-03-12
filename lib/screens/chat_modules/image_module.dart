import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

class ImageModule {
  static final ImagePicker _picker = ImagePicker();

  static Future<String?> uploadImage(String chatRoomId) async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return null;

    Uint8List fileBytes = await file.readAsBytes();
    String fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    Reference ref = FirebaseStorage.instance.ref().child('chats/$chatRoomId/$fileName');
    
    await ref.putData(fileBytes);
    return await ref.getDownloadURL();
  }
}