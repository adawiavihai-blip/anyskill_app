import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';

class ChatHelpers {
  // --- חלק 1: טיפול במיקום ---
  static Future<String?> pickLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      // שימוש ב-Raw String כדי למנוע שגיאות $ בטרמינל
      return "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";
    } catch (e) {
      debugPrint("Location Error: $e");
      return null;
    }
  }

  // --- חלק 2: טיפול בתמונות ---
  static Future<String?> uploadImage(String chatRoomId) async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return null;

    Uint8List fileBytes = await file.readAsBytes();
    String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    Reference ref = FirebaseStorage.instance.ref().child('chats/$chatRoomId/$fileName');
    
    await ref.putData(fileBytes);
    return await ref.getDownloadURL();
  }
}